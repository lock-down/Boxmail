import BoxmailCore
import SwiftUI

struct ConversationAIView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @ViewState<String> private var request = ""

  private func latest(_ task: String) -> AgentJob? {
    store.latestConversationJob(task: task, message: message)
  }
  private func stale(_ job: AgentJob) -> Bool {
    guard let fingerprint = store.conversation?.fingerprint,
      let original = job.result?.contextFingerprint
    else { return false }
    return fingerprint != original
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("仅分析本机已缓存的往来邮件，结果可逐项查看依据。")
        .font(UIType.caption).foregroundStyle(Palette.muted)
      HStack(spacing: 12) {
        ActionButton(
          title: latest("conversationSummary") == nil ? "总结会话" : "刷新会话总结", icon: "sparkles",
          kind: .ai
        ) {
          store.generate(task: "conversationSummary", message: message)
        }.disabled(store.busy.contains("agent"))
        if let count = store.conversation?.total {
          Text("\(count) 封往来").font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
        }
      }
      if let output = store.aiOutput(task: "conversationSummary", messageId: message.id) {
        AIStreamingView(output: output)
      } else if let job = latest("conversationSummary"), let result = job.result {
        if stale(job) { staleNotice }
        if result.partial == true {
          WorkflowNotice(text: "本次结果使用了部分已缓存内容；更多历史或较长正文未全部纳入。", color: Palette.amber)
        }
        findings("已确认进展", items: result.progress ?? [], sources: result.sourceMessages ?? [])
        findings("未决事项", items: result.openItems ?? [], sources: result.sourceMessages ?? [])
        findings(
          "下一步", items: result.conversationNextSteps ?? [], sources: result.sourceMessages ?? [])
      }
      Divider().overlay(Palette.softBorder)
      WorkflowTextInput(label: "会话回复要求", placeholder: "补充回复要求（可选）", text: $request, lines: 3)
      HStack(spacing: 12) {
        ActionButton(title: "生成会话回复", icon: "arrowshape.turn.up.left", kind: .ai) {
          store.generate(
            task: "conversationReply", message: message, prompt: request, preview: true)
        }.disabled(store.busy.contains("agent"))
        Text("关联最新往来，先预览再使用").font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let output = store.aiOutput(task: "conversationReply", messageId: message.id) {
        AIStreamingView(output: output)
      } else if let job = latest("conversationReply"), let result = job.result {
        if stale(job) { staleNotice }
        Text(result.subject ?? "").font(UIType.section).textSelection(.enabled)
        Text(result.body ?? "").font(UIType.body).lineSpacing(5).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        sourceLinks(result.sourceIds ?? [], sources: result.sourceMessages ?? [])
        if result.partial == true {
          WorkflowNotice(text: "回复基于部分缓存内容，请核对历史与事实后使用。", color: Palette.amber)
        }
        ActionButton(title: "使用为回复草稿", icon: "square.and.pencil", kind: .primary) {
          store.useReply(job)
        }
        .disabled(
          stale(job) || store.composer != nil || store.busy.contains("agent")
            || store.busy.contains("use-reply"))
        Text("生成和刷新不会覆盖已编辑的草稿，发送前仍需确认。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
    }
  }
  private var staleNotice: some View {
    WorkflowNotice(text: "会话已有新邮件，当前结果需要刷新后再使用。", icon: "arrow.clockwise", color: Palette.amber)
  }
  private func findings(
    _ title: String, items: [ConversationFinding], sources: [ConversationSource]
  ) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(UIType.section)
      if items.isEmpty { Text("未发现明确事项").font(UIType.caption).foregroundStyle(Palette.muted) }
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        VStack(alignment: .leading, spacing: 5) {
          Text(item.text).font(UIType.body).lineSpacing(4).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          sourceLinks(item.messageIds, sources: sources)
        }
      }
    }
  }
  private func sourceLinks(_ ids: [String], sources: [ConversationSource]) -> some View {
    WrappingFlowLayout(spacing: 6) {
      ForEach(sources.filter { ids.contains($0.id) }) { source in
        ActionButton(
          title: "\(source.sender) · \(displayTime(source.date))", icon: "envelope", kind: .primary
        ) {
          let revision = store.restoreRevision
          let anchor = store.selectedMessageId
          Task {
            do {
              let mail: MailMessage = try await store.backend.request("/messages/\(source.id)")
              guard revision == store.restoreRevision, anchor == store.selectedMessageId,
                mail.accountId == message.accountId
              else { return }
              store.openMail(mail, tab: .conversation)
            } catch { store.mailAIErrors[message.id] = error.localizedDescription }
          }
        }.help(source.subject)
      }
    }
  }
}
