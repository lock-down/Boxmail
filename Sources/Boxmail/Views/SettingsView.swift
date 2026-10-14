import AppKit
import BoxmailCore
import SwiftUI

struct SettingsView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<AIConfig> private var config = AIConfig()
  @ViewState<Preferences> private var preferences = Preferences()
  @ViewState<String> private var key = ""
  @ViewState<[String]> private var models: [String] = []
  @ViewState<String> private var promptTab = "summary"
  @ViewState<String> private var status = ""
  @ViewState<MailAccount> private var account = MailAccount()
  @ViewState<String> private var password = ""
  @ViewState<String> private var selectedAccountId = ""
  @ViewState<Bool> private var editingAccount = false
  @ViewState<Bool> private var loading = false
  @ViewState<MailAccount?> private var removingAccount: MailAccount?
  let tabs = ["常用", "账号", "写邮件", "阅读邮件", "反垃圾", "高级", "AI 助手"]
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("设置").font(.system(size: 15, weight: .semibold))
        Spacer()
        IconButton(icon: "xmark", help: "关闭设置") { dismiss() }
      }.padding(.horizontal, 18).frame(height: 50)
      Divider()
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(tabs, id: \.self) { tab in
            Button {
              store.settingsTab = tab
            } label: {
              HStack(spacing: 11) {
                Image(systemName: icon(tab)).frame(width: 17)
                Text(tab)
                Spacer()
              }.font(.system(size: 12, weight: store.settingsTab == tab ? .semibold : .regular))
                .foregroundStyle(store.settingsTab == tab ? Palette.purple : Palette.ink).padding(
                  .horizontal, 10
                ).frame(height: 34).background(
                  store.settingsTab == tab ? Palette.purpleSoft : .clear,
                  in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
          }
          Spacer()
          Text("Boxmail · 原生桌面客户端").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(14).frame(width: 196).background(Palette.canvas)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Text(store.settingsTab).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
              }
              Spacer()
              if store.settingsTab == "AI 助手" {
                Toggle("启用 AI 助手", isOn: $config.enabled).toggleStyle(.switch).font(
                  .system(size: 12))
              }
            }
            switch store.settingsTab {
            case "AI 助手": aiSettings
            case "账号": accountSettings
            case "常用": generalSettings
            case "写邮件": composeSettings
            case "阅读邮件": readSettings
            case "反垃圾": spamSettings
            default: advancedSettings
            }
            if !status.isEmpty {
              Text(status).font(.system(size: 12)).foregroundStyle(
                status.contains("失败") ? .red : Palette.success
              ).textSelection(.enabled)
            }
          }.padding(22)
        }
      }
      Divider()
      HStack {
        if loading { ProgressView().controlSize(.small) }
        Spacer()
        ActionButton(title: "取消") { dismiss() }
        ActionButton(title: "应用") { save(close: false) }
        ActionButton(title: "确定", kind: .primary) { save(close: true) }
      }.padding(.horizontal, 18).frame(height: 54)
    }.frame(width: 1000, height: 750).background(.white)
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
        Text("将移除账户的本机邮件、草稿和钥匙串凭证，服务器邮件会保留。")
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
        do { key = try KeychainService.read("ai-key") } catch {
          status = error.localizedDescription
        }
      }
  }
  private var subtitle: String {
    switch store.settingsTab {
    case "AI 助手": return "配置模型接口与默认提示词，为邮件总结、回复、整理和附件解析提供能力"
    case "账号": return "使用邮箱授权码连接 IMAP 和 SMTP，凭证保存在 macOS 钥匙串"
    case "常用": return "设置邮箱同步与桌面使用偏好"
    case "写邮件": return "配置默认签名和草稿行为"
    case "阅读邮件": return "调整阅读字号与已读行为"
    case "反垃圾": return "同步邮箱服务商的垃圾邮件分类"
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
    default: return "sparkles"
    }
  }
  private var aiSettings: some View {
    VStack(spacing: 16) {
      SectionCard(title: "云端 / 本地 AI 模型", icon: "cloud") {
        HStack {
          Tag(text: "DeepSeek · Responses API", ai: true)
          Spacer()
        }
        field("API 地址", text: $config.baseURL, prompt: "https://api.deepseek.com")
        HStack {
          Text("API Key").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
            width: 76, alignment: .trailing)
          SecureField("密钥保存在系统钥匙串", text: $key).textFieldStyle(.roundedBorder)
          ActionButton(title: "测试连接", icon: "bolt", kind: .softAI) { testAI() }.disabled(
            loading || config.model.isEmpty)
        }
        HStack {
          field("默认模型", text: $config.model, prompt: "deepseek-flash")
          Menu {
            ForEach(models, id: \.self) { model in Button(model) { config.model = model } }
          } label: {
            Image(systemName: "chevron.down")
          }.menuStyle(.borderlessButton).disabled(models.isEmpty)
          ActionButton(title: "刷新列表", icon: "arrow.clockwise") { refreshModels() }.disabled(loading)
        }
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Text("思考等级（effort）").font(.system(size: 10)).foregroundStyle(Palette.muted)
            Picker("思考等级", selection: $config.effort) {
              Text("Low").tag("low")
              Text("High").tag("high")
              Text("Max").tag("max")
            }.pickerStyle(.segmented).labelsHidden()
          }.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 8) {
            Text("请求超时（秒）").font(.system(size: 10)).foregroundStyle(Palette.muted)
            TextField("120", value: $config.timeout, format: .number).textFieldStyle(.roundedBorder)
          }.frame(width: 150)
        }
        Text("超时可设为 10 至 600 秒。图片和 PDF 理解请使用支持视觉输入的模型，如 deepseek-flash。")
          .font(.system(size: 10)).foregroundStyle(Palette.muted)
      }
      SectionCard(title: "系统默认提示词", icon: "curlybraces") {
        HStack(spacing: 6) {
          ForEach(
            [
              ("summary", "邮件总结"), ("reply", "自动回复"), ("classify", "智能整理"), ("attachment", "附件解析"),
              ("compose", "AI 写信"),
              ("translate", "邮件翻译"),
            ], id: \.0
          ) { item in
            Button {
              promptTab = item.0
            } label: {
              Text(item.1).font(.system(size: 11)).padding(.horizontal, 9).padding(.vertical, 6)
                .foregroundStyle(promptTab == item.0 ? Palette.purple : Palette.muted).background(
                  promptTab == item.0 ? Palette.purpleSoft : Palette.canvas, in: Capsule())
            }.buttonStyle(.plain)
          }
        }
        TextEditor(
          text: Binding(
            get: { config.prompts[promptTab] ?? AIPromptDefaults.values[promptTab] ?? "" },
            set: { config.prompts[promptTab] = $0 })
        ).font(.system(size: 12)).frame(height: 140).padding(9).scrollContentBackground(.hidden)
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
        Text("已预设每类任务的提示词，可自定义语气和分析要求。清空后保存会恢复默认。邮件内容、图片和文档内容会发送至你配置的 AI 服务。").font(
          .system(size: 10)
        )
        .foregroundStyle(Palette.muted)
        HStack {
          Spacer()
          Button("恢复当前默认") { config.prompts[promptTab] = AIPromptDefaults.values[promptTab] }
            .buttonStyle(.plain).font(
              .system(size: 11)
            ).foregroundStyle(Palette.muted)
        }
      }
    }
  }
  private var accountSettings: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(store.accounts) { a in
        HStack(spacing: 10) {
          Image(systemName: "envelope").foregroundStyle(Palette.blue)
          VStack(alignment: .leading, spacing: 4) {
            Text(a.name).font(.system(size: 13, weight: .semibold))
            Text(a.email).font(.system(size: 11)).foregroundStyle(Palette.muted)
          }
          Spacer()
          if a.isDemo {
            Tag(text: "演示数据")
          } else {
            ActionButton(title: "编辑") {
              account = a
              selectedAccountId = a.id
              editingAccount = true
              do { password = try KeychainService.read("mail-\(a.id)") } catch {
                status = error.localizedDescription
              }
            }
            ActionButton(title: "移除") { removingAccount = a }
          }
        }.padding(14).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
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
          HStack {
            Text("授权码").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
              width: 76, alignment: .trailing)
            SecureField("邮箱应用密码 / 授权码", text: $password).textFieldStyle(.roundedBorder)
          }
          serverFields(
            "IMAP", host: $account.imapHost, port: $account.imapPort, tls: $account.imapTLS)
          serverFields(
            "SMTP", host: $account.smtpHost, port: $account.smtpPort, tls: $account.smtpTLS)
          Text("QQ、163 等邮箱需先在网页邮箱启用 IMAP/SMTP，并生成客户端授权码。非直连 TLS 端口会强制使用 STARTTLS。").font(
            .system(size: 10)
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
      Stepper("自动同步间隔：\(preferences.syncMinutes) 分钟", value: $preferences.syncMinutes, in: 1...60)
        .font(.system(size: 13))
      Text("应用打开时定期同步；每次读取各邮箱文件夹最近 200 封邮件，正文与附件保存在本机。更多历史邮件的分页同步将在后续版本加入。").font(.system(size: 12))
        .foregroundStyle(Palette.muted)
      ActionButton(title: "立即同步", icon: "arrow.clockwise", kind: .primary) {
        Task { await store.syncAll() }
      }
    }
  }
  private var composeSettings: some View {
    SectionCard(title: "邮件签名", icon: "signature") {
      TextEditor(text: $preferences.signature).font(.system(size: 13)).frame(height: 190).padding(
        10
      ).scrollContentBackground(.hidden).background(
        Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
      Text("新邮件会自动附上签名。草稿在停止输入后自动保存到本机；发送前始终需要确认。").font(.system(size: 12)).foregroundStyle(
        Palette.muted)
    }
  }
  private var readSettings: some View {
    SectionCard(title: "阅读行为", icon: "envelope.open") {
      Toggle("打开邮件时标记为已读", isOn: $preferences.markRead).font(.system(size: 13))
      Stepper("正文字号：\(preferences.fontSize) pt", value: $preferences.fontSize, in: 12...24).font(
        .system(size: 13))
      Text("正文采用文本阅读视图，不加载远程图片或执行邮件中的脚本。已读和星标更改会在下次同步时提交至服务器。").font(.system(size: 12))
        .foregroundStyle(Palette.muted)
    }
  }
  private var spamSettings: some View {
    SectionCard(title: "垃圾邮件与内容安全", icon: "shield") {
      Text("同步时会识别服务商的垃圾邮件文件夹。正文以纯文本呈现，外部跟踪图片不会加载。AI 分类只修改本机分类标签。第一版暂未提供本机垃圾邮件训练或黑名单规则。").font(
        .system(size: 13)
      ).lineSpacing(7)
      Text("需要管理垃圾邮件时，可在服务商网页邮箱调整规则。").font(.system(size: 12)).foregroundStyle(Palette.muted)
    }
  }
  private var advancedSettings: some View {
    VStack(spacing: 16) {
      SectionCard(title: "本机数据", icon: "externaldrive") {
        Text(BackendService.shared.dataDirectory.path).font(.system(size: 12)).textSelection(
          .enabled)
        Text("邮件正文、附件、草稿、AI 结果与活动记录存于 SQLite 和本机附件目录。授权码与 API Key 保存在系统钥匙串。").font(
          .system(size: 12)
        ).foregroundStyle(Palette.muted)
        HStack {
          ActionButton(title: "打开数据目录", icon: "folder") {
            NSWorkspace.shared.open(BackendService.shared.dataDirectory)
          }
          Text("\(store.messages.count) 封邮件 · \(store.attachments.count) 个附件").font(
            .system(size: 11)
          ).foregroundStyle(Palette.muted)
        }
      }
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
    HStack {
      Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
        width: 76, alignment: .trailing)
      TextField(prompt, text: text).textFieldStyle(.roundedBorder).font(.system(size: 12))
    }
  }
  private func serverFields(
    _ name: String, host: Binding<String>, port: Binding<Int>, tls: Binding<Bool>
  ) -> some View {
    HStack {
      field(name + " 地址", text: host)
      TextField("端口", value: port, format: .number).textFieldStyle(.roundedBorder).frame(width: 65)
      Toggle("TLS", isOn: tls).font(.system(size: 11)).frame(width: 68)
    }
  }
  private func save(close: Bool) {
    loading = true
    Task {
      defer { loading = false }
      do {
        try KeychainService.save(key, account: "ai-key")
        try await BackendService.shared.perform(
          "/settings",
          body: ["ai": try jsonObject(config), "preferences": try jsonObject(preferences)])
        try await store.refresh()
        status = "设置已保存"
        if close { dismiss() }
      } catch { status = "保存失败：\(error.localizedDescription)" }
    }
  }
  private func testAI() {
    loading = true
    status = "正在测试…"
    Task {
      defer { loading = false }
      do {
        let _: EmptyResponse = try await BackendService.shared.request(
          "/ai/test", method: "POST", body: ["config": try jsonObject(config), "apiKey": key],
          timeout: TimeInterval(max(10, min(600, config.timeout)) + 30))
        status = "AI 服务连接成功"
      } catch { status = "连接失败：\(error.localizedDescription)" }
    }
  }
  private func refreshModels() {
    loading = true
    Task {
      defer { loading = false }
      do {
        let result: ModelsResponse = try await BackendService.shared.request(
          "/ai/models", method: "POST", body: ["config": try jsonObject(config), "apiKey": key])
        models = result.models
        status = "已读取 \(models.count) 个模型"
      } catch { status = "获取失败：\(error.localizedDescription)" }
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
        try KeychainService.save(password, account: "mail-\(value.id)")
        let _: IDResponse = try await BackendService.shared.request(
          "/accounts", method: "POST", body: ["account": try jsonObject(value)])
        try await store.refresh()
        store.accountId = value.id
        editingAccount = false
        status = "账户已保存，可以开始同步"
      } catch { status = "保存失败：\(error.localizedDescription)" }
    }
  }
  private func removeAccount(_ account: MailAccount) {
    store.action("remove-account") {
      try await BackendService.shared.perform("/accounts/\(account.id)", method: "DELETE")
      try KeychainService.save("", account: "mail-\(account.id)")
    }
  }
}
