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
