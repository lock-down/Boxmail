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
        ActionButton(title: "返回上次结果", icon: "arrow.uturn.backward", action: restore)
      }
      Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
      ActionButton(title: "重试", icon: "arrow.clockwise", action: retry)
    }
  }
}

extension View {
  func stalePage<ID: Hashable>(_ stale: Bool, id: ID) -> some View {
    self.id(id).opacity(stale ? 0.55 : 1).disabled(stale)
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
      IconButton(icon: "chevron.left", help: "上一页\(subject)", action: previous)
        .disabled(loading || offset == 0)
      Text("第 \(offset / pageSize + 1) / \(max(1, (total + pageSize - 1) / pageSize)) 页")
        .monospacedDigit().foregroundStyle(Palette.muted)
      IconButton(icon: "chevron.right", help: "下一页\(subject)", action: next)
        .disabled(loading || offset + pageSize >= total)
    }.font(UIType.small).padding(.horizontal, 12).frame(height: 40)
      .background(Palette.paper).overlay(alignment: .top) {
        Rectangle().fill(Palette.softBorder).frame(height: 1)
      }
  }
}
