import BoxmailCore
import SwiftUI

struct SummaryOverviewView: View {
  @Bindable var store: MailStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var summarized: [MailMessage] {
    store.accountMessages.filter { $0.summary != nil && $0.folder != "trash" }
  }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 24) {
        HStack {
          PageHeading(title: "AI 摘要总览", subtitle: "把邮件要点、待办与关键信息集中在一处")
          Spacer()
          ActionButton(title: store.busy.contains("summarize-unread") ? "正在总结…" : "总结未读邮件", icon: "sparkles", kind: .ai) {
            store.action("summarize-unread") {
              for message in store.unreadInboxMessages.filter({ $0.summary == nil }).prefix(10) {
                _ = try await store.runAI(task: "summary", message: message)
              }
            }
          }.disabled(store.busy.contains("agent") || store.unreadInboxMessages.allSatisfy { $0.summary != nil })
        }
        HStack(spacing: 22) {
          metric("已总结邮件", String(summarized.count))
          Divider().frame(height: 24)
          metric(
            "待完成事项",
            String(summarized.flatMap { $0.summary?.todos ?? [] }.filter { !$0.done }.count),
          )
          Divider().frame(height: 24)
          metric("收件箱未读", String(store.unreadInboxMessages.count))
        }.padding(.vertical, 18)
          .overlay(alignment: .bottom) { Rectangle().fill(Palette.border).frame(height: 1) }
        HStack {
          Text("邮件摘要").font(UIType.heading)
          Spacer()
          if store.busy.contains("agent") { ProgressView().controlSize(.small) }
        }
        ForEach(summarized) { message in
          VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
              VStack(alignment: .leading, spacing: 5) {
                Text(message.subject).font(.system(size: 16, weight: .semibold)).lineSpacing(4)
                  .fixedSize(horizontal: false, vertical: true)
                Text("\(message.sender) · \(displayTime(message.date))").font(.system(size: 11))
                  .foregroundStyle(Palette.muted)
              }
              Spacer()
              ActionButton(title: "打开邮件", icon: "arrow.up.right") {
                store.openMail(message, tab: .summary)
              }
            }
            Divider().overlay(Palette.softBorder)
            if let summary = message.summary {
              SummaryCard(store: store, message: message, summary: summary, embedded: true)
            }
          }.padding(22).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
        }
        if summarized.isEmpty {
          EmptyState(title: "还没有 AI 摘要", subtitle: "打开邮件后点击 AI 总结，或批量总结未读邮件。", icon: "sparkles")
            .frame(height: 300)
        }
      }.workspacePage()
    }.background(Palette.canvas)
  }
  private func metric(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
        .contentTransition(reduceMotion ? .identity : .numericText())
      Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
      Spacer(minLength: 0)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .animation(UIMotion.selection(reduceMotion), value: value)
  }
}
struct DraftsView: View {
  @Bindable var store: MailStore
  private var drafts: [MailDraft] { store.drafts.filter { $0.accountId == store.accountId } }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HStack {
          PageHeading(title: "草稿箱", subtitle: "草稿保存在本机，确认发送后投递")
          Spacer()
          ActionButton(title: "新建邮件", icon: "square.and.pencil", kind: .primary) {
            store.newDraft()
          }
        }.padding(.bottom, 6)
        Text("\(drafts.count) 份草稿").font(.system(size: 12, weight: .medium)).foregroundStyle(
          Palette.muted)
        ForEach(drafts) { draft in
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: "doc.text").foregroundStyle(Palette.muted).frame(
                width: 22, height: 22)
              VStack(alignment: .leading, spacing: 6) {
                Text(draft.subject.isEmpty ? "无主题草稿" : draft.subject).font(
                  .system(size: 14, weight: .semibold)
                ).lineLimit(2)
                Text("收件人：\(draft.to.isEmpty ? "未填写" : draft.to)").font(.system(size: 11))
                  .foregroundStyle(Palette.muted).lineLimit(1)
              }
              Spacer(minLength: 8)
              Text(displayTime(draft.updatedAt)).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(Palette.muted)
            }
            Text(
              draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "尚未撰写正文" : draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            .font(UIType.body).foregroundStyle(Palette.muted).lineLimit(2).lineSpacing(4)
            .frame(maxWidth: UILayout.document, alignment: .leading)
            HStack {
              if draft.status == "uncertain" {
                Label("发送结果待确认", systemImage: "exclamationmark.circle").font(.system(size: 11))
                  .foregroundStyle(Palette.amber)
              }
              if !draft.attachmentIds.isEmpty {
                Label("\(draft.attachmentIds.count) 个附件", systemImage: "paperclip").font(
                  .system(size: 11)
                ).foregroundStyle(Palette.muted)
              }
              Spacer()
              IconButton(icon: "trash", help: "删除草稿") {
                store.action("delete-draft") {
                  try await BackendService.shared.perform("/drafts/\(draft.id)", method: "DELETE")
                }
              }.disabled(draft.status == "uncertain")
              ActionButton(
                title: draft.status == "uncertain" ? "查看草稿" : "继续编辑", icon: "square.and.pencil"
              ) { store.composer = draft }
            }
          }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
        }
        if drafts.isEmpty {
          EmptyState(title: "还没有草稿", subtitle: "点击写邮件开始，AI 也可以帮你拟稿。", icon: "square.and.pencil")
            .frame(height: 350)
        }
      }.workspacePage()
    }.background(Palette.canvas)
  }
}
