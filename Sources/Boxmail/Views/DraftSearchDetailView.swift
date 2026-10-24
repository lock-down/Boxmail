import BoxmailCore
import SwiftUI

struct DraftSearchDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Label("本机草稿", systemImage: "square.and.pencil").font(UIType.caption).foregroundStyle(Palette.muted)
        Spacer()
        ActionButton(title: "继续编辑草稿", icon: "square.and.pencil", kind: .primary) {
          if let id = message.draftId { store.editDraft(id) }
        }.disabled(store.drafts.first(where: { $0.id == message.draftId })?.status == "sending")
      }.padding(.horizontal, 20).frame(height: 52)
      Divider().overlay(Palette.softBorder)
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 22) {
          Text(message.subject).font(.system(size: 23, weight: .semibold)).textSelection(.enabled)
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(message.senderEmail).font(UIType.caption).foregroundStyle(Palette.muted)
              Spacer()
              Text(displayTime(message.date)).font(UIType.small).foregroundStyle(Palette.muted)
            }
            RecipientDetailsView(to: message.to, cc: message.cc)
            if let draft = store.drafts.first(where: { $0.id == message.draftId }), !draft.bcc.isEmpty {
              Text("密送：" + draft.bcc).font(UIType.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
          }
          if message.html?.isEmpty == false {
            MailBodyView(message: message, preferences: store.settings.preferences)
          } else {
            Text(message.body.isEmpty ? "尚未填写正文" : message.body).font(UIType.body).lineSpacing(6)
              .foregroundStyle(message.body.isEmpty ? Palette.muted : Palette.ink).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          if !message.attachmentIds.isEmpty {
            Text("附件 · \(message.attachmentIds.count) 个").font(UIType.section)
            ForEach(message.attachmentIds, id: \.self) { id in
              if let attachment = store.attachments.first(where: { $0.id == id }) {
                AttachmentCard(attachment: attachment) { store.previewAttachment = attachment }
              }
            }
          }
        }.frame(maxWidth: UILayout.reading, alignment: .leading).padding(30).frame(maxWidth: .infinity)
      }
    }.background(Palette.paper)
  }
}
