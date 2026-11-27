import BoxmailCore
import SwiftUI

struct CategoryManagerView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<String> private var name = ""
  @ViewState<String> private var description = ""
  @ViewState<String> private var color = CategoryTone.presets[0].hex
  @ViewState<String?> private var editingID = nil
  @ViewState<MailCategory?> private var deleting = nil
  @ViewState<Bool> private var saving = false
  @ViewState private var hasColor = false
  @ViewState private var matches = false
  @ViewState private var condition = ""
  @ViewState private var trialLabel: MailCategory?
  @ViewState private var rulesLabel: MailCategory?
  @ViewState<String?> private var error = nil
  private var systemCategory: Bool { editingID == "unclassified" }
  private var selected: MailCategory? { store.categories.first { $0.id == editingID } }

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: "管理标签", subtitle: "所有账户共用标签，匹配条件按邮箱启用", closeLabel: "关闭标签管理") { dismiss() }
        .padding(24)
      CossSeparator()
      HStack(alignment: .top, spacing: 0) {
        categoryList.frame(width: 264)
        CossSeparator(axis: .vertical)
        editor.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }.background(Palette.paper).tint(Palette.accent).workspaceWindowSize(.categories)
      .onAppear { color = CategoryTone.suggestedHex(in: store.categories) }
      .disabled(saving)
      .sheet(item: $trialLabel) { OrganizationMailPicker(store: store, label: $0) }
      .sheet(item: $rulesLabel) { LabelAccountsView(store: store, label: $0) }
      .cossAlert("删除标签？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { category in
        CossAlertAction("取消", role: .cancel) { deleting = nil }
        CossAlertAction("删除标签", role: .destructive) { remove(category) }
      } message: { category in
        Text("邮件和其他标签会保留。已保存的旧分类视图会按原有方式更新。")
      }
  }

  private var categoryList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("\(store.categories.count) 个标签").font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        ActionButton(title: "新增", icon: .plus, color: Palette.accent) { reset() }
          .cossTooltip("新增标签").accessibilityLabel("新增标签")
      }.padding(.horizontal, 16).padding(.top, 12)
      ScrollViewReader { proxy in
        OverlayScrollView {
          LazyVStack(spacing: 4) {
          ForEach(store.categories) { category in
            Button { edit(category) } label: {
              HStack(alignment: .top, spacing: 10) {
                Circle().fill(store.categoryTone(category.name).swatch)
                  .overlay { Circle().strokeBorder(Palette.border.opacity(0.5), lineWidth: 1) }
                  .frame(width: 12, height: 12)
                  .padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                  Text(category.name).font(.system(size: 13, weight: editingID == category.id ? .medium : .regular))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                  if category.origin == "mailOrganization" {
                    Text("Agent 整理创建").font(UIType.small).foregroundStyle(Palette.muted)
                  }
                  if category.id == "unclassified" || !category.description.isEmpty {
                    Text(category.id == "unclassified" ? "系统分类" : category.description)
                      .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(2)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.foregroundStyle(Palette.ink).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(editingID == category.id ? Palette.accentSoft : .clear, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
            }.buttonStyle(ControlFeedback(selected: editingID == category.id)).controlFocus()
              .accessibilityLabel("\(category.id == "unclassified" ? "查看" : "编辑")标签 \(category.name)")
              .accessibilityAddTraits(editingID == category.id ? .isSelected : [])
              .id(category.id)
            }
          }.padding(.horizontal, 12).padding(.bottom, 16)
        }.onChange(of: editingID) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
      }
    }.frame(maxHeight: .infinity).background(Palette.chrome)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(systemCategory ? "未分类" : editingID == nil ? "新增标签" : "编辑标签").font(UIType.section)
        Spacer()
        if saving { CossSpinner() }
      }
      if systemCategory {
        WorkflowNotice(text: "未分类用于接收尚未整理或原分类已删除的邮件，由系统保留，不能改名或删除。", icon: .inbox)
        Spacer()
      } else {
        OverlayScrollView {
          VStack(alignment: .leading, spacing: 18) {
            WorkflowField(title: "标签名称", detail: "\(name.count) / 32") {
              WorkflowTextInput(label: "标签名称", placeholder: "合同审批", text: $name)
            }
            Toggle("自定颜色", isOn: $hasColor).toggleStyle(CossToggleStyle())
            if hasColor {
              CategoryColorField(hex: $color, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            WorkflowField(title: "标签说明", detail: "\(description.count) / 500") {
              WorkflowTextInput(label: "标签说明", placeholder: "标签用途", text: $description, lines: 4)
            }
            Toggle("整理匹配", isOn: $matches).toggleStyle(CossToggleStyle(isSwitch: true))
            if matches {
              WorkflowField(title: "匹配条件") {
                WorkflowTextInput(label: "匹配条件", placeholder: "匹配条件", text: $condition, lines: 3)
              }
              Text("启用此条件的邮箱整理邮件时，会使用发件人、主题和正文。")
                .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
              if let selected, selected.match == condition.trimmingCharacters(in: .whitespacesAndNewlines) {
                HStack(spacing: 8) {
                  ActionButton(title: "试用条件", emphasis: .secondary, size: .compact,
                    width: UILayout.pairedActionWidth) { trialLabel = selected }
                  ActionButton(title: "适用邮箱", emphasis: .secondary, size: .compact,
                    width: UILayout.pairedActionWidth) { rulesLabel = selected }
                }
              }
            }
            if let error { WorkflowNotice(text: error, icon: .infoCircle, color: Palette.amber) }
          }
        }
        HStack(spacing: 12) {
          if let category = selected {
            ActionButton(title: "删除标签", icon: .trash, color: Palette.amber) { deleting = category }
          }
          Spacer(minLength: 0)
          if editingID != nil { ActionButton(title: "取消编辑") { reset() } }
          ActionButton(title: saving ? "保存中…" : editingID == nil ? "添加标签" : "保存修改", icon: .check, color: Palette.accent) { save() }
            .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 32 || description.count > 500)
            .disabled(hasColor && CategoryTone.canonicalHex(color) == nil)
            .disabled(matches && (condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || condition.count > 500))
            .keyboardShortcut("s", modifiers: .command)
        }
      }
    }
  }
  private func edit(_ category: MailCategory) {
    editingID = category.id; name = category.name; description = category.description; error = nil
    color = CategoryTone.hex(for: category.name, category: category)
    hasColor = category.color != nil
    condition = category.match ?? ""
    matches = category.match != nil
  }
  private func reset() {
    editingID = nil; name = ""; description = ""; error = nil
    hasColor = false; matches = false; condition = ""
    color = CategoryTone.suggestedHex(in: store.categories)
  }
  private func save() {
    let color = hasColor ? CategoryTone.canonicalHex(color) : nil
    saving = true; error = nil
    let id = editingID
    let previousIDs = Set(store.categories.map(\.id))
    Task {
      defer { saving = false }
      do {
        let response: CategoryResponse = try await store.backend.request(id.map { "/categories/\($0)" } ?? "/categories",
          method: id == nil ? "POST" : "PATCH", body: ["name": name, "description": description, "color": color as Any? ?? NSNull(), "match": matches ? condition : ""])
        try await store.refresh()
        if let category = response.categories.first(where: { id == nil ? !previousIDs.contains($0.id) : $0.id == id }) { edit(category) }
      } catch { self.error = error.localizedDescription }
    }
  }
  private func remove(_ category: MailCategory) {
    deleting = nil; saving = true; error = nil
    Task {
      defer { saving = false }
      do {
        try await store.backend.perform("/categories/\(category.id)", method: "DELETE")
        try await store.refresh()
        if editingID == category.id { reset() }
      } catch { self.error = error.localizedDescription }
    }
  }
}
