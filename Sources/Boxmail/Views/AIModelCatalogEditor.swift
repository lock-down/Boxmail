import BoxmailCore
import SwiftUI

struct AIModelCatalogEditor: View {
  @Binding var models: [AIModel]
  @Binding var selectedModel: String
  let apiProtocol: AIAPIProtocol

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("模型目录").font(.system(size: 12, weight: .medium))
        Text("\(models.count)").font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        SettingsInlineAction(title: "添加模型", icon: "plus") {
          let current = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
          models.append(AIModel(id: !current.isEmpty && !models.contains(where: { $0.id == current }) ? current : ""))
        }.disabled(models.count >= 500)
      }
      if models.isEmpty {
        Text("添加模型后可设置容量、输入类型和推理等级；也可从服务商获取可用模型。")
          .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading).padding(12)
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
      }
      LazyVStack(alignment: .leading, spacing: 10) {
        ForEach(models.indices, id: \.self) { index in
          AIModelEditorRow(model: modelBinding(index), selectedModel: $selectedModel, apiProtocol: apiProtocol) {
            if models.indices.contains(index) { models.remove(at: index) }
          }
        }
      }
    }
  }
  private func modelBinding(_ index: Int) -> Binding<AIModel> {
    Binding(get: { models.indices.contains(index) ? models[index] : AIModel(id: "") },
      set: { if models.indices.contains(index) { models[index] = $0 } })
  }
}

private struct AIModelEditorRow: View {
  @Binding var model: AIModel
  @Binding var selectedModel: String
  let apiProtocol: AIAPIProtocol
  let remove: () -> Void
  @ViewState<Bool> private var expanded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var name: Binding<String> {
    Binding(get: { model.name ?? "" }, set: { model.name = $0.isEmpty ? nil : $0 })
  }
  private var identifier: Binding<String> {
    Binding(get: { model.id }, set: { value in
      let followsSelection = selectedModel == model.id
      model.id = value
      if followsSelection { selectedModel = value }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Button { selectedModel = model.id.trimmingCharacters(in: .whitespacesAndNewlines) } label: {
          Image(systemName: !model.id.isEmpty && selectedModel == model.id ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(!model.id.isEmpty && selectedModel == model.id ? Palette.accent : Palette.muted)
        }.buttonStyle(ControlFeedback(corner: 6)).frame(width: 28, height: 32)
          .controlFocus(corner: 6).help("使用此模型").accessibilityLabel("使用模型 \(model.id)")
          .disabled(model.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        WorkflowTextInput(label: "模型 ID", placeholder: "模型 ID", text: identifier, font: UIType.caption, surface: Palette.paper)
        WorkflowTextInput(label: "模型显示名称", placeholder: "显示名称", text: name, font: UIType.caption, surface: Palette.paper)
          .frame(width: 150)
        IconButton(icon: expanded ? "chevron.up" : "chevron.down", help: expanded ? "收起模型参数" : "展开模型参数") {
          withAnimation(UIMotion.disclosure(reduceMotion)) { expanded.toggle() }
        }
        IconButton(icon: "trash", help: "移除模型 \(model.id)", action: remove)
      }
      if expanded {
        Divider().overlay(Palette.softBorder)
        HStack(alignment: .top, spacing: 14) {
          capacity("上下文窗口", placeholder: "256K", draft: $model.contextWindowDraft, value: $model.contextWindow)
          capacity("最大输出 token 数", placeholder: "32K", draft: $model.maxTokensDraft, value: $model.maxTokens)
        }
        Text("支持 K、M（1K = 1000）。留空使用模型默认值；填写输出数将限制单次请求。")
          .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 18) {
          Text("输入类型").foregroundStyle(Palette.muted)
          Toggle("文本", isOn: input("text")).toggleStyle(.checkbox)
          Toggle("图片", isOn: input("image")).toggleStyle(.checkbox)
          Spacer()
        }.font(UIType.caption)
        AIModelReasoningEditor(model: $model, apiProtocol: apiProtocol)
        if apiProtocol == .chatCompletions {
          HStack(spacing: 10) {
            Text("输出上限参数").font(UIType.caption).foregroundStyle(Palette.muted)
            WorkflowSelection(title: "输出上限参数", selection: Binding(
              get: { model.compat?.maxTokensField ?? "max_completion_tokens" },
              set: { model.compat = .init(maxTokensField: $0, forceAdaptiveThinking: model.compat?.forceAdaptiveThinking) }),
              options: [("max_completion_tokens", "max_completion_tokens"), ("max_tokens", "max_tokens")]).frame(width: 210)
            Spacer()
          }
        }
      }
      if let issue = model.validationIssue {
        Text(issue).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
    }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
  }
  private func input(_ type: String) -> Binding<Bool> {
    Binding(get: { model.inputTypes.contains(type) }, set: { enabled in
      var types = model.inputTypes
      if enabled { if !types.contains(type) { types.append(type) } }
      else if types.count > 1 { types.removeAll { $0 == type } }
      model.input = types
    })
  }
  private func capacity(_ title: String, placeholder: String, draft: Binding<String?>, value: Binding<Int?>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(UIType.caption).foregroundStyle(Palette.muted)
      WorkflowTextInput(label: title, placeholder: placeholder, text: Binding(
        get: { draft.wrappedValue ?? AIModel.formatCapacity(value.wrappedValue) },
        set: { draft.wrappedValue = $0; value.wrappedValue = AIModel.parseCapacity($0) }), font: UIType.caption, surface: Palette.paper)
    }.frame(width: 200, alignment: .leading)
  }
}
