import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private final class SyncTransport {
  let id = UUID().uuidString
  let session: URLSession
  let lock = NSLock()
  var finished = false
  var pollsFail = false
  var requests: [URLRequest] = []
  var firstAcknowledged = false
  var loseFirstReply = false
  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Synthetic-Sync": id]
    session = URLSession(configuration: configuration)
    SyncProtocol.register(self)
  }
  func close() {
    session.invalidateAndCancel()
    SyncProtocol.remove(id)
  }
  func reply(_ request: URLRequest) -> (Data, TimeInterval, URLError?) {
    lock.withLock {
      requests.append(request)
      switch request.url?.path {
      case "/sync":
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
          stream.open()
          defer { stream.close() }
          var buffer = [UInt8](repeating: 0, count: 1024)
          while bytes.count < 8192 {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            bytes.append(contentsOf: buffer.prefix(count))
          }
        }
        let body = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        let first = body?["accountId"] as? String == "a"
        if first && loseFirstReply { return (Data(), 0, URLError(.timedOut)) }
        return (Data(#"{"ok":true}"#.utf8), first ? 0.4 : 0, nil)
      case "/sync-status":
        if pollsFail { return (Data(), 0, URLError(.timedOut)) }
        let status = finished ? "completed" : "running"
        let data: [String: Any] = [
          "runningAccounts": finished ? [] : ["a", "b"],
          "folders": [
            [
              "id": "b-in", "accountId": "b", "folder": "inbox", "status": status,
              "downloaded": 27, "total": 1001,
            ]
          ],
          "results": [
            ["accountId": "a", "status": status], ["accountId": "b", "status": status],
          ],
        ]
        return (try! JSONSerialization.data(withJSONObject: data), 0, nil)
      case "/state": return (Data("{}".utf8), 2, nil)
      default: return (Data(#"{"ok":true}"#.utf8), 0, nil)
      }
    }
  }
}
private final class SyncProtocol: URLProtocol {
  static let lock = NSLock()
  static var transports: [String: SyncTransport] = [:]
  var work: Task<Void, Never>?
  static func register(_ value: SyncTransport) { lock.withLock { transports[value.id] = value } }
  static func remove(_ id: String) { lock.withLock { transports[id] = nil } }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    guard let key = request.value(forHTTPHeaderField: "X-Synthetic-Sync"),
      let transport = Self.lock.withLock({ Self.transports[key] })
    else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }
    let (data, delay, error) = transport.reply(request)
    work = Task {
      do {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
      } catch { return }
      if let error {
        client?.urlProtocol(self, didFailWithError: error)
        return
      }
      if request.url?.path == "/sync", delay > 0 {
        transport.lock.withLock { transport.firstAcknowledged = true }
      }
      let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { work?.cancel() }
}

@Suite(.serialized) @MainActor struct MailSyncLifecycleTests {
  private func store(_ transport: SyncTransport) -> MailStore {
    let store = MailStore(
      backend: BackendService(session: transport.session), readMailPassword: { _ in "synthetic" })
    store.accounts = [
      MailAccount(id: "a", email: "a@example.test"), MailAccount(id: "b", email: "b@example.test"),
    ]
    store.syncPollInterval = .milliseconds(10)
    return store
  }
  @Test func progressContinuesWhileOneAccountStartReplyIsDelayedAndFinalRefreshCannotHoldSyncBusy()
    async throws
  {
    let transport = SyncTransport()
    defer { transport.close() }
    let store = store(transport)
    let task = Task { await store.syncAll() }
    for _ in 0..<100 {
      if store.syncSnapshot?.folders.first?.downloaded == 27 { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    #expect(store.syncProgressText == "正在同步 27/1001 封")
    #expect(!transport.lock.withLock { transport.firstAcknowledged })
    transport.lock.withLock { transport.finished = true }
    await task.value
    #expect(!store.busy.contains("sync"))
    #expect(store.error == nil)
    let starts = transport.lock.withLock { transport.requests.filter { $0.url?.path == "/sync" } }
    #expect(starts.count == 2 && starts.allSatisfy { $0.timeoutInterval == 10 })
    store.syncContentRefresh?.cancel()
    await store.syncContentRefresh?.value
  }
  @Test func aLostStartAcknowledgementRejoinsTheAcceptedServerSession() async throws {
    let transport = SyncTransport()
    transport.loseFirstReply = true
    defer { transport.close() }
    let store = store(transport)
    let task = Task { await store.syncAll() }
    for _ in 0..<100 {
      if transport.lock.withLock({
        transport.requests.filter { $0.url?.path == "/sync-status" }.count >= 2
      }) {
        break
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    transport.lock.withLock { transport.finished = true }
    await task.value
    #expect(store.error == nil && !store.busy.contains("sync"))
    store.syncContentRefresh?.cancel()
    await store.syncContentRefresh?.value
  }
  @Test func cancellingTheClientTaskStillDeliversServerStopRequests() async throws {
    let transport = SyncTransport()
    defer { transport.close() }
    let store = store(transport)
    let task = Task { await store.syncAll() }
    for _ in 0..<500 {
      if store.syncSnapshot != nil { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    #expect(store.syncSnapshot != nil)
    task.cancel()
    await task.value
    let cancelledAccounts = transport.lock.withLock {
      transport.requests.filter { $0.url?.path == "/sync/cancel" }.count
    }
    #expect(cancelledAccounts == 2)
    #expect(!store.busy.contains("sync"))
  }
  @Test func failedProgressPollingRequestsBoundedCancellationAndClearsTheBusyIndicator()
    async throws
  {
    let transport = SyncTransport()
    transport.pollsFail = true
    defer { transport.close() }
    let store = store(transport)
    await store.syncAll()
    #expect(!store.busy.contains("sync") && store.syncingAccountIds.isEmpty)
    #expect(store.error?.contains("无法取得同步进度") == true)
    let cancellations = transport.lock.withLock {
      transport.requests.filter { $0.url?.path == "/sync/cancel" }
    }
    #expect(cancellations.count == 2 && cancellations.allSatisfy { $0.timeoutInterval == 5 })
  }
}
