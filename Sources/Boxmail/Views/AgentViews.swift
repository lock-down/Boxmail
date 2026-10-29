import BoxmailCore
import SwiftUI

struct DraftsView: View {
  @Bindable var store: MailStore
  private var drafts: [MailDraft] { store.drafts.filter { $0.accountId == store.accountId } }
  var body: some View {
    OverlayScrollView {
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
  }
}
