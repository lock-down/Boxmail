import BoxmailCore
import Foundation

@MainActor final class BackendService {
  static let shared = BackendService()
  private var process: Process?
  private var port = 0
  private let token = UUID().uuidString + UUID().uuidString
  private let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 190
    config.timeoutIntervalForResource = 240
    return URLSession(configuration: config)
  }()
  var dataDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Boxmail", isDirectory: true)
  }
  func start() async throws {
    if process?.isRunning == true { return }
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
    environment["BOXMAIL_DATA"] = dataDirectory.path
    environment["BOXMAIL_TOKEN"] = token
    environment["BOXMAIL_PORT"] = String(port)
    child.environment = environment
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    try child.run()
    process = child
    for _ in 0..<60 {
      guard child.isRunning else { throw failure("本机邮件服务启动失败") }
      do {
        let _: AppSnapshot = try await request("/state", timeout: 1)
        return
      } catch { try await Task.sleep(for: .milliseconds(100)) }
    }
    stop()
    throw failure("本机邮件服务启动超时")
  }
  func stop() {
    process?.terminate()
    process = nil
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
