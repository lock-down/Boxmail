import BoxmailCore
import Foundation

@MainActor final class BackendService {
  static let shared = BackendService()
  private var process: LocalBackendProcess?
  private var activeDirectory: URL?
  private let storageKey = "BoxmailDataDirectoryConfiguration"
  var startupNotice: String?
  private var port = 0
  private let token = UUID().uuidString + UUID().uuidString
  private let session: URLSession
  let diagnostics: RuntimeDiagnostics
  private var lastExit: (code: Int32, signal: Bool)?
  private var processGeneration = UUID()
  var isRunning: Bool { process?.isRunning == true }
  var hasExited: Bool { activeDirectory != nil && !isRunning }
  var disconnectedMessage: String {
    if let exit = lastExit, exit.signal {
      return "本机邮件服务意外退出（信号 \(exit.code)）。已下载邮件保留，再次同步会重新连接并继续。"
    }
    return "本机邮件服务已退出。已下载邮件保留，再次同步会重新连接并继续。"
  }

  init(session: URLSession? = nil, diagnostics: RuntimeDiagnostics? = nil) {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 190
    config.timeoutIntervalForResource = 900
    self.session = session ?? URLSession(configuration: config)
    self.diagnostics = diagnostics ?? RuntimeDiagnostics(directory: nil)
    if session == nil { self.diagnostics.setDirectory(dataDirectory) }
  }
  var defaultDataDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Boxmail", isDirectory: true)
  }
  var hasDataDirectoryOverride: Bool { ProcessInfo.processInfo.environment["BOXMAIL_DATA"] != nil }
  var dataDirectory: URL {
    activeDirectory
      ?? (try? configuration().resolvedDirectory(
        defaultDirectory: defaultDataDirectory,
        override: ProcessInfo.processInfo.environment["BOXMAIL_DATA"])) ?? defaultDataDirectory
  }
  var pendingDataDirectory: URL? {
    guard !hasDataDirectoryOverride, let path = try? configuration().pendingDirectory else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
  private func configuration() throws -> DataDirectoryConfiguration {
    if hasDataDirectoryOverride { return DataDirectoryConfiguration() }
    guard let data = UserDefaults.standard.data(forKey: storageKey) else {
      return DataDirectoryConfiguration()
    }
    do { return try JSONDecoder().decode(DataDirectoryConfiguration.self, from: data) } catch {
      throw failure("数据目录配置无法读取。请检查本机偏好配置，原数据目录未作更改。")
    }
  }
  private func saveConfiguration(_ value: DataDirectoryConfiguration) throws {
    UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: storageKey)
  }
  func scheduleDataDirectory(_ destination: URL?) throws {
    guard !hasDataDirectoryOverride else { return }
    var value = try configuration()
    value.pendingDirectory = try destination.map {
      try LocalDataStorage.validateDestination(from: dataDirectory, to: $0).path
    }
    try saveConfiguration(value)
  }
  func start() async throws {
    if process?.isRunning == true { return }
    diagnostics.setDirectory(dataDirectory)
    diagnostics.record("service.starting")
    // Release the previous owned lease before trying to acquire it again.
    await stop()
    startupNotice = nil
    var value = try configuration()
    let source = try value.resolvedDirectory(
      defaultDirectory: defaultDataDirectory,
      override: ProcessInfo.processInfo.environment["BOXMAIL_DATA"])
    // A missing custom disk must never create a second, empty mailbox at the saved path.
    let custom = !hasDataDirectoryOverride && value.directory != nil
    if custom
      && !FileManager.default.fileExists(
        atPath: source.appendingPathComponent("boxmail.sqlite").path)
    {
      throw failure("自定义数据目录不可用或缺少数据库：\(source.path)。请接入原磁盘或恢复文件夹后重试。")
    }
    let sourceLease = try await acquireDirectory(source, create: !custom)
    if !hasDataDirectoryOverride, let pending = value.pendingDirectory {
      do {
        guard pending.hasPrefix("/"), !pending.contains("\0") else {
          throw failure("待迁移的数据目录必须是绝对路径，请重新选择。")
        }
        let destination = URL(fileURLWithPath: pending, isDirectory: true)
        let targetLease = try await Task.detached(priority: .userInitiated) {
          try LocalDataStorage.migrate(from: sourceLease, to: destination)
        }.value
        try await launch(in: targetLease)
        value.directory = targetLease.directory.path
        value.pendingDirectory = nil
        try saveConfiguration(value)
        startupNotice = "本机数据已迁移至 \(targetLease.directory.path)。原目录保留在 \(source.path)，可核对后自行处理。"
        return
      } catch {
        await stop()
        value.pendingDirectory = nil
        try saveConfiguration(value)
        startupNotice = "数据目录迁移未完成，继续使用原位置。\(error.localizedDescription)"
      }
    }
    try await launch(in: sourceLease)
  }
  private func acquireDirectory(_ directory: URL, create: Bool) async throws -> DataDirectoryLease {
    // The previous backend may still be closing after the app was reopened immediately.
    for attempt in 0..<50 {
      do { return try DataDirectoryLease(directory: directory, create: create) } catch {
        guard (error as NSError).code == 2, attempt < 49 else { throw error }
        if attempt == 0 {
          let node = Bundle.main.resourceURL!.appendingPathComponent("Runtime/node")
          if await LocalBackendProcess.recoverOrphan(in: directory, executable: node) {
            startupNotice = "已关闭上次退出后残留的本机服务，继续使用原数据。"
          }
        }
        try await Task.sleep(for: .milliseconds(100))
      }
    }
    throw failure("数据目录仍在使用中，请稍后重试。")
  }
  private func launch(in lease: DataDirectoryLease) async throws {
    let resources = Bundle.main.resourceURL!
    let node = resources.appendingPathComponent("Runtime/node")
    let backend = resources.appendingPathComponent("Backend/src/server.js")
    guard FileManager.default.isExecutableFile(atPath: node.path),
      FileManager.default.fileExists(atPath: backend.path)
    else { throw failure("本机服务资源缺失，请通过项目 Run 按钮重新构建") }
    port = Int.random(in: 49152...65000)
    var environment = ProcessInfo.processInfo.environment
    // Keep unrelated development-tool preload, heap and debug flags out of bundled Node.
    environment.removeValue(forKey: "NODE_OPTIONS")
    environment.removeValue(forKey: "NODE_PATH")
    environment["BOXMAIL_DATA"] = lease.directory.path
    environment["BOXMAIL_TOKEN"] = token
    environment["BOXMAIL_PORT"] = String(port)
    environment["BOXMAIL_PARENT_PID"] = String(ProcessInfo.processInfo.processIdentifier)
    if let demoEnabled = Bundle.main.object(forInfoDictionaryKey: "BoxmailDemoDataEnabled") as? Bool
    {
      environment["BOXMAIL_DEMO"] = demoEnabled ? "1" : "0"
    }
    let journal = diagnostics
    let generation = UUID()
    processGeneration = generation
    lastExit = nil
    let child = try LocalBackendProcess(
      executable: node, arguments: [backend.path],
      directory: backend.deletingLastPathComponent(), environment: environment, lease: lease,
      onExit: { [weak self] code, signalled in
        journal.record(
          "service.exited",
          [
            "code": String(code),
            "status": signalled ? "signal" : "exit",
          ])
        Task { @MainActor [weak self] in
          if self?.processGeneration == generation { self?.lastExit = (code, signalled) }
        }
      }, onDiagnostic: { category in journal.record("service.fatal", ["reason": category]) })
    process = child
    activeDirectory = lease.directory
    diagnostics.setDirectory(lease.directory)
    do {
      for _ in 0..<60 {
        guard child.isRunning else { throw failure("本机邮件服务启动失败") }
        do {
          let _: EmptyResponse = try await request("/health", timeout: 1)
          diagnostics.record("service.connected")
          return
        } catch { try await Task.sleep(for: .milliseconds(100)) }
      }
      throw failure("本机邮件服务启动超时")
    } catch {
      await stop()
      throw error
    }
  }
  func stop() async {
    guard let child = process else { return }
    processGeneration = UUID()
    await child.stop()
    if process === child { process = nil }
    diagnostics.record("service.stopped")
  }
  func reconnectAfterExit() async throws {
    guard hasExited, let directory = activeDirectory else { return }
    // Reconnect to the current data directory. A scheduled migration still
    // belongs to the next app launch, not an unexpected backend restart.
    diagnostics.record("service.reconnecting")
    await stop()
    let lease = try await acquireDirectory(directory, create: false)
    try await launch(in: lease)
  }
  nonisolated func request<T: Decodable>(
    _ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 190
  ) async throws -> T {
    try Task.checkCancellation()
    let endpointPort = await port
    let diagnostics = diagnostics
    let started = Date()
    let requestID = UUID().uuidString.lowercased()
    var status: Int?
    var responseData: Data?
    do {
      if await hasExited { throw await failure(disconnectedMessage) }
      guard let url = URL(string: "http://127.0.0.1:\(endpointPort)\(path)") else {
        throw failure("接口地址无效")
      }
      var request = URLRequest(url: url)
      request.httpMethod = method
      request.timeoutInterval = timeout
      request.setValue(token, forHTTPHeaderField: "X-Boxmail-Token")
      request.setValue(requestID, forHTTPHeaderField: "X-Boxmail-Request-ID")
      if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
      }
      try Task.checkCancellation()
      let (data, response) = try await session.data(for: request)
      responseData = data
      try Task.checkCancellation()
      guard let response = response as? HTTPURLResponse else { throw failure("本机服务无响应") }
      status = response.statusCode
      guard (200..<300).contains(response.statusCode) else {
        let error =
          (try? JSONDecoder().decode(APIError.self, from: data))?.error
          ?? "请求失败 (\(response.statusCode))"
        throw failure(error)
      }
      let result = try JSONDecoder().decode(T.self, from: data)
      if Date().timeIntervalSince(started) >= 2 {
        diagnostics.record(
          "api.slow",
          [
            "route": RuntimeDiagnostics.route(path), "method": method,
            "status": String(response.statusCode),
            "requestID": requestID,
            "durationMs": String(Int(Date().timeIntervalSince(started) * 1000)),
          ])
      }
      return result
    } catch {
      if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled {
        var fields = RuntimeDiagnostics.errorFields(error, responseData: responseData)
        fields["requestID"] = requestID
        if let responseData { fields["responseBytes"] = String(responseData.count) }
        fields["route"] = RuntimeDiagnostics.route(path)
        fields["method"] = method
        fields["durationMs"] = String(Int(Date().timeIntervalSince(started) * 1000))
        if let status { fields["status"] = String(status) }
        diagnostics.record("api.failed", fields)
      }
      throw error
    }
  }
  func perform(
    _ path: String, method: String = "POST", body: [String: Any] = [:], timeout: TimeInterval = 190
  ) async throws {
    let _: EmptyResponse = try await request(path, method: method, body: body, timeout: timeout)
  }
  nonisolated func aiEvents(receive: @MainActor (AIStreamEvent) -> Void) async throws {
    let endpointPort = await port
    let requestID = UUID().uuidString.lowercased()
    guard let url = URL(string: "http://127.0.0.1:\(endpointPort)/ai/events") else {
      throw failure("接口地址无效")
    }
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "X-Boxmail-Token")
    request.setValue(requestID, forHTTPHeaderField: "X-Boxmail-Request-ID")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
      throw failure("无法连接 AI 输出流")
    }
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard line.hasPrefix("data: ") else { continue }
      guard line.utf8.count <= 12_000_000 else { throw failure("AI 输出过长") }
      let payload = Data(line.dropFirst(6).utf8)
      do {
        let event = try JSONDecoder().decode(AIStreamEvent.self, from: payload)
        await receive(event)
      } catch {
        var fields = RuntimeDiagnostics.errorFields(error, responseData: payload)
        fields["route"] = "/ai/events"
        fields["method"] = "GET"
        fields["requestID"] = requestID
        diagnostics.record("api.stream.failed", fields)
        throw error
      }
    }
  }
  nonisolated func failure(_ message: String) -> NSError {
    NSError(domain: "Boxmail", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
struct EmptyResponse: Decodable {}
struct APIError: Decodable { let error: String }
struct IDResponse: Decodable { let id: String }
struct ModelsResponse: Decodable {
  let models: [String]
  let details: [AIModel]?
  var catalog: [AIModel] { details ?? models.map { AIModel(id: $0) } }
}
struct FileResponse: Decodable { let name, content: String }
struct SendResponse: Decodable {
  let ok: Bool
  let rejected: [String]?
  let warning: String?
}
func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
}
