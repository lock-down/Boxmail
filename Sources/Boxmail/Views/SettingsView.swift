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
  @ViewState<String> private var status = ""
  @ViewState<MailAccount> private var account = MailAccount()
  @ViewState<String> private var password = ""
  @ViewState<String> private var selectedAccountId = ""
  @ViewState<Bool> private var editingAccount = false
  @ViewState<Bool> private var loading = false
  @ViewState<Bool> private var transferringConfiguration = false
  @ViewState<MailAccount?> private var removingAccount: MailAccount?
  @ViewState<URL?> private var pendingDataDirectory = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var settingsSelection
  let tabs = ["常用", "账号", "写邮件", "阅读邮件", "反垃圾", "高级", "AI 助手", "开发者"]
  init(store: MailStore) {
    self.store = store
    _config = ViewState(wrappedValue: store.settings.ai)
    _preferences = ViewState(wrappedValue: store.settings.preferences)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("设置").font(.system(size: 15, weight: .semibold))
        Spacer()
        IconButton(icon: "xmark", help: "关闭设置") { dismiss() }.disabled(transferringConfiguration)
      }.padding(.horizontal, 22).frame(height: 54).background(Palette.chrome)
      Divider()
      HStack(alignment: .top, spacing: 0) {
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
                    if reduceMotion { RoundedRectangle(cornerRadius: 7).fill(Palette.accentSoft) }
                    else {
                      RoundedRectangle(cornerRadius: 7).fill(Palette.accentSoft)
                        .matchedGeometryEffect(id: "settings-selection", in: settingsSelection)
                    }
                  }
                }
            }.buttonStyle(ControlFeedback(selected: store.settingsTab == tab)).disabled(transferringConfiguration)
              .controlFocus()
              .accessibilityAddTraits(store.settingsTab == tab ? .isSelected : [])
              .animation(UIMotion.selection(reduceMotion), value: store.settingsTab == tab)
          }
          Spacer()
          Text(
            "Boxmail · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")"
          ).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }.padding(14).frame(width: 190).background(Palette.sidebar)
        Divider()
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
                  .system(size: 12)).controlSize(.small).fixedSize().padding(.top, 4)
              }
            }
            switch store.settingsTab {
            case "AI 助手": aiSettings
            case "账号": accountSettings
            case "常用": generalSettings
            case "写邮件": composeSettings
            case "阅读邮件": readSettings
            case "反垃圾": spamSettings
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
        }.id(store.settingsTab).background(Palette.canvas)
      }
      Divider()
      HStack {
        if loading { ProgressView().controlSize(.small) }
        Spacer()
        ActionButton(title: "取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(transferringConfiguration)
        ActionButton(title: "应用") { save(close: false) }.disabled(loading || transferringConfiguration)
        ActionButton(title: "确定", kind: .primary) { save(close: true) }.disabled(loading || transferringConfiguration)
      }.padding(.horizontal, 22).frame(height: 56).background(Palette.chrome)
    }.frame(width: 1000, height: 750).background(.white).tint(Palette.blue)
      .interactiveDismissDisabled(transferringConfiguration)
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
      }
      .onChange(of: store.restoreRevision) { _, _ in
        config = store.settings.ai; preferences = store.settings.preferences
        aiKeys = [:]; originalAIKeys = [:]; editingAccount = false; password = ""
      }
  }
  private var subtitle: String {
    switch store.settingsTab {
    case "AI 助手": return "配置模型接口与默认提示词，为邮件总结、回复、整理和附件解析提供能力"
    case "账号": return "使用邮箱授权码连接 IMAP 和 SMTP，凭证保存在本机 .env 文件"
    case "常用": return "设置邮箱同步与桌面使用偏好"
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
    VStack(spacing: 16) {
      AIProviderSettingsView(config: $config, keys: $aiKeys, originalKeys: $originalAIKeys,
        status: $status, loading: $loading)
      SectionCard(title: "系统默认提示词", icon: "curlybraces") {
        WrappingFlowLayout(spacing: 6) {
          ForEach(
            [
              ("summary", "邮件总结"), ("reply", "自动回复"), ("classify", "智能整理"), ("attachment", "附件解析"),
              ("compose", "AI 写信"),
              ("translate", "邮件翻译"),
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
  }
  private var accountSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(store.accounts) { a in
        HStack(spacing: 10) {
          SenderAvatar(name: a.name, size: 34).fixedSize()
          VStack(alignment: .leading, spacing: 4) {
            Text(a.name).font(.system(size: 13, weight: .semibold))
              .lineLimit(1).truncationMode(.middle).help(a.name)
            Text(a.email).font(.system(size: 11)).foregroundStyle(Palette.muted)
              .lineLimit(1).truncationMode(.middle).help(a.email)
          }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
          Spacer()
          if a.isDemo {
            Tag(text: "演示数据").fixedSize()
          } else {
            ActionButton(title: "编辑") {
              account = a
              selectedAccountId = a.id
              editingAccount = true
              password = ""
              do { password = try CredentialService.read("mail-\(a.id)") } catch {
                status = error.localizedDescription
              }
            }
            ActionButton(title: "移除") { removingAccount = a }
          }
        }.padding(18).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
      }
      ActionButton(title: "添加邮箱", icon: "plus", kind: .primary) {
        account = MailAccount()
        password = ""
        selectedAccountId = ""
        editingAccount = true
      }
      if editingAccount {
        SectionCard(title: selectedAccountId.isEmpty ? "添加 IMAP / SMTP 账户" : "编辑账户", icon: "person")
        {
          HStack {
            Text("快速填入服务器：").font(.system(size: 11)).foregroundStyle(Palette.muted)
            ForEach(["QQ", "163", "自定义"], id: \.self) { provider in
              ActionButton(title: provider) {
                if provider == "QQ" {
                  account.imapHost = "imap.qq.com"
                  account.smtpHost = "smtp.qq.com"
                } else if provider == "163" {
                  account.imapHost = "imap.163.com"
                  account.smtpHost = "smtp.163.com"
                } else {
                  account.imapHost = ""
                  account.smtpHost = ""
                }
                account.imapPort = 993
                account.smtpPort = 465
                account.imapTLS = true
                account.smtpTLS = true
              }
            }
          }
          field("账户名称", text: $account.name, prompt: "你的姓名")
          field("邮箱地址", text: $account.email, prompt: "you@example.com")
          field("登录用户名", text: $account.username, prompt: "留空时使用邮箱地址")
          HStack(spacing: SettingsFormLayout.columnGap) {
            SettingsFormLabel(title: "授权码")
            SecureField("", text: $password).settingsTextInput()
              .inputPlaceholder("邮箱应用密码 / 授权码", visible: password.isEmpty).accessibilityLabel("邮箱授权码")
          }
          VStack(spacing: SettingsFormLayout.columnGap) {
            HStack(spacing: SettingsFormLayout.columnGap) {
              Color.clear.frame(width: SettingsFormLayout.labelWidth, height: 1)
                .accessibilityHidden(true)
              Text("服务器地址").frame(maxWidth: .infinity, alignment: .leading)
              Text("端口").frame(width: SettingsFormLayout.portWidth, alignment: .leading)
              Text("加密方式").frame(width: SettingsFormLayout.menuWidth, alignment: .leading)
            }.font(UIType.small).foregroundStyle(Palette.muted)
            serverFields(
              "IMAP", host: $account.imapHost, port: $account.imapPort, tls: $account.imapTLS,
              sslPort: 993, startTLSPort: 143)
            serverFields(
              "SMTP", host: $account.smtpHost, port: $account.smtpPort, tls: $account.smtpTLS,
              sslPort: 465, startTLSPort: 587)
          }
          Text("在下拉框中选择 SSL/TLS 或 STARTTLS。QQ、163 等邮箱需先启用 IMAP/SMTP，并生成客户端授权码。").font(
            .system(size: 11)
          ).foregroundStyle(Palette.muted)
          HStack {
            ActionButton(title: "测试连接", icon: "bolt") { testMail() }.disabled(loading)
            ActionButton(title: "保存账户", kind: .primary) { saveAccount() }.disabled(
              loading || account.email.isEmpty || password.isEmpty)
          }
        }
      }
    }
  }
  private var generalSettings: some View {
    SectionCard(title: "邮箱同步", icon: "arrow.triangle.2.circlepath") {
      WorkflowStepper(title: "自动同步间隔", value: $preferences.syncMinutes, range: 1...60, unit: "分钟")
      Text("应用打开时定期同步，自动逐批补齐全部历史邮件；已下载邮件持续保存，可从主窗口顶部停止本次同步，下次同步会自动继续。").font(.system(size: 12))
        .foregroundStyle(Palette.muted)
      ActionButton(title: "立即同步", icon: "arrow.clockwise", kind: .primary) {
        Task { await store.syncAll() }
      }.disabled(store.busy.contains("sync"))
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
    SectionCard(title: "垃圾邮件与内容安全", icon: "shield") {
      Text("同步时会识别服务商的垃圾邮件文件夹。默认屏蔽远程图片自动加载。AI 分类只修改本机分类标签。第一版暂未提供本机垃圾邮件训练或黑名单规则。").font(
        .system(size: 13)
      ).lineSpacing(7)
      Text("需要管理垃圾邮件时，可在服务商网页邮箱调整规则。").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
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
  private func field(_ title: String, text: Binding<String>, prompt: String = "") -> some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      WorkflowTextInput(label: title, placeholder: prompt, text: text, font: UIType.caption)
    }
  }
  private func serverFields(
    _ name: String, host: Binding<String>, port: Binding<Int>, tls: Binding<Bool>,
    sslPort: Int, startTLSPort: Int
  ) -> some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: name)
      WorkflowTextInput(label: name + " 地址", placeholder: "服务器地址", text: host, font: UIType.caption)
        .frame(maxWidth: .infinity)
      TextField("端口", value: port, format: .number.grouping(.never)).settingsTextInput()
        .frame(width: SettingsFormLayout.portWidth).accessibilityLabel(name + " 端口")
      WorkflowSelection(title: name + " 加密方式", selection: tls,
        options: [(true, "SSL/TLS"), (false, "STARTTLS")]).frame(width: SettingsFormLayout.menuWidth)
    }.onChange(of: tls.wrappedValue) { oldValue, newValue in
      let oldPort = oldValue ? sslPort : startTLSPort
      if port.wrappedValue == oldPort {
        port.wrappedValue = newValue ? sslPort : startTLSPort
      }
    }
  }
  private func save(close: Bool) {
    loading = true
    Task {
      defer { loading = false }
      do {
        if let pendingDataDirectory {
          _ = try LocalDataStorage.validateDestination(
            from: BackendService.shared.dataDirectory, to: pendingDataDirectory)
        }
        if !store.ready {
          try BackendService.shared.scheduleDataDirectory(pendingDataDirectory)
          status = "数据位置设置已保存，请恢复原数据目录后重新启动。"
          if close { dismiss() }
          return
        }
        if let issue = config.validationIssue { throw BackendService.shared.failure(issue) }
        for account in config.credentialAccounts {
          if let key = aiKeys[account], originalAIKeys[account] != key {
            if key.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
              throw BackendService.shared.failure("API Key 不能包含控制字符。")
            }
            try CredentialService.save(key.trimmingCharacters(in: .whitespacesAndNewlines), account: account)
            originalAIKeys[account] = key
          }
        }
        let removedProviders = store.settings.ai.providers.filter { old in !config.providers.contains { $0.id == old.id } }
        try await BackendService.shared.perform(
          "/settings",
          body: ["ai": try jsonObject(config), "preferences": try jsonObject(preferences)])
        try await store.refresh()
        for provider in removedProviders { try CredentialService.save("", account: provider.credentialAccount) }
        try BackendService.shared.scheduleDataDirectory(pendingDataDirectory)
        status = pendingDataDirectory == nil ? "设置已保存" : "设置已保存，重新打开 Boxmail 后迁移本机数据。"
        if close { dismiss() }
      } catch { status = "保存失败：\(error.localizedDescription)" }
    }
  }
  private func testMail() {
    loading = true
    status = "正在测试 IMAP 与 SMTP…"
    Task {
      defer { loading = false }
      do {
        var value = account
        if value.username.isEmpty { value.username = value.email }
        try await BackendService.shared.perform(
          "/accounts/test", body: ["account": try jsonObject(value), "password": password])
        status = "IMAP 与 SMTP 连接成功"
      } catch { status = "连接失败：\(error.localizedDescription)" }
    }
  }
  private func saveAccount() {
    loading = true
    Task {
      defer { loading = false }
      do {
        var value = account
        if value.username.isEmpty { value.username = value.email }
        try CredentialService.save(password, account: "mail-\(value.id)")
        let _: IDResponse = try await BackendService.shared.request(
          "/accounts", method: "POST", body: ["account": try jsonObject(value)])
        try await store.refresh()
        store.credentialIssueAccounts.remove(value.id)
        store.accountId = value.id
        editingAccount = false
        status = "账户已保存，可以开始同步"
      } catch { status = "保存失败：\(error.localizedDescription)" }
    }
  }
  private func removeAccount(_ account: MailAccount) {
    store.action("remove-account") {
      try await BackendService.shared.perform("/accounts/\(account.id)", method: "DELETE")
      try CredentialService.save("", account: "mail-\(account.id)")
    }
  }
}
