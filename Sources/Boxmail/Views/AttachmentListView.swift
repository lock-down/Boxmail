import BoxmailCore
import SwiftUI

struct AttachmentListView: View {
  let items: [AttachmentPageItem]
  @Binding var sortOrder: [KeyPathComparator<AttachmentPageItem>]
  let preview: (MailAttachment) -> Void
  let openMail: (String) -> Void
  let download: (MailAttachment) -> Void
  @ViewBuilder var footer: () -> ListPagination
  @ViewState<String?> private var selection: String?
  @FocusState private var focused: Bool

  var body: some View {
    GeometryReader { geometry in
      let columns = AttachmentListLayout(width: geometry.size.width)
      ScrollViewReader { scroll in
        WorkspaceList(items: items) {
          HStack(spacing: AttachmentListLayout.gap) {
            Color.clear.frame(width: AttachmentListLayout.icon, height: 1).accessibilityHidden(true)
            sortHeader("附件名称", keyPath: \.name).frame(width: columns.name, alignment: .leading)
            if columns.showsSource {
              Text("原邮件与发件人").frame(width: columns.source, alignment: .leading)
            }
            sortHeader("大小", keyPath: \.size).frame(width: columns.size, alignment: .leading)
            sortHeader("日期", keyPath: \.date).frame(width: columns.date, alignment: .leading)
            if columns.showsStatus {
              Text("理解状态").frame(width: columns.status, alignment: .leading)
            }
            Text("操作").frame(width: columns.actions)
          }.font(UIType.small).foregroundStyle(Palette.muted).padding(.horizontal, AttachmentListLayout.inset)
            .frame(height: 40).background(Palette.chrome)
        } footer: {
          footer()
        } row: { item in
          WorkspaceListRow(
            selected: selection == item.id,
            primaryAction: { preview(item.attachment) },
            action: {
              selection = item.id
              focused = true
            }
          ) {
            HStack(spacing: AttachmentListLayout.gap) {
              AttachmentIcon(attachment: item.attachment, size: 18).frame(width: AttachmentListLayout.icon)
              VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                  .truncationMode(
                    .middle)
                if !columns.showsSource {
                  HStack(spacing: 8) {
                    if !columns.showsStatus { status(item).fixedSize() }
                    Text(item.source.subject).font(UIType.small).foregroundStyle(Palette.muted)
                      .lineLimit(1).truncationMode(.middle)
                  }
                }
              }.frame(width: columns.name, alignment: .leading).foregroundStyle(Palette.ink).help(
                item.name)
              if columns.showsSource {
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.source.subject).font(UIType.caption).foregroundStyle(Palette.ink)
                    .lineLimit(1).truncationMode(.middle)
                  Text(item.source.sender).font(UIType.small).foregroundStyle(Palette.muted)
                    .lineLimit(1)
                }.frame(width: columns.source, alignment: .leading).help(item.source.subject)
              }
              Text(fileSize(item.size)).frame(width: columns.size, alignment: .leading)
              Text(String(item.date.prefix(10))).frame(width: columns.date, alignment: .leading)
              if columns.showsStatus {
                status(item).frame(width: columns.status, alignment: .leading)
              }
            }.font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
          } actions: {
            HStack(spacing: UILayout.iconGap) {
              IconButton(icon: "doc.text.magnifyingglass", help: "预览 \(item.name)") {
                preview(item.attachment)
              }
              IconButton(icon: "envelope", help: "打开原邮件") { openMail(item.source.id) }
              IconButton(icon: "arrow.down.to.line", help: "下载 \(item.name)") {
                download(item.attachment)
              }
            }.frame(width: columns.actions, alignment: .leading).padding(.leading, 4).padding(
              .trailing, 16)
          }
          .foregroundStyle(Palette.ink)
          .contextMenu {
            Button("预览附件") { preview(item.attachment) }
            Button("打开原邮件") { openMail(item.source.id) }
            Button("下载附件") { download(item.attachment) }
          }
        }.accessibilityLabel("附件列表")
          .focusable().focusEffectDisabled().focused($focused)
          .onKeyPress(.return) {
            guard let item = items.first(where: { $0.id == selection }) else { return .ignored }
            preview(item.attachment)
            return .handled
          }
          .onKeyPress(.downArrow) { moveSelection(1) }
          .onKeyPress(.upArrow) { moveSelection(-1) }
          .onChange(of: selection) { _, id in if let id { scroll.scrollTo(id) } }
      }
    }
  }
  private func status(_ item: AttachmentPageItem) -> some View {
    Text(item.attachment.analysisStatusTitle).font(UIType.small)
      .foregroundStyle(item.attachment.isAnalyzed ? Palette.blue : Palette.muted)
  }
  private func moveSelection(_ delta: Int) -> KeyPress.Result {
    guard !items.isEmpty else { return .ignored }
    let current = items.firstIndex { $0.id == selection } ?? (delta > 0 ? -1 : items.count)
    selection = items[min(items.count - 1, max(0, current + delta))].id
    return .handled
  }
  private func sortHeader<Value: Comparable>(
    _ title: String, keyPath: KeyPath<AttachmentPageItem, Value>
  ) -> some View {
    let selected = sortOrder.first?.keyPath == keyPath
    let ascending = sortOrder.first?.order == .forward
    return TableSortButton(title: title, selected: selected, ascending: ascending) {
      sortOrder = [KeyPathComparator(keyPath, order: selected && ascending ? .reverse : .forward)]
    }
  }
}
