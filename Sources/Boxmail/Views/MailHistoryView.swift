import BoxmailCore
import SwiftUI

struct MailHistory: Decodable {
  let summaries: [AgentJob]
  let replies: [AgentJob]
  let turns: [AssistantTurn]

  var isEmpty: Bool { summaries.isEmpty && replies.isEmpty && turns.isEmpty }
}

struct MailHistoryView: View {
  let store: MailStore
  let history: MailHistory?
  let summary: MailSummary?
  let openMail: (String) -> Void
  let openAttachment: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let summary {
        DisclosureGroup("整封邮件分析") {
          VStack(alignment: .leading, spacing: 12) {
            AnalysisDocumentView(text: summary.points.joined(separator: "\n\n"))
            if !summary.keyInfo.isEmpty { SummaryFactsView(facts: summary.keyInfo) }
            if let context = summary.context {
              MailAIContextNotice(context: context, attachmentCount: context.attachments.count)
            }
          }.padding(.vertical, 8)
        }
      }
      ForEach(history?.summaries ?? []) { job in
        if let result = job.result {
          DisclosureGroup("会话结论 · \(displayTime(job.createdAt))") {
            VStack(alignment: .leading, spacing: 12) {
              if result.partial == true {
                WorkflowNotice(text: "本次结论基于当时的部分缓存内容。", color: Palette.amber)
              }
              findings("已确认进展", items: result.progress ?? [], sources: result.sourceMessages ?? [])
              findings("未决事项", items: result.openItems ?? [], sources: result.sourceMessages ?? [])
              findings("下一步", items: result.conversationNextSteps ?? [], sources: result.sourceMessages ?? [])
              if let sources = result.sourceMessages, !sources.isEmpty {
                DisclosureGroup("查阅的邮件") { sourceLinks(sources) }
              }
            }.padding(.vertical, 8)
          }
        }
      }
      ForEach(history?.replies ?? []) { job in
        if let result = job.result, let body = result.body {
          DisclosureGroup("回复预览 · \(displayTime(job.createdAt))") {
            VStack(alignment: .leading, spacing: 12) {
              if let subject = result.subject, !subject.isEmpty {
                Text(subject).font(UIType.section).textSelection(.enabled)
              }
              AnalysisDocumentView(text: body)
              if let sources = result.sourceMessages, !sources.isEmpty {
                sourceLinks(sources.filter { result.sourceIds?.contains($0.id) ?? true })
              }
            }.padding(.vertical, 8)
          }
        }
      }
      ForEach(history?.turns ?? []) { turn in
        DisclosureGroup(turn.prompt) {
          VStack(alignment: .leading, spacing: 12) {
            Text(displayTime(turn.createdAt)).font(UIType.small).foregroundStyle(Palette.muted)
            AnalysisDocumentView(text: turn.text)
            if let coverage = turn.contextCoverage, coverage.partial {
              Text("本轮查阅 \(coverage.included) / \(coverage.total) 项。")
                .font(UIType.small).foregroundStyle(Palette.muted)
            }
            if !turn.sources.isEmpty {
              AssistantSourcesView(store: store, turn: turn, openMailSource: openMail,
                openAttachmentSource: openAttachment)
            }
          }.padding(.vertical, 8)
        }
      }
    }.font(UIType.body)
  }

  @ViewBuilder private func findings(
    _ title: String, items: [ConversationFinding], sources: [ConversationSource]
  ) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title).font(UIType.section)
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          AnalysisDocumentView(text: item.text)
          sourceLinks(sources.filter { item.messageIds.contains($0.id) })
        }
      }
    }
  }

  private func sourceLinks(_ sources: [ConversationSource]) -> some View {
    WrappingFlowLayout(spacing: 6) {
      ForEach(sources) { source in
        MailSourceButton(sender: source.sender, date: source.date, subject: source.subject) {
          openMail(source.id)
        }
      }
    }
  }
}
