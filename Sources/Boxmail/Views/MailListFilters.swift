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
        Picker("邮件状态", selection: $store.filter) {
          ForEach(statuses, id: \.self) { Text($0).tag($0) }
        }.pickerStyle(.menu).labelsHidden().fixedSize()
          .accessibilityLabel("邮件状态")
        Spacer(minLength: 4)
        categoryMenu
      }
    }.frame(minHeight: UIControlSize.compact.height)
  }

  private var categoryMenu: some View {
    let title = store.listCategory.isEmpty ? "全部分类" : store.listCategory
    return Menu {
      Picker("邮件分类", selection: $store.listCategory) {
        Text("全部分类").tag("")
        ForEach(store.categories) { category in
          Text("\(category.name)（\(store.listCategoryCounts[category.name] ?? 0)）").tag(category.name)
        }
      }.pickerStyle(.inline)
      Divider()
      Button("管理分类…") { store.navigate(.organize) }
    } label: {
      ActionLabel(title: menuTitle(title, limit: 20), icon: "tag", font: UIControlSize.compact.font)
        .foregroundStyle(store.listCategory.isEmpty ? Palette.muted : store.categoryTone(title).ink)
        .controlLabel(size: .compact)
    }.menuStyle(.borderlessButton).fixedSize()
      .help(title).accessibilityLabel("邮件分类，\(title)")
  }
}

struct SaveMailQueryButton: View {
  @Bindable var store: MailStore
  @ViewState private var saving = false
  @ViewState private var name = ""

  var body: some View {
    IconButton(icon: store.activeSavedSearchId == nil ? "bookmark" : "bookmark.fill", help: "保存当前查询", size: 28) {
      name = store.savedSearches.first { $0.id == store.activeSavedSearchId }?.name ?? ""; saving = true
    }
    .popover(isPresented: $saving) {
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
