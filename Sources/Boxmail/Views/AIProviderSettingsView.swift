import BoxmailCore
import SwiftUI

struct AIProviderSettingsView: View {
  @Binding var config: AIConfig
  @Binding var keys: [String: String]
  @Binding var originalKeys: [String: String]
  @Binding var status: String
  @Binding var loading: Bool
  @ViewState<Bool> private var addingProvider = false
  @ViewState<Bool> private var discoveringModels = false
  @ViewState<[AIModel]> private var candidates = []
  @ViewState<Int> private var catalogRevision = 0
  @ViewState<Bool> private var showingConnection = false
  @ViewState<Bool> private var showingCatalog = false

  private var key: Binding<String> {
    let account = config.credentialAccount
    return Binding(get: { keys[account] ?? "" }, set: { keys[account] = $0 })
  }
  private var catalog: [AIModel] { config.activeProvider.models }
  private var effortLevels: [String] { config.activeProvider.definition(for: config.model).reasoningLevels }
  private var editableCatalog: Binding<[AIModel]> {
    Binding(get: { catalog.map { config.activeProvider.resolvedModel($0) } },
      set: { config.activeProvider.models = $0 })
  }

  var body: some View {
    SectionCard(title: "模型与连接", icon: "", contentSpacing: 16) {
      HStack(spacing: SettingsFormLayout.columnGap) {
        SettingsFormLabel(title: "当前服务商")
        WorkflowSelection(
          title: "当前 AI 服务商", selection: $config.providerId,
          options: config.providers.map { ($0.id, $0.name) }
        )
        .frame(width: SettingsFormLayout.fieldWidth)
        SettingsInlineAction(title: "自定义 API", icon: "plus") { addingProvider = true }
          .disabled(config.providers.count >= 20)
      }.frame(maxWidth: SettingsFormLayout.formWidth, alignment: .leading)
      HStack(spacing: SettingsFormLayout.columnGap) {
        SettingsFormLabel(title: "模型设置")
        SettingsAISelectionView(
          model: $config.model, effort: $config.effort, models: catalog,
          effortLevels: effortLevels)
        SettingsInlineAction(title: "获取模型", icon: "arrow.clockwise") { refreshModels() }
      }.frame(maxWidth: SettingsFormLayout.formWidth, alignment: .leading)
      Text("邮件总结、翻译和写信共用当前模型。内容仅在使用 AI 功能时提交给所选服务商。")
        .font(UIType.small).foregroundStyle(Palette.muted)
      Divider().overlay(Palette.softBorder)
      DisclosureGroup("连接设置", isExpanded: $showingConnection) {
        VStack(alignment: .leading, spacing: 14) {
          SettingsFieldRow(
            title: "显示名称", text: $config.activeProvider.name, placeholder: "服务商名称")
          SettingsFieldRow(
            title: "API 地址", text: $config.baseURL,
            placeholder: config.apiProtocol.addressPlaceholder)
          HStack(spacing: SettingsFormLayout.columnGap) {
            SettingsFormLabel(title: "API 协议")
            WorkflowSelection(
              title: "API 协议", selection: $config.apiProtocol,
              options: AIAPIProtocol.allCases.map { ($0, $0.title) }
            ).frame(width: SettingsFormLayout.fieldWidth)
            Spacer(minLength: 0)
          }
          HStack(spacing: SettingsFormLayout.columnGap) {
            SettingsFormLabel(title: "API Key")
            SecureField("", text: key).settingsTextInput()
              .inputPlaceholder("密钥保存在本机 .env 文件", visible: key.wrappedValue.isEmpty)
              .accessibilityLabel("当前服务商 API Key").frame(width: SettingsFormLayout.fieldWidth)
            SettingsInlineAction(title: "测试连接", icon: "bolt") { testConnection() }
              .disabled(
                config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || config.validationIssue != nil)
          }
          HStack(spacing: SettingsFormLayout.columnGap) {
            SettingsFormLabel(title: "请求超时")
            TextField("120", value: $config.timeout, format: .number.grouping(.never))
              .settingsTextInput().frame(width: SettingsFormLayout.portWidth).accessibilityLabel(
                "请求超时（秒）")
            Text("秒").font(UIType.caption).foregroundStyle(Palette.muted)
            Spacer()
          }
          HStack {
            Text("服务商标识：" + config.providerId).font(UIType.small).foregroundStyle(Palette.muted)
              .textSelection(.enabled)
            Spacer()
            if config.providerId != "default" {
              ActionButton(title: "移除服务商…", color: Palette.amber, size: .compact, role: .destructive) {
                removeProvider()
              }
                .disabled(config.providers.count <= 1)
            }
          }
        }.padding(.top, 14)
      }.font(UIType.caption)
      Divider().overlay(Palette.softBorder)
      DisclosureGroup("模型目录 · \(catalog.count) 个", isExpanded: $showingCatalog) {
        AIModelCatalogEditor(
          models: editableCatalog, selectedModel: $config.model, apiProtocol: config.apiProtocol
        )
        .padding(.top, 14)
      }.font(UIType.caption)
      if let issue = config.validationIssue {
        Text(issue).font(UIType.caption).foregroundStyle(Palette.amber)
          .fixedSize(horizontal: false, vertical: true)
      }
    }.disabled(loading)
      .sheet(isPresented: $addingProvider) {
        NewAIProviderView(takenIDs: config.providers.map(\.id)) { provider, key in
          config.providers.append(provider)
          keys[provider.credentialAccount] = key
          config.providerId = provider.id
          status = "已添加 \(provider.name)，点击“保存”生效。"
        }
      }
      .sheet(isPresented: $discoveringModels) {
        AIModelDiscoveryView(candidates: candidates, existingIDs: Set(catalog.map(\.id))) {
          models in
          config.activeProvider.models.append(contentsOf: models)
          config.activeProvider.catalogConfigured = true
          status = "已添加 \(models.count) 个模型，点击“保存”生效。"
        }
      }
      .onChange(of: effortLevels, initial: true) { _, levels in
        if !levels.isEmpty, !levels.contains(config.effort) {
          config.effort = levels.contains("high") ? "high" : (levels.first { $0 != "off" } ?? "off")
        }
      }
      .task(id: config.providerId) {
        loadKey()
        showingConnection =
          key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        showingCatalog = !catalog.compactMap(\.validationIssue).isEmpty
      }
      .task(id: config.catalogScope) { await loadCatalog() }
      .onChange(of: config.activeProvider.models) { _, _ in
        config.activeProvider.catalogConfigured = true
      }
  }

  private func loadKey() {
    let account = config.credentialAccount
    guard keys[account] == nil else { return }
    do {
      let value = try CredentialService.read(account)
      keys[account] = value; originalKeys[account] = value
    } catch { status = error.localizedDescription }
  }
  private func removeProvider() {
    guard config.providers.count > 1 else { return }
    let provider = config.activeProvider
    config.providers.removeAll { $0.id == provider.id }
    config.providerId = config.providers[0].id
    keys.removeValue(forKey: provider.credentialAccount)
    originalKeys.removeValue(forKey: provider.credentialAccount)
    status = "已移除 \(provider.name)，点击“保存”生效；取消可保留原设置。"
  }
  private func testConnection() {
    let requested = config, apiKey = key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    loading = true; status = "正在测试 \(requested.activeProvider.name)…"
    Task {
      defer { loading = false }
      do {
        let _: EmptyResponse = try await BackendService.shared.request("/ai/test", method: "POST",
          body: ["config": try jsonObject(requested), "apiKey": apiKey],
          timeout: TimeInterval(max(10, min(600, requested.timeout)) + 30))
        status = "\(requested.activeProvider.name) 连接成功"
      } catch { status = "连接失败：\(error.localizedDescription)" }
    }
  }
  private func refreshModels() {
    let requested = config, apiKey = key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    catalogRevision += 1
    let revision = catalogRevision
    loading = true; status = "正在获取 \(requested.activeProvider.name) 的模型…"
    Task {
      defer { loading = false }
      do {
        let result = try await AIModelDiscovery.fetch(requested.activeProvider, apiKey: apiKey)
        guard config.catalogScope == requested.catalogScope, catalogRevision == revision else { return }
        catalogRevision += 1
        candidates = result
        discoveringModels = !candidates.isEmpty
        status = candidates.isEmpty ? "服务商未返回模型，可手动添加。" : "已读取 \(candidates.count) 个模型，请选择加入目录。"
      } catch {
        guard config.catalogScope == requested.catalogScope else { return }
        status = "获取失败，已保留模型目录：\(error.localizedDescription)"
        if !candidates.isEmpty { discoveringModels = true }
      }
    }
  }
  private func loadCatalog() async {
    let requested = config, revision = catalogRevision
    candidates = []
    var components = URLComponents()
    components.queryItems = [URLQueryItem(name: "baseURL", value: requested.baseURL),
      URLQueryItem(name: "providerId", value: requested.providerId),
      URLQueryItem(name: "apiProtocol", value: requested.apiProtocol.rawValue)]
    do {
      let result: ModelsResponse = try await BackendService.shared.request("/ai/models?" + (components.percentEncodedQuery ?? ""))
      guard !Task.isCancelled, config.catalogScope == requested.catalogScope, catalogRevision == revision else { return }
      candidates = result.catalog
    } catch { /* Cache discovery is optional; manually configured models remain available. */ }
  }
}
