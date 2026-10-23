import BoxmailCore
import SwiftUI

struct SettingsAISelectionView: View {
  @Binding var model: String
  @Binding var effort: String
  let models: [AIModel]
  var effortLevels: [String] = []
  private var showsEffort: Bool { !effortLevels.isEmpty }
  @ViewState<Bool> private var editingModel = false

  private var effortName: String { effort.capitalized }
  private var availableModels: [String] {
    var seen = Set<String>()
    return ([model] + models.map(\.id)).filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  var body: some View {
    SettingsSelectionMenu(
      model: displayName(model), effort: showsEffort ? effortName : "",
      groups: [
        .init(title: "模型", value: displayName(model), items: modelItems),
      ] + (showsEffort ? [.init(title: "思考等级", value: effortName, items: effortItems)] : []))
      .frame(width: SettingsFormLayout.modelSelectorWidth, height: SettingsFormLayout.controlHeight)
      .help(showsEffort ? "选择模型与思考等级" : "选择模型")
      .sheet(isPresented: $editingModel) {
        SettingsCustomModelEditor(model: $model)
      }
  }

  private func displayName(_ id: String) -> String { models.first { $0.id == id }?.displayName ?? (id.isEmpty ? "选择模型" : id) }

  private var modelItems: [SettingsSelectionItem] {
    var result = availableModels.map { value in
      SettingsSelectionItem.choice(displayName(value), selected: value == model) {
        model = value
      }
    }
    if models.isEmpty { result.append(.note("刷新列表后可选择更多模型")) }
    result.append(.separator)
    result.append(.choice("自定义模型…", selected: false) {
      editingModel = true
    })
    return result
  }

  private var effortItems: [SettingsSelectionItem] {
    effortLevels.map { value in
      .choice(value.capitalized, selected: value == effort) {
        effort = value
      }
    }
  }

}

struct SettingsCustomModelEditor: View {
  @Binding var model: String
  @ViewState<String> private var draft: String
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  init(model: Binding<String>) {
    _model = model
    _draft = ViewState(wrappedValue: model.wrappedValue)
  }
  private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("自定义模型").font(.system(size: 12, weight: .semibold))
      TextField("", text: $draft).settingsTextInput()
        .inputPlaceholder("例如 deepseek-flash", visible: draft.isEmpty)
        .focused($focused).accessibilityLabel("模型名称")
      HStack {
        Spacer()
        ActionButton(title: "取消") { dismiss() }.keyboardShortcut(.cancelAction)
        ActionButton(title: "使用模型", kind: .primary) {
          model = trimmedDraft
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(trimmedDraft.isEmpty)
      }
    }.padding(14).frame(width: 340).font(UIType.caption)
      .onAppear { focused = true }.onExitCommand { dismiss() }
  }
}
