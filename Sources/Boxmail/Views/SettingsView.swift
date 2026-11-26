import AppKit
import BoxmailCore
import SwiftUI

struct SettingsView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<AIConfig> private var config = AIConfig()
  @ViewState<Preferences> private var preferences = Preferences()
  @ViewState<[String: String]> private var aiKeys = [:]
  @ViewState<[String: String]> private var originalAIKeys = [:]
  @ViewState<String> private var promptTab = "translate"
  @ViewState<String> private var aiSection = "模型与连接"
  @ViewState<MailAccount?> private var accountToEdit = nil
  @ViewState private var signatureAccountId = ""
  @ViewState<String> private var status = ""
  @ViewState<Bool> private var loading = false
  @ViewState<Bool> private var transferringConfiguration = false
  @ViewState<MailAccount?> private var removingAccount: MailAccount?
  @ViewState<URL?> private var pendingDataDirectory = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var settingsSelection
  let tabs = ["常用", "账号", "邮箱规则", "AI", "高级", "开发者"]
  init(store: MailStore) {
    self.store = store
    _config = ViewState(wrappedValue: store.settings.ai)
    _preferences = ViewState(wrappedValue: store.settings.preferences)
  }
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        HStack(spacing: 16) {
          Text("设置").font(UIType.heading).accessibilityAddTraits(.isHeader)
          if geometry.size.width < 900 {
            FilterBar(values: tabs, selection: $store.settingsTab)
              .disabled(transferringConfiguration || loading)
          }
          Spacer()
          IconButton(icon: .x, help: "关闭设置") { dismiss() }
            .disabled(transferringConfiguration || loading)
        }.padding(.horizontal, 22).frame(height: 54).background(Palette.chrome)
        CossSeparator()
        HStack(alignment: .top, spacing: 0) {
          if geometry.size.width >= 900 {
            settingsSidebar
            CossSeparator(axis: .vertical)
          }
          settingsContent
        }
        if store.settingsTab != "邮箱规则" {
          SettingsActionBar(
            primaryTitle: loading ? "正在保存…" : "保存", isWorking: loading,
            primaryDisabled: transferringConfiguration, cancelDisabled: transferringConfiguration,
            cancel: { dismiss() }, primary: { save() }
          ) {
            if store.settingsTab == "账号" {
              Text("账号连接在编辑窗口中单独保存").font(UIType.small).foregroundStyle(Palette.muted)
            }
          }
        }
      }
    }.background(.white).tint(Palette.accent)
      .disclosureGroupStyle(SettingsDisclosureStyle())
      .sheet(item: $accountToEdit) { account in
        AccountEditorView(
          store: store, account: account,
          isNewAccount: !store.accounts.contains(where: { $0.id == account.id })
        ) { status = $0 }
        .borderlessScrollers()
      }
      .interactiveDismissDisabled(transferringConfiguration || loading)
      .cossAlert(
        "移除邮箱账户",
        isPresented: Binding(
          get: { removingAccount != nil }, set: { if !$0 { removingAccount = nil } }),
        presenting: removingAccount
      ) { account in
        CossAlertAction("取消", role: .cancel) { removingAccount = nil }
        CossAlertAction("移除", role: .destructive) {
          removeAccount(account)
        }
      } message: { _ in
        Text("将移除账户的本机邮件、草稿和 .env 中的凭证，服务器邮件会保留。")
      }
      .storeAlert(
        "操作未完成", text: { store.error }, isPresented: { store.error != nil },
        dismiss: { store.error = nil })
      .onAppear {
        config = store.settings.ai
        preferences = store.settings.preferences
        pendingDataDirectory = BackendService.shared.pendingDataDirectory
        if !tabs.contains(store.settingsTab) { store.settingsTab = "常用" }
      }
      .onChange(of: store.restoreRevision) { _, _ in
        config = store.settings.ai; preferences = store.settings.preferences
        aiKeys = [:]; originalAIKeys = [:]; accountToEdit = nil; signatureAccountId = ""
      }
  }
  private var settingsSidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(tabs, id: \.self) { tab in
        Button {
          withAnimation(UIMotion.selection(reduceMotion)) { store.settingsTab = tab }
        } label: {
          HStack(spacing: 11) {
            AppicaIcon(icon(tab), size: UILayout.iconSize)
              .frame(width: 20, height: 20).accessibilityHidden(true)
            Text(tab)
            Spacer()
          }.font(.system(size: 13, weight: store.settingsTab == tab ? .semibold : .regular))
            .foregroundStyle(store.settingsTab == tab ? Palette.ink : Palette.muted).padding(
              .horizontal, 10
            ).frame(maxWidth: .infinity).frame(height: 36)
            .contentShape(Rectangle()).background {
              if store.settingsTab == tab {
                if reduceMotion {
                  RoundedRectangle(cornerRadius: UILayout.navigationRadius, style: .continuous)
                    .fill(Palette.selected)
                } else {
                  RoundedRectangle(cornerRadius: UILayout.navigationRadius, style: .continuous)
                    .fill(Palette.selected)
                    .matchedGeometryEffect(id: "settings-selection", in: settingsSelection)
                }
              }
            }
        }.buttonStyle(
          ControlFeedback(corner: UILayout.navigationRadius)
        ).disabled(
          transferringConfiguration || loading
        )
        .controlFocus(corner: UILayout.navigationRadius)
        .accessibilityAddTraits(store.settingsTab == tab ? .isSelected : [])
        .animation(UIMotion.selection(reduceMotion), value: store.settingsTab == tab)
      }
      Spacer()
      Text(
        "Boxmail · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")"
      ).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }.padding(UILayout.windowInset).frame(width: 190).background(Palette.sidebar)
  }
  private var settingsContent: some View {
    OverlayScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text(store.settingsTab).font(UIType.title).tracking(-0.4).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if store.settingsTab == "AI" {
            Toggle("启用 AI", isOn: $config.enabled).toggleStyle(CossToggleStyle(isSwitch: true)).font(
              .system(size: 12)
            ).controlSize(.small).fixedSize().padding(.top, 4)
          }
        }
        switch store.settingsTab {
        case "AI": aiSettings
        case "账号": accountSettings
        case "邮箱规则": RuleManagementView(store: store, workspace: store.rules)
        case "常用": generalSettings
        case "开发者": DeveloperSettingsView(store: store)
        default: advancedSettings
        }
        if !status.isEmpty {
          Label(status, icon: statusFailed ? .infoCircle : .infoCircle)
            .font(.system(size: 12))
            .foregroundStyle(statusFailed ? Palette.destructive : Palette.muted)
          .textSelection(.enabled).lineSpacing(4).padding(12)
          .frame(maxWidth: .infinity, alignment: .leading).background(
            Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
        }
      }.frame(maxWidth: 720, alignment: .leading).padding(24).frame(
        maxWidth: .infinity, alignment: .leading)
    }.id(store.settingsTab).background(Palette.canvas).disabled(loading)
  }
  private var statusFailed: Bool {
    status.contains("失败") || status.contains("无法") || status.contains("授权")
  }
  private var subtitle: String {
    switch store.settingsTab {
    case "AI": return "配置清单整理、翻译与写作使用的模型和提示词"
    case "账号": return "连接邮箱并设置发信签名"
    case "邮箱规则": return "设置收信条件和邮箱动作，预览匹配后运行"
    case "常用": return "同步与阅读偏好"
    case "开发者": return "导出同步与 API 运行日志，帮助定位异常和性能问题"
    default: return "管理本机数据、诊断与同步状态"
    }
  }
  private func icon(_ tab: String) -> AppicaGlyph {
    switch tab {
    case "常用": .settings
    case "账号": .user
    case "邮箱规则": .filter2
    case "高级": .adjustments
    case "开发者": .hammer
    default: .sparkles
    }
  }
  private var aiSettings: some View {
    VStack(alignment: .leading, spacing: 20) {
      SegmentedSelection(title: "AI 设置分区", values: ["模型与连接", "任务提示词"], selection: $aiSection)
        .frame(width: 280)
      if aiSection == "模型与连接" {
        AIProviderSettingsView(
          config: $config, keys: $aiKeys, originalKeys: $originalAIKeys,
          status: $status, loading: $loading)
      } else {
        promptSettings
      }
    }
  }
  private var promptSettings: some View {
    SectionCard(title: "任务提示词") {
        WrappingFlowLayout(spacing: 6) {
          ForEach(
            [
              ("translate", "邮件翻译"), ("compose", "帮我写"),
              ("reply", "基于原邮件回复"), ("conversationReply", "参考会话回复"),
            ], id: \.0
          ) { item in
            SelectionButton(title: item.1, selected: promptTab == item.0, size: .compact) {
              promptTab = item.0
            }
          }
        }
        PlainTextEditor(
          text: Binding(
            get: { config.prompts[promptTab] ?? AIPromptDefaults.values[promptTab] ?? "" },
            set: { config.prompts[promptTab] = $0 }),
          fontSize: 13, inset: .init(width: 5, height: 5), accessibilityLabel: "AI 默认提示词"
        ).frame(height: 160).padding(12)
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
          .id(promptTab)
        Text("清空提示词后保存会恢复默认。翻译和写作会将对应范围的内容提交给已配置的服务商。").font(
          .system(size: 11)
        )
        .foregroundStyle(Palette.muted)
        HStack {
          Spacer()
          ActionButton(title: "恢复当前默认", color: Palette.accent, size: .compact) {
            config.prompts[promptTab] = AIPromptDefaults.values[promptTab]
          }
      }
    }
  }
  private var accountSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(spacing: 0) {
        ForEach(store.accounts) { account in
          HStack(spacing: 12) {
            SenderAvatar(name: account.sidebarName, size: 30).fixedSize()
            VStack(alignment: .leading, spacing: 4) {
              Text(account.sidebarName).font(UIType.section).lineLimit(1).cossTooltip(account.sidebarName)
              Text(account.email).font(UIType.caption).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.middle).cossTooltip(account.email)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if account.isDemo {
              Tag(text: "演示数据")
            } else {
              ActionButton(title: "编辑") { accountToEdit = account }
              IconMenu(icon: .dots, help: "账号更多操作") {
                CossMenuItem.command("移除账号…", icon: .trash, destructive: true) { removingAccount = account }
              }
            }
          }.padding(16)
          if account.id != store.accounts.last?.id {
            CossSeparator().padding(.leading, 58)
          }
        }
      }.background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
      ActionButton(title: "添加邮箱", icon: .plus, emphasis: .secondary) { accountToEdit = MailAccount() }
      signatureSettings
    }
  }
  private var generalSettings: some View {
    VStack(spacing: 16) {
      syncSettings
      readSettings
      NotificationPreferencesView(preferences: $preferences, coordinator: store.notifications)
      spamSettings
    }
  }
  private var syncSettings: some View {
    SectionCard(title: "邮箱同步", icon: .refresh, contentSpacing: 12) {
      HStack(spacing: 16) {
        WorkflowStepper(title: "自动同步间隔", value: $preferences.syncMinutes, range: 1...60, unit: "分钟")
        Spacer(minLength: 0)
        ActionButton(title: "立即同步", icon: .refresh, color: Palette.accent) {
          Task { await store.syncAll() }
        }.disabled(store.busy.contains("sync"))
      }
      Toggle("实时接收新邮件", isOn: Binding(
        get: { preferences.realtimeSync ?? false }, set: { preferences.realtimeSync = $0 }
      )).font(UIType.body)
      Text("应用打开时按间隔同步，并逐批补齐历史邮件。可在主窗口停止；下次同步会继续补齐。")
        .font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
  }
  private var signatureSettings: some View {
    let signature = Binding(
      get: { preferences.accountSignatures?[signatureAccountId] ?? preferences.signature },
      set: { value in
        if signatureAccountId.isEmpty { preferences.signature = value }
        else {
          var signatures = preferences.accountSignatures ?? [:]
          signatures[signatureAccountId] = value
          preferences.accountSignatures = signatures
        }
      })
    return SectionCard(title: "邮件签名", icon: .feather) {
      HStack(spacing: 8) {
        WorkflowSelection(title: "应用签名的邮件账户", selection: $signatureAccountId,
          options: [("", "默认签名")] + store.accounts.map { ($0.id, $0.email) })
          .frame(width: 270)
        if !signatureAccountId.isEmpty, preferences.accountSignatures?[signatureAccountId] != nil {
          ActionButton(title: "使用默认签名") { preferences.accountSignatures?.removeValue(forKey: signatureAccountId) }
        }
      }
      PlainTextEditor(text: signature, fontSize: 13, inset: .init(width: 4, height: 4),
        accessibilityLabel: "邮件签名").frame(height: 120).padding(12).background(
          Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
      Text(signatureAccountId.isEmpty ? "未设置单独签名的账户使用此签名。" : "保存后用于该账户新建的草稿。")
        .font(UIType.caption).foregroundStyle(Palette.muted)
    }
  }
  private var readSettings: some View {
    SectionCard(title: "阅读行为", icon: .mailOpened) {
      Toggle("打开邮件时标记为已读", isOn: $preferences.markRead).font(.system(size: 13))
      WorkflowStepper(title: "正文字号", value: $preferences.fontSize, range: 12...24, unit: "pt")
      Toggle("屏蔽远程图片", isOn: $preferences.blockRemoteImages).font(.system(size: 13))
      Text("HTML 邮件保留原文排版，内嵌图片直接展示。外部图片可在邮件中单独加载，邮件中的脚本不会执行。已读和星标更改会在下次同步时提交至服务器。").font(
        .system(size: 12)
      )
      .foregroundStyle(Palette.muted)
    }
  }
  private var spamSettings: some View {
    DisclosureGroup("垃圾邮件处理") {
      Text("同步时会识别服务商的垃圾邮件文件夹。默认屏蔽远程图片自动加载。AI 分类只修改本机分类标签。第一版暂未提供本机垃圾邮件训练或黑名单规则。").font(
        .system(size: 13)
      ).lineSpacing(7)
      Text("需要管理垃圾邮件时，可在服务商网页邮箱调整规则。").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }.font(UIType.caption).padding(.horizontal, 4)
  }
  private var advancedSettings: some View {
    VStack(spacing: 16) {
      LocalDataSettingsView(store: store, pendingDirectory: $pendingDataDirectory)
        .disabled(transferringConfiguration)
      ConfigurationSettingsView(store: store, transferring: $transferringConfiguration)
      BackupSettingsView(store: store).disabled(transferringConfiguration)
      SearchIndexSettingsView(store: store).disabled(transferringConfiguration)
      SectionCard(title: "运行诊断", icon: .stethoscope) {
        Text(
          "本机服务：\(store.ready ? "已连接" : "未连接")\n待同步更改：\(store.pendingMutations) 项\n应用版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")"
        )
        .font(.system(size: 12)).lineSpacing(8)
        Text("附件由模型理解：图片直接上传，PDF 转为页面图片，Word 和表格提取内容。OAuth 登录和服务器草稿同步尚未接入。").font(
          .system(size: 11)
        ).foregroundStyle(Palette.muted)
      }
    }
  }
  private func save() {
    guard !loading && !transferringConfiguration else { return }
    loading = true
    Task {
      defer { loading = false }
      var settingsSaved = false
      do {
        if let pendingDataDirectory {
          _ = try LocalDataStorage.validateDestination(
            from: BackendService.shared.dataDirectory, to: pendingDataDirectory)
        }
        if !store.ready {
          try BackendService.shared.scheduleDataDirectory(pendingDataDirectory)
          status = "数据位置设置已保存，请恢复原数据目录后重新启动。"
          dismiss()
          return
        }
        if let issue = config.validationIssue { throw BackendService.shared.failure(issue) }
        var changedKeys: [String: String] = [:]
        for account in config.credentialAccounts {
          if let key = aiKeys[account], originalAIKeys[account] != key {
            if AIModel.hasControls(key.trimmingCharacters(in: .whitespacesAndNewlines)) {
              throw BackendService.shared.failure("API Key 不能包含控制字符。")
            }
            changedKeys[account] = key.trimmingCharacters(in: .whitespacesAndNewlines)
          }
        }
        let removedProviders = store.settings.ai.providers.filter { old in !config.providers.contains { $0.id == old.id } }
        let refreshed = try await store.saveSettings(
          ai: config, preferences: preferences, keys: changedKeys)
        settingsSaved = true
        for account in changedKeys.keys { originalAIKeys[account] = aiKeys[account] }
        for provider in removedProviders { try CredentialService.save("", account: provider.credentialAccount) }
        try BackendService.shared.scheduleDataDirectory(pendingDataDirectory)
        if !refreshed {
          status = "设置已保存，邮件列表刷新未完成。请重新加载列表，或导出诊断日志。"
          return
        }
        status = pendingDataDirectory == nil ? "设置已保存" : "设置已保存，重新打开 Boxmail 后迁移本机数据。"
        dismiss()
      } catch {
        status =
          settingsSaved
          ? "设置已保存，后续操作未完成：\(error.localizedDescription)"
          : "保存失败：\(error.localizedDescription)"
      }
    }
  }
  private func removeAccount(_ account: MailAccount) {
    store.action("remove-account") {
      try await BackendService.shared.perform("/accounts/\(account.id)", method: "DELETE")
      try CredentialService.save("", account: "mail-\(account.id)")
    }
  }
}
