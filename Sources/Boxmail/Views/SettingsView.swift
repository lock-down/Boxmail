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
  @ViewState<String> private var promptTab = "summary"
  @ViewState<String> private var aiSection = "模型与连接"
  @ViewState<MailAccount?> private var accountToEdit = nil
  @ViewState<String> private var status = ""
  @ViewState<Bool> private var loading = false
  @ViewState<Bool> private var transferringConfiguration = false
  @ViewState<MailAccount?> private var removingAccount: MailAccount?
  @ViewState<URL?> private var pendingDataDirectory = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var settingsSelection
  let tabs = ["常用", "账号", "AI 助手", "高级", "开发者"]
  init(store: MailStore) {
    self.store = store
    _config = ViewState(wrappedValue: store.settings.ai)
    _preferences = ViewState(wrappedValue: store.settings.preferences)
  }
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        HStack(spacing: 16) {
          Text("设置").font(.system(size: 15, weight: .semibold))
          if geometry.size.width < 900 {
            FilterBar(values: tabs, selection: $store.settingsTab)
              .disabled(transferringConfiguration || loading)
          }
          Spacer()
          IconButton(icon: "xmark", help: "关闭设置") { dismiss() }
            .disabled(transferringConfiguration || loading)
        }.padding(.horizontal, 22).frame(height: 54).background(Palette.chrome)
        Divider()
        HStack(alignment: .top, spacing: 0) {
          if geometry.size.width >= 900 {
            settingsSidebar
            Divider()
          }
          settingsContent
        }
        SettingsActionBar(
          primaryTitle: loading ? "正在保存…" : "保存", isWorking: loading,
          primaryDisabled: transferringConfiguration, cancelDisabled: transferringConfiguration,
          cancel: { dismiss() }, primary: { save() }
        ) {
          if store.settingsTab == "账号" {
            Text("账号在编辑窗口中单独保存").font(UIType.small).foregroundStyle(Palette.muted)
          }
        }
      }
    }.frame(
      minWidth: 700, idealWidth: 1000, maxWidth: 1000,
      minHeight: 500, idealHeight: 700, maxHeight: 750
    ).background(.white).tint(Palette.blue)
      .disclosureGroupStyle(SettingsDisclosureStyle())
      .sheet(item: $accountToEdit) { account in
        AccountEditorView(
          store: store, account: account,
          isNewAccount: !store.accounts.contains(where: { $0.id == account.id })
        ) { status = $0 }
        .borderlessScrollers()
      }
      .interactiveDismissDisabled(transferringConfiguration || loading)
      .alert(
        "移除邮箱账户",
        isPresented: Binding(
          get: { removingAccount != nil }, set: { if !$0 { removingAccount = nil } })
      ) {
        Button("取消", role: .cancel) { removingAccount = nil }
        Button("移除", role: .destructive) {
          if let account = removingAccount { removeAccount(account) }
          removingAccount = nil
        }
      } message: {
        Text("将移除账户的本机邮件、草稿和 .env 中的凭证，服务器邮件会保留。")
      }
      .alert(
        "操作未完成",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("确定") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
      .onAppear {
        config = store.settings.ai
        preferences = store.settings.preferences
        pendingDataDirectory = BackendService.shared.pendingDataDirectory
        if !tabs.contains(store.settingsTab) { store.settingsTab = "常用" }
      }
      .onChange(of: store.restoreRevision) { _, _ in
        config = store.settings.ai; preferences = store.settings.preferences
        aiKeys = [:]; originalAIKeys = [:]; accountToEdit = nil
      }
  }
  private var settingsSidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(tabs, id: \.self) { tab in
        Button {
          withAnimation(UIMotion.selection(reduceMotion)) { store.settingsTab = tab }
        } label: {
          HStack(spacing: 11) {
            Image(systemName: icon(tab)).font(.system(size: 14, weight: .medium))
              .frame(width: 20, height: 20).accessibilityHidden(true)
            Text(tab)
            Spacer()
          }.font(.system(size: 13, weight: store.settingsTab == tab ? .semibold : .regular))
            .foregroundStyle(store.settingsTab == tab ? Palette.accent : Palette.ink).padding(
              .horizontal, 10
            ).frame(maxWidth: .infinity).frame(height: 36)
            .contentShape(Rectangle()).background {
              if store.settingsTab == tab {
                if reduceMotion {
                  RoundedRectangle(cornerRadius: UILayout.selectionRadius, style: .continuous)
                    .fill(Palette.accentSoft)
                } else {
                  RoundedRectangle(cornerRadius: UILayout.selectionRadius, style: .continuous)
                    .fill(Palette.accentSoft)
                    .matchedGeometryEffect(id: "settings-selection", in: settingsSelection)
                }
              }
            }
        }.buttonStyle(
          ControlFeedback(selected: store.settingsTab == tab, corner: UILayout.selectionRadius)
        ).disabled(
          transferringConfiguration || loading
        )
        .controlFocus(corner: UILayout.selectionRadius)
        .accessibilityAddTraits(store.settingsTab == tab ? .isSelected : [])
        .animation(UIMotion.selection(reduceMotion), value: store.settingsTab == tab)
      }
      Spacer()
      Text(
        "Boxmail · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")"
      ).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }.padding(14).frame(width: 190).background(Palette.sidebar)
  }
  private var settingsContent: some View {
    OverlayScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            Text(store.settingsTab).font(UIType.title).tracking(-0.3)
            Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(3)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if store.settingsTab == "AI 助手" {
            Toggle("启用 AI 助手", isOn: $config.enabled).toggleStyle(.switch).font(
              .system(size: 12)
            ).controlSize(.small).fixedSize().padding(.top, 4)
          }
        }
        switch store.settingsTab {
        case "AI 助手": aiSettings
        case "账号": accountSettings
        case "常用": generalSettings
        case "开发者": DeveloperSettingsView(store: store)
        default: advancedSettings
        }
        if !status.isEmpty {
          Label(
            status,
            systemImage: status.contains("失败") || status.contains("无法") || status.contains("授权")
              ? "exclamationmark.circle" : "info.circle"
          )
          .font(.system(size: 12)).foregroundStyle(
            status.contains("失败") || status.contains("无法") || status.contains("授权")
              ? Palette.amber : Palette.muted
          )
          .textSelection(.enabled).lineSpacing(4).padding(12)
          .frame(maxWidth: .infinity, alignment: .leading).background(
            Palette.blueSoft, in: RoundedRectangle(cornerRadius: 7))
        }
      }.frame(maxWidth: 720, alignment: .leading).padding(24).frame(
        maxWidth: .infinity, alignment: .leading)
    }.id(store.settingsTab).background(Palette.canvas).disabled(loading)
  }
  private var subtitle: String {
    switch store.settingsTab {
    case "AI 助手": return "配置模型接口与默认提示词，为邮件总结、回复、整理和附件解析提供能力"
    case "账号": return "使用邮箱授权码连接 IMAP 和 SMTP，凭证保存在本机 .env 文件"
    case "常用": return "同步频率、阅读行为与邮件签名"
    case "写邮件": return "配置默认签名和草稿行为"
    case "阅读邮件": return "调整阅读字号与已读行为"
    case "反垃圾": return "同步邮箱服务商的垃圾邮件分类"
    case "开发者": return "导出同步与 API 运行日志，帮助定位异常和性能问题"
    default: return "管理本机数据、诊断与同步状态"
    }
  }
  private func icon(_ tab: String) -> String {
    switch tab {
    case "常用": return "gearshape"
    case "账号": return "person"
    case "写邮件": return "square.and.pencil"
    case "阅读邮件": return "envelope.open"
    case "反垃圾": return "shield"
    case "高级": return "slider.horizontal.3"
    case "开发者": return "hammer"
    default: return "sparkles"
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
    SectionCard(title: "任务提示词", icon: "") {
        WrappingFlowLayout(spacing: 6) {
          ForEach(
            [
              ("summary", "邮件总结"), ("reply", "自动回复"), ("classify", "智能整理"), ("attachment", "附件解析"),
              ("compose", "AI 写信"),
              ("translate", "邮件翻译"),
              ("conversationSummary", "会话总结"), ("conversationReply", "会话回复"),
            ], id: \.0
          ) { item in
            FilterButton(title: item.1, selected: promptTab == item.0, compact: true) {
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
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
          .id(promptTab)
        Text("已预设每类任务的提示词，可自定义语气和分析要求。清空后保存会恢复默认。邮件内容、图片和文档内容会发送至你配置的 AI 服务。").font(
          .system(size: 11)
        )
        .foregroundStyle(Palette.muted)
        HStack {
          Spacer()
          Button("恢复当前默认") { config.prompts[promptTab] = AIPromptDefaults.values[promptTab] }
            .buttonStyle(ControlFeedback(corner: 6)).font(
              .system(size: 11)
          ).foregroundStyle(Palette.accent).padding(.vertical, 4).controlFocus(corner: 6)
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
              Text(account.sidebarName).font(UIType.section).lineLimit(1).help(account.sidebarName)
              Text(account.email).font(UIType.caption).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.middle).help(account.email)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if account.isDemo {
              Tag(text: "演示数据")
            } else {
              ActionButton(title: "编辑") { accountToEdit = account }
              IconMenu(icon: "ellipsis", help: "账号更多操作") {
                Button("移除账号…", role: .destructive) { removingAccount = account }
              }
            }
          }.padding(16)
          if account.id != store.accounts.last?.id {
            Divider().overlay(Palette.softBorder).padding(.leading, 58)
          }
        }
      }.background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      ActionButton(title: "添加邮箱", icon: "plus", kind: .primary) { accountToEdit = MailAccount() }
    }
  }
  private var generalSettings: some View {
    VStack(spacing: 16) {
      syncSettings
      readSettings
      composeSettings
      spamSettings
    }
  }
  private var syncSettings: some View {
    SectionCard(title: "邮箱同步", icon: "arrow.triangle.2.circlepath", contentSpacing: 12) {
      HStack(spacing: 16) {
        WorkflowStepper(title: "自动同步间隔", value: $preferences.syncMinutes, range: 1...60, unit: "分钟")
        Spacer(minLength: 0)
        ActionButton(title: "立即同步", icon: "arrow.clockwise", kind: .primary) {
          Task { await store.syncAll() }
        }.disabled(store.busy.contains("sync"))
      }
      Text("应用打开时按间隔同步，并逐批补齐历史邮件。可在主窗口停止；下次同步会继续补齐。")
        .font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
  }
  private var composeSettings: some View {
    SectionCard(title: "邮件签名", icon: "signature") {
      PlainTextEditor(text: $preferences.signature, fontSize: 13, inset: .init(width: 4, height: 4),
        accessibilityLabel: "邮件签名").frame(height: 144).padding(12).background(
        Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 620, alignment: .leading)
      Text("新邮件会自动附上签名。草稿在停止输入后自动保存到本机；发送前始终需要确认。").font(.system(size: 12)).foregroundStyle(
        Palette.muted)
    }
  }
  private var readSettings: some View {
    SectionCard(title: "阅读行为", icon: "envelope.open") {
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
      SectionCard(title: "运行诊断", icon: "stethoscope") {
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
            if key.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
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
