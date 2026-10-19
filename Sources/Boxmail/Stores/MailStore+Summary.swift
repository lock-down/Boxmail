import BoxmailCore
import Foundation

struct SummaryReplyRequest: Identifiable {
  let id = UUID()
  let messageId, prompt: String
}

extension MailStore {
  func followSummary(_ step: SummaryNextStep, in message: MailMessage) {
    guard !busy.contains("agent") else { return }
    switch step.action {
    case "reply":
      guard !step.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
      summaryReplyRequest = SummaryReplyRequest(messageId: message.id, prompt: step.prompt)
      openMail(message, tab: .reply)
      generate(task: "reply", message: message, prompt: step.prompt, preview: true)
    case "attachments":
      guard !message.attachmentIds.isEmpty else { return }
      attachmentResultsMessageId = message.id
      openMail(message, tab: .attachment)
      let batch = attachmentBatch(for: message)
      if let batch, ["paused", "failed", "partial"].contains(batch.status) {
        analyzeAttachments(in: message, retry: batch)
      } else if attachments.contains(where: { $0.messageId == message.id && $0.canAnalyze && !$0.isAnalyzed }) {
        analyzeAttachments(in: message)
      }
    default: break
    }
  }
}
