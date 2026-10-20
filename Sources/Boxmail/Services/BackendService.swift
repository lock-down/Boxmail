import BoxmailCore
import Foundation

@MainActor final class BackendService {
  static let shared = BackendService()
  private var process: Process?
  private var directoryLease: DataDirectoryLease?
  private var activeDirectory: URL?
  private let storageKey = "BoxmailDataDirectoryConfiguration"
  var startupNotice: String?
  private var port = 0
  private let token = UUID().uuidString + UUID().uuidString
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 190
    config.timeoutIntervalForResource = 900
    return URLSession(configuration: config)
  }()
  var defaultDataDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Boxmail", isDirectory: true)
  }
  var hasDataDirectoryOverride: Bool { ProcessInfo.processInfo.environment["BOXMAIL_DATA"] != nil }
  var dataDirectory: URL {
    activeDirectory ?? (try? configuration().resolvedDirectory(
      defaultDirectory: defaultDataDirectory,
      override: ProcessInfo.processInfo.environment["BOXMAIL_DATA"])) ?? defaultDataDirectory
  }
  var pendingDataDirectory: URL? {
    guard !hasDataDirectoryOverride, let path = try? configuration().pendingDirectory else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
  private func configuration() throws -> DataDirectoryConfiguration {
    if hasDataDirectoryOverride { return DataDirectoryConfiguration() }
    guard let data = UserDefaults.standard.data(forKey: storageKey) else {
      return DataDirectoryConfiguration()
    }
    do { return try JSONDecoder().decode(DataDirectoryConfiguration.self, from: data) }
    catch { throw failure("数据目录配置无法读取。请检查本机偏好配置，原数据目录未作更改。") }
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
    startupNotice = nil
    var value = try configuration()
    let source = try value.resolvedDirectory(defaultDirectory: defaultDataDirectory,
      override: ProcessInfo.processInfo.environment["BOXMAIL_DATA"])
    // A missing custom disk must never create a second, empty mailbox at the saved path.
    let custom = !hasDataDirectoryOverride && value.directory != nil
    if custom && !FileManager.default.fileExists(atPath: source.appendingPathComponent("boxmail.sqlite").path) {
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
        stop()
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
      do { return try DataDirectoryLease(directory: directory, create: create) }
      catch {
        guard (error as NSError).code == 2, attempt < 49 else { throw error }
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
    let child = Process()
    child.executableURL = node
    child.arguments = [backend.path]
    child.currentDirectoryURL = backend.deletingLastPathComponent()
    var environment = ProcessInfo.processInfo.environment
    environment["BOXMAIL_DATA"] = lease.directory.path
    environment["BOXMAIL_TOKEN"] = token
    environment["BOXMAIL_PORT"] = String(port)
    if let demoEnabled = Bundle.main.object(forInfoDictionaryKey: "BoxmailDemoDataEnabled") as? Bool {
      environment["BOXMAIL_DEMO"] = demoEnabled ? "1" : "0"
    }
    child.environment = environment
    child.standardInput = try lease.inheritedFileHandle()
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    process = child
    directoryLease = lease
    activeDirectory = lease.directory
    do {
      for _ in 0..<60 {
        guard child.isRunning else { throw failure("本机邮件服务启动失败") }
        do {
          let _: AppSnapshot = try await request("/state?compact=1", timeout: 1)
          return
        } catch { try await Task.sleep(for: .milliseconds(100)) }
      }
      throw failure("本机邮件服务启动超时")
    } catch {
      stop()
      throw error
    }
  }
  func stop() {
    process?.terminate()
    process = nil
    directoryLease = nil
  }
  func request<T: Decodable>(
    _ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 190
  ) async throws -> T {
    guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { throw failure("接口地址无效") }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = timeout
    request.setValue(token, forHTTPHeaderField: "X-Boxmail-Token")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw failure("本机服务无响应") }
    guard (200..<300).contains(response.statusCode) else {
      let error =
        (try? JSONDecoder().decode(APIError.self, from: data))?.error
        ?? "请求失败 (\(response.statusCode))"
      throw failure(error)
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  func perform(_ path: String, method: String = "POST", body: [String: Any] = [:]) async throws {
    let _: EmptyResponse = try await request(path, method: method, body: body)
  }
  func failure(_ message: String) -> NSError {
    NSError(domain: "Boxmail", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
struct EmptyResponse: Decodable {}
struct APIError: Decodable { let error: String }
struct IDResponse: Decodable { let id: String }
struct ModelsResponse: Decodable { let models: [String] }
struct FileResponse: Decodable { let name, content: String }
struct SendResponse: Decodable {
  let ok: Bool
  let rejected: [String]?
  let warning: String?
}
func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
  try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
}
