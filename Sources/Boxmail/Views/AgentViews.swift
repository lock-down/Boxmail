import BoxmailCore
import SwiftUI

struct SummaryOverviewView: View {
  @Bindable var store: MailStore
  var summarized: [MailMessage] {
    store.accountMessages.filter { $0.summary != nil && $0.folder != "trash" }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          VStack(alignment: .leading, spacing: 8) {
            Text("AI 摘要总览").font(.system(size: 24, weight: .bold))
            Text("把邮件要点、待办与关键信息集中在一处").font(.system(size: 12)).foregroundStyle(Palette.muted)
          }
          Spacer()
          ActionButton(title: "总结未读邮件", icon: "sparkles", kind: .ai) {
            store.action("summarize-unread") {
              for message in store.accountMessages.filter({
                $0.unread && $0.folder == "inbox" && $0.summary == nil
              }).prefix(10) { _ = try await store.runAI(task: "summary", message: message) }
            }
          }.disabled(store.busy.contains("agent"))
        }
        HStack(spacing: 14) {
          metric("已总结邮件", String(summarized.count), "sparkles")
          metric(
            "待完成事项",
            String(summarized.flatMap { $0.summary?.todos ?? [] }.filter { !$0.done }.count),
            "checklist")
          metric("未读邮件", String(store.accountMessages.filter { $0.unread }.count), "envelope.badge")
        }
        HStack {
          Text("邮件摘要").font(.system(size: 16, weight: .semibold))
          Spacer()
          if store.busy.contains("agent") { ProgressView().controlSize(.small) }
        }
        ForEach(summarized) { message in
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              VStack(alignment: .leading, spacing: 5) {
                Text(message.subject).font(.system(size: 15, weight: .semibold))
                Text("\(message.sender) · \(displayTime(message.date))").font(.system(size: 11))
                  .foregroundStyle(Palette.muted)
              }
              Spacer()
              ActionButton(title: "打开邮件", icon: "arrow.up.right") {
                store.openMail(message, tab: .summary)
              }
            }
            if let summary = message.summary {
              SummaryCard(store: store, message: message, summary: summary)
            }
          }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 10)).overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
        }
        if summarized.isEmpty {
          EmptyState(title: "还没有 AI 摘要", subtitle: "打开邮件后点击 AI 总结，或批量总结未读邮件。", icon: "sparkles")
            .frame(height: 300)
        }
      }.padding(30)
    }.background(Palette.canvas)
  }
  func metric(_ title: String, _ value: String, _ icon: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 10) {
        Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted)
        Text(value).font(.system(size: 30, weight: .semibold))
      }
      Spacer()
      Image(systemName: icon).font(.system(size: 24)).foregroundStyle(Palette.purple)
    }.padding(20).frame(maxWidth: .infinity).background(
      .white, in: RoundedRectangle(cornerRadius: 10)
    ).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
  }
}
struct DraftsView: View {
  @Bindable var store: MailStore
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Text("草稿箱").font(.system(size: 24, weight: .bold))
          Spacer()
          ActionButton(title: "新建邮件", icon: "square.and.pencil", kind: .primary) {
            store.newDraft()
          }
        }
        Text("草稿仅保存在本机；确认发送后通过 SMTP 投递").font(.system(size: 12)).foregroundStyle(Palette.muted)
        ForEach(store.drafts.filter { $0.accountId == store.accountId }) { draft in
          SectionCard(
            title: draft.subject.isEmpty ? "无主题草稿" : draft.subject, icon: "square.and.pencil"
          ) {
            Text("收件人：\(draft.to.isEmpty ? "未填写" : draft.to)").font(.system(size: 12))
              .foregroundStyle(Palette.muted)
            Text(draft.body).font(.system(size: 13)).lineLimit(3)
            HStack {
              Text("保存于 \(displayTime(draft.updatedAt))").font(.system(size: 10)).foregroundStyle(
                Palette.muted)
              if draft.status == "uncertain" { Tag(text: "发送结果待确认", ai: true) }
              Spacer()
              ActionButton(title: "删除草稿", icon: "trash") {
                store.action("delete-draft") {
                  try await BackendService.shared.perform("/drafts/\(draft.id)", method: "DELETE")
                }
              }.disabled(draft.status == "uncertain")
              ActionButton(title: draft.status == "uncertain" ? "查看草稿" : "继续编辑", kind: .primary) {
                store.composer = draft
              }
            }
          }
        }
        if store.drafts.filter({ $0.accountId == store.accountId }).isEmpty {
          EmptyState(title: "还没有草稿", subtitle: "点击写邮件开始，AI 也可以帮你拟稿。", icon: "square.and.pencil")
            .frame(height: 350)
        }
      }.padding(30)
    }.background(Palette.canvas)
  }
}
