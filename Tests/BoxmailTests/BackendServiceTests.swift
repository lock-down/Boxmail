import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private struct DecodingThread: Decodable {
  let values: [String]
  let wasMainThread: Bool
  private enum CodingKeys: CodingKey { case values }
  init(from decoder: Decoder) throws {
    wasMainThread = Thread.isMainThread
    values = try decoder.container(keyedBy: CodingKeys.self).decode([String].self, forKey: .values)
  }
}

@Test @MainActor func backendLogsTheRequestAndTriggeringRecordFieldWithoutResponseValues()
  async throws
{
  struct Envelope: Decodable {
    struct Message: Decodable { let uid: Int }
    let messages: [Message]
  }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BoxmailDecodeLog-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let payload = Data(
    #"{"messages":[{"id":"synthetic-record","accountId":"synthetic-account","uid":"PRIVATE FIELD VALUE"}]}"#
      .utf8)
  let stub = HTTPStub(path: "/shape-\(UUID())", data: payload)
  defer { stub.close() }
  let journal = RuntimeDiagnostics(directory: directory)
  let backend = BackendService(session: stub.session, diagnostics: journal)
  do {
    let _: Envelope = try await backend.request(stub.path)
    Issue.record("Invalid UID must fail decoding")
  } catch { #expect(error is DecodingError) }
  await journal.flush()
  let log = try String(
    contentsOf: directory.appendingPathComponent("logs/app.jsonl"), encoding: .utf8)
  let entry = try #require(JSONSerialization.jsonObject(with: Data(log.utf8)) as? [String: String])
  #expect(entry["field"] == "$.messages[0].uid")
  #expect(entry["expectedType"] == "integer" && entry["actualType"] == "string")
  #expect(entry["record"] == RuntimeDiagnostics.accountReference("synthetic-record"))
  #expect(entry["account"] == RuntimeDiagnostics.accountReference("synthetic-account"))
  #expect(
    entry["requestID"] == stub.latestRequest?.value(forHTTPHeaderField: "X-Boxmail-Request-ID"))
  #expect(UUID(uuidString: entry["requestID"] ?? "") != nil)
  #expect(!log.contains("PRIVATE FIELD VALUE") && !log.contains("synthetic-record"))
}

@Test @MainActor func committedSettingsRemainSavedWhenUnrelatedMailRefreshFails() async throws {
  var saved = SettingsData()
  saved.preferences.fontSize = 18
  saved.preferences.blockRemoteImages = false
  let settings = HTTPStub(path: "/settings", data: try JSONEncoder().encode(saved))
  let state = HTTPStub(
    path: "/state", data: Data(#"{"error":"Synthetic refresh failure"}"#.utf8),
    status: 502, scope: settings)
  defer {
    settings.close()
    state.close()
  }
  let store = MailStore(backend: BackendService(session: settings.session))
  let refreshed = try await store.saveSettings(ai: saved.ai, preferences: saved.preferences)
  #expect(!refreshed)
  #expect(store.settings.preferences.fontSize == 18)
  #expect(!store.settings.preferences.blockRemoteImages)
}

@Test @MainActor func backendDecodesLargeResponsesOutsideTheUIThread() async throws {
  let values = Array(repeating: String(repeating: "邮件正文", count: 100), count: 4000)
  let stub = HTTPStub(
    path: "/decode-\(UUID().uuidString)",
    data: try JSONSerialization.data(withJSONObject: ["values": values]))
  defer { stub.close() }
  let backend = BackendService(session: stub.session)
  let result: DecodingThread = try await backend.request(stub.path)
  #expect(!result.wasMainThread)
  #expect(result.values == values)
}

@Test @MainActor func backendKeepsActionableHTTPFailuresAndRejectsMalformedResponses() async throws
{
  let failed = HTTPStub(
    path: "/failure-\(UUID().uuidString)", data: Data(#"{"error":"请等待同步完成"}"#.utf8), status: 409)
  defer { failed.close() }
  do {
    let _: DecodingThread = try await BackendService(session: failed.session).request(failed.path)
    Issue.record("An HTTP failure must not be decoded as a successful result")
  } catch { #expect(error.localizedDescription == "请等待同步完成") }
  let malformed = HTTPStub(path: "/malformed-\(UUID().uuidString)", data: Data("invalid JSON".utf8))
  defer { malformed.close() }
  await #expect(throws: DecodingError.self) {
    let _: DecodingThread = try await BackendService(session: malformed.session).request(
      malformed.path)
  }
}

@Test @MainActor func independentStubSessionsCannotOverwriteOrUnregisterTheSameRoute() async throws
{
  let path = "/shared-route"
  let first = HTTPStub(path: path, data: Data(#"{"values":["first"]}"#.utf8))
  defer { first.close() }
  let second = HTTPStub(path: path, data: Data(#"{"values":["second"]}"#.utf8))
  defer { second.close() }
  let firstBackend = BackendService(session: first.session)
  let secondBackend = BackendService(session: second.session)
  let a: DecodingThread = try await firstBackend.request(path)
  let b: DecodingThread = try await secondBackend.request(path)
  #expect(a.values == ["first"])
  #expect(b.values == ["second"])
  second.close()
  let retained: DecodingThread = try await firstBackend.request(path)
  #expect(retained.values == ["first"])
}
