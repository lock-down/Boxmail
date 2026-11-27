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
      AttachmentGrid {
        ForEach(files) { file in
          AttachmentCard(attachment: file, action: { store.previewFile(file) })
            .contextMenu {
              Button("下载") { store.download(file) }
            }
        }
      }
    }.padding(.top, 8)
  }
}

struct AttachmentGrid<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9, content: content)
  }
}

struct AttachmentCard: View {
  let attachment: MailAttachment
  var remove: (() -> Void)? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 4) {
      if let action {
        Button(action: action) { details.padding(12) }.buttonStyle(ControlFeedback()).controlFocus()
      } else {
        details.padding(.leading, 12).padding(.vertical, 12)
      }
      if let remove {
        IconButton(icon: .x, help: "移除附件：\(attachment.name)", size: UIControlSize.compact.height, action: remove)
          .padding(.trailing, 8)
      }
    }.background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous))
  }

  private var details: some View {
    HStack(spacing: 9) {
      AttachmentIcon(attachment: attachment, size: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(attachment.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
          .truncationMode(.middle).cossTooltip(attachment.name)
        Text(fileSize(attachment.size)).font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
