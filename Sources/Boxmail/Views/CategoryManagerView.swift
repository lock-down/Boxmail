import BoxmailCore
import SwiftUI

struct CategoryManagerView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<String> private var name = ""
  @ViewState<String> private var description = ""
  @ViewState<String?> private var editingID = nil
  @ViewState<MailCategory?> private var deleting = nil
  @ViewState<Bool> private var saving = false
  @ViewState<String?> private var error = nil
  private var systemCategory: Bool { editingID == "unclassified" }
  private var selected: MailCategory? { store.categories.first { $0.id == editingID } }

  var body: some View {
    VStack(spacing: 0) {
      WorkflowPanelHeader(title: "分类标签", subtitle: "所有账户共用，AI 根据名称和说明提出分类建议", closeLabel: "关闭分类管理") { dismiss() }
        .padding(24)
      Divider().overlay(Palette.softBorder)
      HStack(alignment: .top, spacing: 0) {
        categoryList.frame(width: 264)
        Divider().overlay(Palette.softBorder)
        editor.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }.frame(width: 760, height: 520).background(Palette.paper).tint(Palette.blue)
      .disabled(saving)
      .alert("删除分类？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { category in
        Button("取消", role: .cancel) { deleting = nil }
        Button("删除分类", role: .destructive) { remove(category) }
      } message: { category in
        Text("“\(category.name)”中的邮件会保留并归为未分类，已有整理记录也会更新。")
      }
  }

  private var categoryList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("\(store.categories.count) 个分类").font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        WorkflowAction(title: "新增", icon: "plus", color: Palette.blue) { reset() }
          .help("新增分类").accessibilityLabel("新增分类")
      }.padding(.horizontal, 16).padding(.top, 12)
      ScrollViewReader { proxy in
        OverlayScrollView {
          LazyVStack(spacing: 4) {
          ForEach(store.categories) { category in
            Button { edit(category) } label: {
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: category.id == "unclassified" ? "tray" : "tag")
                  .font(.system(size: 12)).frame(width: 16).padding(.top, 2)
                  .foregroundStyle(editingID == category.id ? Palette.blue : Palette.muted)
                VStack(alignment: .leading, spacing: 5) {
                  Text(category.name).font(.system(size: 13, weight: editingID == category.id ? .medium : .regular))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                  if category.id == "unclassified" || !category.description.isEmpty {
                    Text(category.id == "unclassified" ? "系统分类" : category.description)
                      .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(2)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading)
              }.foregroundStyle(Palette.ink).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(editingID == category.id ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(ControlFeedback(selected: editingID == category.id))
              .accessibilityLabel("\(category.id == "unclassified" ? "查看" : "编辑")分类 \(category.name)")
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
        Text(systemCategory ? "未分类" : editingID == nil ? "新增分类" : "编辑分类").font(UIType.section)
        Spacer()
        if saving { ProgressView().controlSize(.small) }
      }
      if systemCategory {
        WorkflowNotice(text: "未分类用于接收尚未整理或原分类已删除的邮件，由系统保留，不能改名或删除。", icon: "tray")
        Spacer()
      } else {
        OverlayScrollView {
          VStack(alignment: .leading, spacing: 18) {
            WorkflowField(title: "分类名称", detail: "\(name.count) / 32") {
              WorkflowTextInput(label: "分类名称", placeholder: "例如：合同审批", text: $name)
            }
            WorkflowField(title: "分类说明", detail: "\(description.count) / 500") {
              WorkflowTextInput(label: "分类说明", placeholder: "例如：需要审核的采购合同、补充协议及审批进度", text: $description, lines: 4)
            }
            Text("说明能帮助 AI 区分相近分类。名称修改后，现有邮件标签也会同步更新。")
              .font(UIType.small).foregroundStyle(Palette.muted).lineSpacing(4)
              .fixedSize(horizontal: false, vertical: true)
            if let error { WorkflowNotice(text: error, icon: "exclamationmark.circle", color: Palette.amber) }
          }
        }
        HStack(spacing: 12) {
          if let category = selected {
            WorkflowAction(title: "删除分类", icon: "trash", color: Palette.amber) { deleting = category }
          }
          Spacer(minLength: 0)
          if editingID != nil { WorkflowAction(title: "取消编辑") { reset() } }
          WorkflowAction(title: saving ? "正在保存…" : editingID == nil ? "添加分类" : "保存修改", icon: "checkmark", color: Palette.blue) { save() }
            .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 32 || description.count > 500)
            .keyboardShortcut("s", modifiers: .command)
        }
      }
    }
  }
  private func edit(_ category: MailCategory) {
    editingID = category.id; name = category.name; description = category.description; error = nil
  }
  private func reset() { editingID = nil; name = ""; description = ""; error = nil }
  private func save() {
    saving = true; error = nil
    let id = editingID
    let previousIDs = Set(store.categories.map(\.id))
    Task {
      defer { saving = false }
      do {
        let response: CategoryResponse = try await BackendService.shared.request(id.map { "/categories/\($0)" } ?? "/categories",
          method: id == nil ? "POST" : "PATCH", body: ["name": name, "description": description])
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
        try await BackendService.shared.perform("/categories/\(category.id)", method: "DELETE")
        try await store.refresh()
        if editingID == category.id { reset() }
      } catch { self.error = error.localizedDescription }
    }
  }
}
