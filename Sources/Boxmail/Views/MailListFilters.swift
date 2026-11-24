import BoxmailCore
import SwiftUI

struct MailListFilters: View {
  @Bindable var store: MailStore

  private let statuses = ["全部", "未读", "有附件", "AI 已总结"]

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) {
        FilterBar(values: statuses, selection: $store.filter, compact: true)
        Spacer(minLength: 4)
        categoryMenu
      }
      HStack(spacing: 6) {
        CossMenu(title: "邮件状态", value: store.filter, width: 156, prefersSelection: true) {
          for status in statuses {
            CossMenuItem.command(status, mark: .choice(status == store.filter)) { store.filter = status }
          }
        } trigger: {
          CossMenuLabel(title: store.filter, size: .compact)
        }.fixedSize()
        Spacer(minLength: 4)
        categoryMenu
      }
    }.frame(minHeight: UIControlSize.compact.height)
  }

  private var categoryMenu: some View {
    let title = store.listCategory.isEmpty ? "全部分类" : store.listCategory
    return CossMenu(title: "邮件分类", value: title, prefersSelection: true) {
      CossMenuItem.command("全部分类", mark: .choice(store.listCategory.isEmpty)) { store.listCategory = "" }
      for category in store.categories {
        CossMenuItem.command("\(category.name)（\(store.listCategoryCounts[category.name] ?? 0)）",
          mark: .choice(category.name == store.listCategory)) { store.listCategory = category.name }
      }
      CossMenuItem.divider
      CossMenuItem.command("管理分类…", icon: .settings3Line) { store.navigate(.organize) }
    } trigger: {
      CossMenuLabel(title: menuTitle(title, limit: 20), icon: .priceTag3Line, size: .compact,
        color: store.listCategory.isEmpty ? Palette.muted : store.categoryTone(title).ink)
    }.fixedSize().cossTooltip(title)
  }
}

struct SaveMailQueryButton: View {
  @Bindable var store: MailStore
  @ViewState private var saving = false
  @ViewState private var name = ""

  var body: some View {
    IconButton(icon: store.activeSavedSearchId == nil ? .bookmarkLine : .bookmarkFill, help: "保存当前查询", size: 28) {
      name = store.savedSearches.first { $0.id == store.activeSavedSearchId }?.name ?? ""; saving = true
    }
    .cossPopover(isPresented: $saving) {
      VStack(alignment: .leading, spacing: 12) {
        Text("保存查询").font(UIType.section)
        Text("\(store.scopeTitle) · \(store.destination.title) · \(store.filter) · \(store.listCategory.isEmpty ? "全部分类" : store.listCategory)")
          .font(UIType.small).foregroundStyle(Palette.muted)
        Text(store.search.isEmpty ? "无关键词条件" : store.search).font(UIType.caption).textSelection(.enabled)
        WorkflowField(title: "视图名称") {
          WorkflowTextInput(label: "视图名称", placeholder: "为这组查询命名", text: $name, font: UIType.caption)
        }
        HStack {
          ActionButton(title: "保存为新视图", color: Palette.accent, emphasis: .tinted) { Task { await store.saveSearch(name: name); saving = false } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
          if let id = store.activeSavedSearchId {
            ActionButton(title: "更新此视图") { Task { await store.saveSearch(name: name, updating: id); saving = false } }.disabled(name.isEmpty)
            ActionButton(title: "移除视图") { Task { await store.removeSavedSearch(id); saving = false } }
          }
        }
        Text("视图会保留账户范围与查询条件，保存后可从侧栏打开")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }.padding(24).frame(width: 440).background(Palette.paper)
    }
  }
}
