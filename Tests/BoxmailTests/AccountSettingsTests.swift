import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private func requestObject(_ request: URLRequest?) throws -> [String: Any] {
  var data = request?.httpBody ?? Data()
  if data.isEmpty, let stream = request?.httpBodyStream {
    stream.open()
    defer { stream.close() }
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
      if count == 0 { break }
      data.append(contentsOf: buffer.prefix(count))
    }
  }
  return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@MainActor @Test func accountCommitRemainsSuccessfulWhenTheMailRefreshFails() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BoxmailAccountSave-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let vault = EnvCredentialStore(fileURL: directory.appendingPathComponent(".env"))
  let account = MailAccount(id: "account", name: "Saved", email: "me@example.test")
  let post = HTTPStub(path: "/accounts", data: Data(), delayed: true)
  let state = HTTPStub(
    path: "/state", data: Data(#"{"error":"Synthetic refresh failure"}"#.utf8), status: 502,
    scope: post)
  defer {
    post.close()
    state.close()
  }
  let store = MailStore(backend: BackendService(session: post.session))
  let task = Task {
    try await store.saveAccount(
      account, password: "synthetic-new-password", credentialStorage: vault)
  }
  try await post.waitUntilStarted()
  let body = try requestObject(post.latestRequest)
  let references = try #require(body["credentialReferences"] as? [String: String])
  let reference = try #require(references["mail-account"])
  #expect(try vault.read(reference) == "synthetic-new-password")
  #expect(body["password"] == nil)
  var settings = SettingsData()
  settings.credentialReferences = references
  post.respond(
    data: try JSONSerialization.data(withJSONObject: [
      "account": jsonObject(account), "settings": jsonObject(settings),
    ]))
  let refreshed = try await task.value
  #expect(!refreshed)
  #expect(store.accounts == [account])
  #expect(store.accountId == account.id)
  #expect(store.settings.credentialReferences == references)
}

@MainActor @Test func aRejectedAccountEditPreservesThePreviousPasswordAndAccount() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BoxmailRejectedAccount-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let vault = EnvCredentialStore(fileURL: directory.appendingPathComponent(".env"))
  try vault.save("synthetic-existing-password", account: "mail-account")
  let original = MailAccount(id: "account", name: "Original", email: "me@example.test")
  let post = HTTPStub(path: "/accounts", data: Data(#"{"error":"请输入有效的邮箱地址"}"#.utf8), status: 400)
  let state = HTTPStub(
    path: "/state",
    data: try JSONSerialization.data(withJSONObject: [
      "accounts": [jsonObject(original)], "settings": jsonObject(SettingsData()),
    ]), scope: post)
  defer {
    post.close()
    state.close()
  }
  let store = MailStore(backend: BackendService(session: post.session))
  store.accounts = [original]
  var edited = original
  edited.email = "invalid"
  do {
    _ = try await store.saveAccount(
      edited, password: "synthetic-replacement-password", credentialStorage: vault)
    Issue.record("An invalid account must fail")
  } catch { #expect(error.localizedDescription == "请输入有效的邮箱地址") }
  #expect(try vault.read("mail-account") == "synthetic-existing-password")
  #expect(store.accounts == [original])
}
