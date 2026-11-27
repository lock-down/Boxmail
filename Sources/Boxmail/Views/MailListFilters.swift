import BoxmailCore
import SwiftUI

struct MailListFilters: View {
  @Bindable var store: MailStore

  private let statuses = ["全部", "未读", "有附件"]
  private var statusTitle: String { store.filter == "AI 已总结" ? "已总结" : store.filter }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 6) {
        FilterBar(values: statuses, selection: $store.filter, compact: true)
        if !statuses.contains(store.filter) {
          Text(statusTitle).font(UIType.small).foregroundStyle(Palette.muted)
        }
        Spacer(minLength: 4)
        categoryMenu
      }
      HStack(spacing: 6) {
        CossMenu(title: "邮件状态", value: statusTitle, width: 156, prefersSelection: true) {
          for status in statuses {
            CossMenuItem.command(status, mark: .choice(status == store.filter)) { store.filter = status }
          }
        } trigger: {
          CossMenuLabel(title: statusTitle, size: .compact)
        }.fixedSize()
        Spacer(minLength: 4)
        categoryMenu
      }
    }.frame(minHeight: UIControlSize.compact.height)
  }

  private var categoryMenu: some View {
    let title = store.labelFilterTitle
    return CossMenu(title: "筛选标签", value: title, prefersSelection: true) {
      CossMenuItem.command("全部标签", mark: .choice(store.listLabelID == nil && store.listCategory.isEmpty)) {
        store.setLabelFilter(nil)
      }
      for label in store.categories {
        CossMenuItem.command(label.name, mark: .choice(label.id == store.listLabelID)) { store.setLabelFilter(label.id) }
      }
      CossMenuItem.divider
      CossMenuItem.command("管理标签", icon: .settings) { store.showLabelManager = true }
    } trigger: {
      CossMenuLabel(title: title, icon: .tag, size: .compact,
        color: title == "全部标签" ? Palette.muted : store.categoryTone(title).ink)
    }
  }
}

struct SaveMailQueryButton: View {
  @Bindable var store: MailStore
  @ViewState private var saving = false
  @ViewState private var name = ""

  var body: some View {
    IconButton(icon: store.activeSavedSearchId == nil ? .bookmark : .bookmarkFilled, help: "保存当前查询") {
      name = store.savedSearches.first { $0.id == store.activeSavedSearchId }?.name ?? ""; saving = true
    }
    .cossPopover(isPresented: $saving) {
      VStack(alignment: .leading, spacing: 12) {
        Text("保存查询").font(UIType.section)
        Text("\(store.scopeTitle) · \(store.destination.title) · \(store.filter) · \(store.labelFilterTitle)")
          .font(UIType.small).foregroundStyle(Palette.muted)
        Text(store.search.isEmpty ? "无关键词条件" : store.search).font(UIType.caption).textSelection(.enabled)
        WorkflowField(title: "视图名称") {
          WorkflowTextInput(label: "视图名称", placeholder: "视图名称", text: $name, font: UIType.caption)
        }
        HStack {
          ActionButton(title: "另存视图", color: Palette.accent, emphasis: .tinted) { Task { await store.saveSearch(name: name); saving = false } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
          if let id = store.activeSavedSearchId {
            ActionButton(title: "更新视图") { Task { await store.saveSearch(name: name, updating: id); saving = false } }.disabled(name.isEmpty)
            ActionButton(title: "移除视图") { Task { await store.removeSavedSearch(id); saving = false } }
          }
        }
        Text("视图会保留账户范围与查询条件，保存后可从侧栏打开")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }.padding(UILayout.sectionInset).frame(width: 440).background(Palette.paper)
    }
  }
}
