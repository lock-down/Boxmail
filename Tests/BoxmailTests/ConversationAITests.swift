import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

@MainActor @Test func newThreadMembersStillRevealOlderResultsForRefreshEvenWhenTheThreadIDChanges()
  throws
{
  let message = try JSONDecoder().decode(
    MailMessage.self,
    from: Data(
      #"{"id":"new","accountId":"account","folder":"inbox","sender":"Sender","senderEmail":"sender@example.test","to":"me@example.test","cc":"","subject":"Reply","body":"New reply","preview":"New reply","date":"2026-11-09T00:00:00Z","category":"","unread":false,"starred":false,"attachmentIds":[]}"#
        .utf8))
  let old = try JSONDecoder().decode(
    AgentJob.self,
    from: Data(
      #"{"id":"old-summary","task":"conversationSummary","status":"completed","accountId":"account","messageId":"old","createdAt":"2026-11-08T00:00:00Z","result":{"conversationId":"old-thread-id","contextFingerprint":"old-fingerprint","sourceMessages":[{"id":"old","sender":"Sender","subject":"Original","date":"2026-11-08T00:00:00Z"}]}}"#
        .utf8))
  var oldMember = message
  oldMember.id = "old"
  let threadData: [String: Any] = [
    "id": "changed-thread-id", "accountId": "account", "messages": [],
    "total": 2, "partial": false, "fingerprint": "new-fingerprint",
  ]
  var thread = try JSONDecoder().decode(
    MailConversation.self, from: JSONSerialization.data(withJSONObject: threadData))
  thread.messages = [message, oldMember]
  let store = MailStore()
  store.conversation = thread
  var foreign = old
  foreign.id = "foreign"
  foreign.accountId = "different-account"
  store.jobs = [foreign, old]
  #expect(
    store.latestConversationJob(task: "conversationSummary", message: message)?.id == "old-summary")
  #expect(
    store.latestConversationJob(task: "conversationSummary", message: message)?.result?
      .contextFingerprint != thread.fingerprint)
  #expect(store.latestConversationJob(task: "conversationReply", message: message) == nil)
}
