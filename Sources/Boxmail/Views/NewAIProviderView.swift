import BoxmailCore
import SwiftUI

struct NewAIProviderView: View {
  let takenIDs: [String]
  let add: (AIProvider, String) -> Void
  @Environment(\.dismiss) private var dismiss
  @ViewState<String> private var id = ""
  @ViewState<String> private var name = ""
  @ViewState<String> private var baseURL = ""
  @ViewState<String> private var key = ""
  @ViewState<String> private var model = ""
  @ViewState<[AIModel]> private var models = []
  @ViewState<[AIModel]> private var candidates = []
  @ViewState<Bool> private var discovering = false
  @ViewState<Bool> private var fetching = false
  @ViewState<String> private var status = ""
  @ViewState<AIAPIProtocol> private var apiProtocol = .chatCompletions
  @FocusState private var focused: Bool

  private var provider: AIProvider {
    let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
    return AIProvider(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : name,
      baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines), apiProtocol: apiProtocol,
      model: model.isEmpty ? (models.first?.id ?? "") : model, models: models)
  }
  private var issue: String? {
    if takenIDs.contains(provider.id) { return "此 Provider ID 已被使用，请更换。" }
    if let issue = provider.validationIssue { return issue }
    if key.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return "API Key 不能包含控制字符。" }
    return nil
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("自定义模型 API").font(UIType.title)
        Spacer()
        IconButton(icon: "xmark", help: "取消添加服务商") { dismiss() }
      }
      Text("接入兼容 OpenAI 或 Anthropic 协议的服务。API 密钥按服务商单独保存在系统钥匙串。")
        .font(UIType.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 14) {
          VStack(spacing: 12) {
            row("Provider ID", text: $id, placeholder: "acme-gateway").focused($focused)
            Text("以小写字母开头，使用小写字母、数字和连字符；创建后保持不变。")
              .font(UIType.small).foregroundStyle(Palette.muted)
              .padding(.leading, SettingsFormLayout.labelWidth + SettingsFormLayout.columnGap)
              .frame(maxWidth: .infinity, alignment: .leading)
            row("显示名称", text: $name, placeholder: "例如 工作模型服务")
            row("API 地址", text: $baseURL, placeholder: apiProtocol.addressPlaceholder)
            HStack(spacing: SettingsFormLayout.columnGap) {
              SettingsFormLabel(title: "API 协议")
              WorkflowSelection(title: "新服务商 API 协议", selection: $apiProtocol,
                options: AIAPIProtocol.allCases.map { ($0, $0.title) })
            }
            HStack(spacing: SettingsFormLayout.columnGap) {
              SettingsFormLabel(title: "API Key")
              SecureField("", text: $key).settingsTextInput()
                .inputPlaceholder("输入 API 密钥，本地服务可留空", visible: key.isEmpty)
                .accessibilityLabel("新服务商 API Key")
            }
          }
          Divider().overlay(Palette.softBorder)
          HStack {
            Text("模型参数按服务商提供的能力填写。").font(UIType.small).foregroundStyle(Palette.muted)
            Spacer()
            SettingsInlineAction(title: fetching ? "正在获取…" : "获取可用模型", icon: "arrow.clockwise") { fetchModels() }
              .disabled(fetching || provider.id.isEmpty || provider.baseURL.isEmpty)
          }
          AIModelCatalogEditor(models: $models, selectedModel: $model, apiProtocol: apiProtocol)
          if !status.isEmpty { Text(status).font(UIType.small).foregroundStyle(Palette.muted) }
        }.padding(2)
      }.frame(height: 470)
      if !id.isEmpty, let issue, !models.compactMap(\.validationIssue).contains(issue) {
        Text(issue).font(UIType.small).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Text("添加后点击设置页的“应用”或“确定”保存。")
          .font(UIType.small).foregroundStyle(Palette.muted)
        Spacer()
        ActionButton(title: "取消") { dismiss() }.keyboardShortcut(.cancelAction)
        ActionButton(title: "添加并使用", icon: "plus", kind: .primary) {
          add(provider, key.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss()
        }.disabled(issue != nil).keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 680).background(Palette.paper).onAppear { focused = true }
      .sheet(isPresented: $discovering) {
        AIModelDiscoveryView(candidates: candidates, existingIDs: Set(models.map(\.id))) { models.append(contentsOf: $0) }
      }
  }
  private func fetchModels() {
    let requested = provider
    let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
    fetching = true
    Task {
      defer { fetching = false }
      do {
        let result: ModelsResponse = try await BackendService.shared.request("/ai/models", method: "POST",
          body: ["config": ["providerId": requested.id, "baseURL": requested.baseURL,
            "apiProtocol": requested.apiProtocol.rawValue, "model": ""], "apiKey": apiKey])
        guard provider.id == requested.id, provider.baseURL == requested.baseURL, provider.apiProtocol == requested.apiProtocol else { return }
        candidates = result.catalog; discovering = !candidates.isEmpty
        status = candidates.isEmpty ? "服务商未返回模型，可手动添加。" : "选择要加入目录的模型。"
      } catch { status = "获取失败：\(error.localizedDescription)" }
    }
  }
  private func row(_ title: String, text: Binding<String>, placeholder: String) -> some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      WorkflowTextInput(label: title, placeholder: placeholder, text: text, font: UIType.caption)
    }
  }
}
