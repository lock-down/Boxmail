import BoxmailCore
import SwiftUI

struct DraftsView: View {
  @Bindable var store: MailStore
  @ViewState<MailDraft?> private var deletingDraft = nil
  private var drafts: [MailDraft] { store.drafts.filter { $0.accountId == store.accountId } }
  var body: some View {
    OverlayScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HStack {
          PageHeading(title: "草稿箱", subtitle: "自动保存在本机，随邮箱同步服务器；同时编辑时保留双方副本")
          Spacer()
          ActionButton(title: store.busy.contains("sync") ? "正在同步…" : "同步草稿", icon: "arrow.triangle.2.circlepath") {
            Task { await store.syncAll(folder: "drafts") }
          }.disabled(store.busy.contains("sync") || store.currentAccount?.isDemo != false)
          ActionButton(title: "新建邮件", icon: "square.and.pencil", color: Palette.accent) {
            store.newDraft()
          }
        }.padding(.bottom, 6)
        Text("\(drafts.count) 份草稿").font(.system(size: 12, weight: .medium)).foregroundStyle(
          Palette.muted)
        ForEach(drafts) { draft in
          let preview = draft.preview ?? ""
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
            Text(preview.isEmpty ? "尚未撰写正文" : preview)
            .font(UIType.body).foregroundStyle(Palette.muted).lineLimit(2).lineSpacing(4)
            .frame(maxWidth: UILayout.document, alignment: .leading)
            if let issue = draft.syncError {
              WorkflowNotice(text: issue, icon: "exclamationmark.circle", color: Palette.amber)
            }
            HStack {
              Text(syncTitle(draft)).font(UIType.small)
                .foregroundStyle(draft.syncState == "conflict" ? Palette.amber : Palette.muted)
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
              if draft.syncState == "conflict" {
                ActionButton(title: "同步为新草稿", icon: "arrow.triangle.2.circlepath") {
                  store.action("resume-draft-sync") {
                    let full: MailDraft = try await store.backend.request("/drafts/\(draft.id)")
                    let _: MailDraft = try await store.backend.request("/drafts", method: "POST", body: try jsonObject(full))
                    await store.syncAll(folder: "drafts", accountID: draft.accountId)
                  }
                }.disabled(store.busy.contains("sync") || store.busy.contains("resume-draft-sync"))
              }
              IconButton(icon: "trash", help: "删除草稿") {
                deletingDraft = draft
              }.disabled(draft.status == "uncertain")
              ActionButton(
                title: draft.status == "uncertain" ? "查看草稿" : "继续编辑", icon: "square.and.pencil"
              ) { store.editDraft(draft.id) }
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
      .alert("删除草稿？", isPresented: Binding(get: { deletingDraft != nil }, set: { if !$0 { deletingDraft = nil } }), presenting: deletingDraft) { draft in
        Button("取消", role: .cancel) { deletingDraft = nil }
        Button("删除草稿", role: .destructive) {
          deletingDraft = nil
          store.action("delete-draft") { try await store.backend.perform("/drafts/\(draft.id)", method: "DELETE") }
        }
      } message: { _ in
        Text("删除本机草稿，并在下次成功同步时清理对应的服务器草稿。")
      }
  }
  private func syncTitle(_ draft: MailDraft) -> String {
    switch draft.syncState {
    case "synced": return "已同步服务器"
    case "pending": return "等待同步服务器"
    case "conflict": return "需要处理同步冲突"
    default: return "本机草稿"
    }
  }
}
