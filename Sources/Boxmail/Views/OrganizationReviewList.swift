import BoxmailCore
import SwiftUI

struct OrganizationReviewList: View {
  let jobId: String
  let items: [Classification]
  let output: AIStreamOutput?
  @Binding var offset: Int
  let message: (String) -> MailMessage?
  let openMail: (MailMessage) -> Void

  private var pageOffset: Int { min(offset, max(0, (items.count - 1) / 50) * 50) }
  private var visible: [Classification] { Array(items.dropFirst(pageOffset).prefix(50)) }

  var body: some View {
    WorkspaceListSurface {
      EmptyView()
    } content: {
      LazyVStack(spacing: 0) {
        if let output {
          AIStreamingView(output: output).padding(16)
          if !visible.isEmpty { Divider().overlay(Palette.softBorder) }
        }
        ForEach(visible) { item in
          WorkspaceListRow(action: {
            if let mail = message(item.id) { openMail(mail) }
          }) {
            HStack(spacing: 14) {
              VStack(alignment: .leading, spacing: 5) {
                Text(message(item.id)?.subject ?? "邮件已不在本机")
                  .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(item.reason).font(UIType.small).foregroundStyle(Palette.muted).lineLimit(2)
              }.frame(maxWidth: .infinity, alignment: .leading)
              Tag(text: item.category)
            }.foregroundStyle(Palette.ink)
          } actions: {
            EmptyView()
          }
          if item.id != visible.last?.id { Divider().overlay(Palette.softBorder) }
        }
      }
    } footer: {
      if !items.isEmpty {
        ListPagination(
          offset: pageOffset, count: visible.count, total: items.count, limit: 50,
          unit: "条", subject: "分类建议", previous: { offset = max(0, pageOffset - 50) },
          next: { offset = pageOffset + 50 })
      }
    }
    .id("\(jobId)-\(pageOffset)")
  }
}
