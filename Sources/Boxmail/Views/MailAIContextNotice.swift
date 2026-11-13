import BoxmailCore
import SwiftUI

struct MailAIContextNotice: View {
  let context: MailAIContext?
  let attachmentCount: Int

  var body: some View {
    if let context, !context.attachments.isEmpty {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(context.attachments) { MailAIContextSourceRow(source: $0) }
        }.padding(.top, 8)
      } label: {
        Text(context.partial
          ? "正文与 \(context.readableCount)/\(context.attachments.count) 份附件 · 部分内容未完整纳入"
          : "已结合正文与全部 \(context.attachments.count) 份附件")
          .foregroundStyle(context.partial ? Palette.amber : Palette.muted)
      }.font(UIType.small)
    } else if context == nil, attachmentCount > 0 {
      WorkflowNotice(text: "此前结果未记录附件覆盖范围，重新理解可结合正文与全部附件。", color: Palette.muted)
    }
  }
}

private struct MailAIContextSourceRow: View {
  let source: MailAIContextSource

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(source.name + " · " + (source.status == "included" ? "已纳入" : source.status == "partial" ? "部分纳入" : "未纳入"))
        .foregroundStyle(source.status == "included" ? Palette.muted : Palette.amber)
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      if let reason = source.reason {
        Text(reason).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }
      if let entries = source.entries {
        ForEach(entries) { MailAIContextSourceRow(source: $0) }.padding(.leading, 12)
      }
    }.font(UIType.small)
  }
}
