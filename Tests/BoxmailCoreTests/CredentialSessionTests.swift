import Testing

@testable import BoxmailCore

@MainActor @Test func successfulAuthorizationIsReusedUntilAppSessionEnds() throws {
  let session = CredentialSession()
  var authorizationRequests = 0
  for _ in 0..<5 {
    let key = session.read("ai-key") {
      authorizationRequests += 1
      return "test-ai"
    }
    #expect(key == "test-ai")
  }
  #expect(authorizationRequests == 1)
  #expect(session.read("mail-a") { "test-mail" } == "test-mail")
  #expect(session.read("ai-key") { "unexpected" } == "test-ai")
  session.clear()
  #expect(
    session.read("ai-key") {
      authorizationRequests += 1
      return "fresh"
    } == "fresh")
  #expect(authorizationRequests == 2)
}

@MainActor @Test func deniedAuthorizationCanBeRetriedAndDoesNotPoisonTheSession() throws {
  enum Denied: Error { case userDenied }
  let session = CredentialSession()
  #expect(throws: Denied.self) {
    try session.read("ai-key") { throw Denied.userDenied }
  }
  #expect(session.read("ai-key") { "authorized" } == "authorized")
}

@MainActor @Test func credentialChangesUpdateMemoryOnlyAfterSuccessfulKeychainWrite() throws {
  enum SaveFailure: Error { case locked }
  let session = CredentialSession()
  _ = session.read("ai-key") { "old" }
  #expect(throws: SaveFailure.self) {
    try session.save("new", account: "ai-key") { throw SaveFailure.locked }
  }
  #expect(session.read("ai-key") { "unexpected" } == "old")
  var writes = 0
  session.save("new", account: "ai-key") { writes += 1 }
  session.save("new", account: "ai-key") { writes += 1 }
  #expect(writes == 1)
  #expect(session.read("ai-key") { "unexpected" } == "new")
  session.save("", account: "ai-key") { writes += 1 }
  #expect(session.read("ai-key") { "unexpected" } == "")
  #expect(writes == 2)
}

@MainActor @Test func backgroundAccessOnlyUsesPreviouslyAuthorizedCredentials() {
  let session = CredentialSession()
  #expect(session.cachedValue("mail-a") == nil)
  _ = session.read("mail-a") { "authorized" }
  #expect(session.cachedValue("mail-a") == "authorized")
  #expect(session.cachedValue("mail-b") == nil)
  session.clear()
  #expect(session.cachedValue("mail-a") == nil)
}
