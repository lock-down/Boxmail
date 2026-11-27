import SwiftUI

struct RefreshKey<Request: Hashable>: Hashable {
  let request: Request
  let revision: Int
}

struct PageStoreErrorRow: View {
  let error: String
  let canRestore: Bool
  let restore: () -> Void
  let retry: () -> Void
  var body: some View {
    HStack {
      if canRestore {
        ActionButton(title: "返回结果", icon: .arrowBackUp, action: restore)
      }
      Text(error).font(UIType.caption).foregroundStyle(Palette.destructive)
      ActionButton(title: "重试", icon: .refresh, action: retry)
    }
  }
}

struct ListPagination: View {
  let offset, count, total, limit: Int
  let unit, subject: String
  var loading = false
  let previous, next: () -> Void
  private var pageSize: Int { max(1, limit) }
  var body: some View {
    HStack(spacing: 12) {
      Text("\(total == 0 ? 0 : offset + 1)–\(offset + count) / 共 \(total) \(unit)")
      Text("每页 \(pageSize) \(unit)").foregroundStyle(Palette.muted)
      Spacer(minLength: 8)
      PageNavigation(title: "第 \(offset / pageSize + 1) / \(max(1, (total + pageSize - 1) / pageSize)) 页",
        subject: subject, hasPrevious: !loading && offset > 0, hasNext: !loading && offset + pageSize < total,
        previous: previous, next: next)
    }.font(UIType.small).monospacedDigit().padding(.horizontal, 12).frame(height: 40)
      .background(Palette.canvas).overlay(alignment: .top) {
        Rectangle().fill(Palette.softBorder).frame(height: 1)
      }
  }
}

struct PageNavigation: View {
  let title, subject: String
  let hasPrevious, hasNext: Bool
  var buttonSize = UILayout.iconControl
  let previous, next: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      IconButton(icon: .chevronLeft, help: "上一页\(subject)", size: buttonSize, action: previous)
        .disabled(!hasPrevious)
      Text(title).monospacedDigit().foregroundStyle(Palette.muted)
      IconButton(icon: .chevronRight, help: "下一页\(subject)", size: buttonSize, action: next)
        .disabled(!hasNext)
    }.fixedSize(horizontal: true, vertical: false)
  }
}
