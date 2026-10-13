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
                store.destination = .inbox
                store.selectedMessageId = message.id
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
struct OrganizeView: View {
  @Bindable var store: MailStore
  var latest: AgentJob? {
    store.jobs.first { $0.task == "classify" && $0.accountId == store.accountId }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          VStack(alignment: .leading, spacing: 8) {
            Text("AI 智能整理").font(.system(size: 24, weight: .bold))
            Text("识别邮件主题，提出分类建议，确认后应用到本机邮件").font(.system(size: 12)).foregroundStyle(Palette.muted)
          }
          Spacer()
          ActionButton(title: "开始整理", icon: "wand.and.stars", kind: .ai) {
            store.action("organize") { _ = try await store.runAI(task: "classify") }
          }.disabled(store.busy.contains("agent"))
        }
        if store.busy.contains("agent") {
          HStack(spacing: 14) {
            ProgressView()
            VStack(alignment: .leading, spacing: 6) {
              Text("正在分析邮件主题").font(.system(size: 14, weight: .semibold))
              Text("本次最多分析 80 封收件箱邮件").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
          }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
            Palette.purpleSoft, in: RoundedRectangle(cornerRadius: 10))
        }
        if let job = latest, job.status == "needsApproval" {
          SectionCard(title: "待确认的整理建议", icon: "checklist") {
            ForEach(job.result?.items ?? []) { item in
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(store.messages.first { $0.id == item.id }?.subject ?? "邮件").font(
                    .system(size: 12, weight: .medium))
                  Text(item.reason).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Tag(text: item.category)
              }.padding(.vertical, 5)
            }
            ActionButton(title: "确认应用分类", icon: "checkmark", kind: .ai) {
              store.action("approve") {
                try await BackendService.shared.perform("/jobs/\(job.id)/approve")
              }
            }
          }
        } else if let job = latest, job.status == "applied" {
          HStack {
            Label("本次分类已应用", systemImage: "checkmark.circle").foregroundStyle(Palette.success)
            Spacer()
            ActionButton(title: "撤销本次整理", icon: "arrow.uturn.backward") {
              store.action("undo") {
                try await BackendService.shared.perform("/jobs/\(job.id)/undo")
              }
            }
          }.font(.system(size: 12)).padding(18).background(
            .white, in: RoundedRectangle(cornerRadius: 10))
        }
        Text("智能分类").font(.system(size: 17, weight: .semibold))
        LazyVGrid(
          columns: [
            GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top),
          ], alignment: .leading, spacing: 16
        ) {
          ForEach(["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来", "未分类"], id: \.self) { category in
            let messages = store.accountMessages.filter {
              $0.category == category && $0.folder == "inbox"
            }
            SectionCard(title: category, icon: category == "账单票据" ? "doc.text" : "folder") {
              HStack {
                Text("\(messages.count)").font(.system(size: 28, weight: .semibold))
                Text("封邮件").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
              }
              ForEach(messages.prefix(4)) { m in
                Button {
                  store.destination = .inbox
                  store.selectedMessageId = m.id
                } label: {
                  VStack(alignment: .leading, spacing: 5) {
                    HStack {
                      Text(m.sender).font(.system(size: 11, weight: .medium))
                      Spacer()
                      Text(displayTime(m.date)).font(.system(size: 10)).foregroundStyle(
                        Palette.muted)
                    }
                    Text(m.subject).font(.system(size: 12)).lineLimit(1)
                  }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
              }
              if messages.isEmpty {
                Text("暂时没有该类邮件").font(.system(size: 12)).foregroundStyle(Palette.muted)
              }
            }
          }
        }
      }.padding(30)
    }.background(Palette.canvas)
  }
}
struct ReplyAssistantView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @ViewState<String> private var prompt = "请礼貌回复这封邮件，确认收到，并列出需要进一步确认的事项。"
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          VStack(alignment: .leading, spacing: 7) {
            Text("AI 自动回复").font(.system(size: 23, weight: .bold))
            Text("先生成草稿，审核后再发送").font(.system(size: 12)).foregroundStyle(Palette.muted)
          }
          Spacer()
          Tag(text: "需要你确认", ai: true)
        }
        SectionCard(title: "原邮件", icon: "envelope") {
          Text(message.subject).font(.system(size: 16, weight: .semibold))
          Text("\(message.sender) · \(message.senderEmail)").font(.system(size: 11))
            .foregroundStyle(Palette.muted)
          Text(message.body).font(.system(size: 12)).lineSpacing(5).lineLimit(8)
        }
        SectionCard(title: "回复要求", icon: "sparkles") {
          TextEditor(text: $prompt).font(.system(size: 13)).frame(height: 90).padding(8).background(
            Palette.canvas, in: RoundedRectangle(cornerRadius: 7)
          ).overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border))
          HStack {
            ActionButton(title: "生成回复草稿", icon: "sparkles", kind: .ai) {
              store.action("reply-generate") {
                let job = try await store.runAI(task: "reply", message: message, prompt: prompt)
                if let id = job.result?.draftId {
                  store.composer = store.drafts.first { $0.id == id }
                }
              }
            }.disabled(store.busy.contains("agent"))
            if store.busy.contains("agent") { ProgressView().controlSize(.small) }
          }
        }
        let related = store.drafts.filter { $0.sourceMessageId == message.id }
        if !related.isEmpty {
          SectionCard(title: "已生成的回复草稿", icon: "square.and.pencil") {
            ForEach(related) { draft in
              HStack {
                VStack(alignment: .leading, spacing: 6) {
                  Text(draft.subject).font(.system(size: 13, weight: .medium))
                  Text(draft.body).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(
                    3)
                }
                Spacer()
                ActionButton(title: "审核草稿") { store.composer = draft }
              }
            }
          }
        }
      }.padding(25)
    }.background(Palette.canvas)
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
