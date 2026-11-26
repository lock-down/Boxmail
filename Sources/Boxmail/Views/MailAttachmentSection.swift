import BoxmailCore
import SwiftUI

struct MailAttachmentSection: View {
  @Bindable var store: MailStore
  let message: MailMessage

  var body: some View {
    let files = message.attachmentIds.compactMap { id in
      store.attachments.first { $0.id == id && $0.messageId == message.id }
    }
    VStack(alignment: .leading, spacing: 12) {
      Label("\(message.attachmentIds.count) 个附件", icon: .paperclip)
        .font(.system(size: 12, weight: .semibold))
      let failedIds = message.attachmentIds.filter { store.attachmentLoadErrors.contains($0) }
      if !failedIds.isEmpty {
        HStack {
          Text("部分附件资料加载未完成。").font(UIType.caption).foregroundStyle(Palette.amber)
          ActionButton(title: "重试", size: .compact) {
            Task { for id in failedIds { await store.loadAttachment(id) } }
          }
        }
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9) {
        ForEach(files) { file in
          AttachmentCard(attachment: file) { store.previewFile(file) }
            .contextMenu {
              Button("下载") { store.download(file) }
            }
        }
      }
    }.padding(.top, 8)
  }
}

struct AttachmentCard: View {
  let attachment: MailAttachment
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        AttachmentIcon(attachment: attachment, size: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(attachment.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
            .truncationMode(.middle).cossTooltip(attachment.name)
          Text(fileSize(attachment.size)).font(UIType.small).foregroundStyle(Palette.muted)
        }
        Spacer(minLength: 0)
      }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
    }.buttonStyle(ControlFeedback()).controlFocus()
  }
}
