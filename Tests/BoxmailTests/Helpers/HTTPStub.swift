import Foundation

// Each route owns its response, so parallel tests cannot overwrite one another.
final class HTTPStub {
  let path: String
  let session: URLSession
  private let lock = NSLock()
  private var pending: URLProtocol?
  private var started = false
  private let data: Data
  private let status: Int
  private let delayed: Bool

  init(path: String, data: Data, status: Int = 200, delayed: Bool = false) {
    self.path = path
    self.data = data
    self.status = status
    self.delayed = delayed
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubHTTPProtocol.self]
    session = URLSession(configuration: config)
    StubHTTPProtocol.register(self)
  }

  fileprivate func start(_ request: URLProtocol) {
    lock.lock()
    pending = request
    started = true
    lock.unlock()
    if !delayed { respond() }
  }

  func waitUntilStarted() async throws {
    for _ in 0..<500 {
      if lock.withLock({ started }) { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    throw URLError(.timedOut)
  }

  func respond() {
    let request = lock.withLock {
      let value = pending
      pending = nil
      return value
    }
    guard let request, let url = request.request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: status, httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"])
    else { return }
    request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
    request.client?.urlProtocol(request, didLoad: data)
    request.client?.urlProtocolDidFinishLoading(request)
  }

  func close() {
    session.invalidateAndCancel()
    StubHTTPProtocol.unregister(path)
  }
}

private final class StubHTTPProtocol: URLProtocol {
  private static let lock = NSLock()
  private static var routes: [String: HTTPStub] = [:]

  static func register(_ stub: HTTPStub) { lock.withLock { routes[stub.path] = stub } }
  static func unregister(_ path: String) { lock.withLock { routes[path] = nil } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let path = request.url?.path, let stub = Self.lock.withLock({ Self.routes[path] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    stub.start(self)
  }
  override func stopLoading() {}
}
