import SwiftUI

struct SettingsAISelectionView: View {
  @Binding var model: String
  @Binding var effort: String
  let models: [String]
  @ViewState<Bool> private var editingModel = false

  private var effortName: String { effort.capitalized }
  private var availableModels: [String] {
    var seen = Set<String>()
    return ([model] + models).filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  var body: some View {
    SettingsSelectionMenu(
      model: model.isEmpty ? "选择模型" : model, effort: effortName,
      groups: [
        .init(title: "模型", value: model.isEmpty ? "选择模型" : model, items: modelItems),
        .init(title: "思考等级", value: effortName, items: effortItems),
      ])
      .frame(width: SettingsFormLayout.modelSelectorWidth, height: SettingsFormLayout.controlHeight)
      .help("选择模型与思考等级")
      .sheet(isPresented: $editingModel) {
        SettingsCustomModelEditor(model: $model)
      }
  }

  private var modelItems: [SettingsSelectionItem] {
    var result = availableModels.map { value in
      SettingsSelectionItem.choice(value, selected: value == model) {
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
    ["low", "high", "max"].map { value in
      .choice(value.capitalized, selected: value == effort) {
        effort = value
      }
    }
  }

}

private struct SettingsCustomModelEditor: View {
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
