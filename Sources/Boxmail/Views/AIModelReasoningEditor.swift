import BoxmailCore
import SwiftUI

struct AIModelReasoningEditor: View {
  @Binding var model: AIModel
  let apiProtocol: AIAPIProtocol
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var levels: [String] { model.reasoningLevels }
  private var enabled: Binding<Bool> {
    Binding(get: { model.reasoningEfforts?.values != nil }, set: { enabled in
      model.reasoningEfforts = enabled ? .mapping(["off": nil, "low": "low", "medium": "medium", "high": "high"]) : .disabled
    })
  }
  private var mode: Binding<String> {
    Binding(get: { model.compat?.forceAdaptiveThinking == true ? "adaptive" : "budget" },
      set: { model.compat = .init(maxTokensField: model.compat?.maxTokensField, forceAdaptiveThinking: $0 == "adaptive") })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("推理等级").font(UIType.caption).foregroundStyle(Palette.muted)
        Image(systemName: "questionmark.circle").foregroundStyle(Palette.muted)
          .help("声明该模型支持的等级及其发送值。Off 留空表示不发送推理参数。")
        Spacer()
        Toggle("启用推理等级", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
          .accessibilityLabel("启用模型推理等级")
      }
      if enabled.wrappedValue {
        if apiProtocol == .anthropic {
          HStack {
            Text("推理模式").font(UIType.caption).foregroundStyle(Palette.muted)
            WorkflowSelection(title: "Anthropic 推理模式", selection: mode,
              options: [("budget", "思考预算"), ("adaptive", "自适应推理")]).frame(width: 180)
            Spacer()
          }
          Text(mode.wrappedValue == "adaptive" ? "由模型自动分配思考量，使用下方等级映射；请确认模型支持自适应推理。" : "预算模式按等级分配思考 token：Minimal 1024、Low 2048、Medium 8192、High 及以上 16384，并为回答保留空间。映射值用于自适应模式。")
            .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: 10) {
          Text("等级").frame(width: 65, alignment: .leading)
          Text("发送值")
          Spacer()
        }.font(UIType.small).foregroundStyle(Palette.muted)
        ForEach(levels, id: \.self) { level in
          HStack(spacing: 10) {
            Text(level.capitalized).font(UIType.caption).frame(width: 65, alignment: .leading)
            WorkflowTextInput(label: "\(level) 推理发送值", placeholder: level == "off" ? "不发送参数" : level,
              text: wireValue(level), font: UIType.caption, surface: Palette.paper).disabled(level == "off")
              .frame(maxWidth: 260)
            IconButton(icon: "minus", help: "移除推理等级 \(level)") {
              var values = model.reasoningEfforts?.values ?? [:]
              values.removeValue(forKey: level); model.reasoningEfforts = .mapping(values)
            }
            Spacer(minLength: 0)
          }
        }
        Menu {
          ForEach(AIReasoningEfforts.levels.filter { !levels.contains($0) }, id: \.self) { level in
            Button(level.capitalized) {
              var values = model.reasoningEfforts?.values ?? [:]
              values[level] = .some(level == "off" ? nil : level)
              model.reasoningEfforts = .mapping(values)
            }
          }
        } label: { Label("添加推理等级", systemImage: "plus").font(UIType.caption).foregroundStyle(Palette.accent) }
          .menuStyle(.borderlessButton).fixedSize().disabled(levels.count == AIReasoningEfforts.levels.count)
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: enabled.wrappedValue)
  }
  private func wireValue(_ level: String) -> Binding<String> {
    Binding(get: { (model.reasoningEfforts?.values?[level] ?? nil) ?? "" }, set: { value in
      var values = model.reasoningEfforts?.values ?? [:]
      values[level] = .some(value)
      model.reasoningEfforts = .mapping(values)
    })
  }
}
