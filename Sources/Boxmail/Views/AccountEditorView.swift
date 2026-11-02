import AppKit
import BoxmailCore
import SwiftUI

struct AccountEditorView: View {
  @Bindable var store: MailStore
  let isNewAccount: Bool
  let onSaved: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @ViewState<MailAccount> private var account: MailAccount
  @ViewState<String> private var password = ""
  @ViewState<String> private var status = ""
  @ViewState<Bool> private var loading = false

  init(
    store: MailStore, account: MailAccount, isNewAccount: Bool, onSaved: @escaping (String) -> Void
  ) {
    self.store = store
    self.isNewAccount = isNewAccount
    self.onSaved = onSaved
    _account = ViewState(wrappedValue: account)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(isNewAccount ? "添加邮箱" : "编辑邮箱").font(UIType.heading)
        Spacer()
        IconButton(icon: "xmark", help: "取消账号编辑") { dismiss() }.disabled(loading)
      }.padding(.horizontal, 24).frame(height: 54).background(Palette.chrome)
      Divider()
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("保存后立即生效，取消不会更改当前账号。")
            .font(UIType.caption).foregroundStyle(Palette.muted)
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
              .inputPlaceholder("邮箱应用密码 / 授权码", visible: password.isEmpty).accessibilityLabel(
                "邮箱授权码"
              )
              .frame(width: SettingsFormLayout.fieldWidth)
            Spacer(minLength: 0)
          }
          VStack(alignment: .leading, spacing: SettingsFormLayout.columnGap) {
            HStack(spacing: SettingsFormLayout.columnGap) {
              Color.clear.frame(width: SettingsFormLayout.labelWidth, height: 1)
                .accessibilityHidden(true)
              Text("服务器地址").frame(width: SettingsFormLayout.fieldWidth, alignment: .leading)
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
          if !status.isEmpty {
            Text(status).font(UIType.caption).foregroundStyle(Palette.muted)
              .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          }
        }.padding(24)
      }.disabled(loading)
      SettingsActionBar(
        primaryTitle: "保存账户", isWorking: loading,
        primaryDisabled: account.email.isEmpty || password.isEmpty,
        cancel: { dismiss() }, primary: { saveAccount() }
      ) {
        ActionButton(title: "测试连接", icon: "bolt") { testMail() }
          .disabled(loading || account.email.isEmpty || password.isEmpty)
      }
    }.frame(width: 680, height: 530).background(Palette.paper).tint(Palette.blue)
      .interactiveDismissDisabled(loading)
      .task {
        guard !isNewAccount else { return }
        do { password = try CredentialService.read("mail-\(account.id)") } catch {
          status = error.localizedDescription
        }
      }
  }
  private func field(_ title: String, text: Binding<String>, prompt: String = "") -> some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      WorkflowTextInput(label: title, placeholder: prompt, text: text, font: UIType.caption)
        .frame(width: SettingsFormLayout.fieldWidth)
      Spacer(minLength: 0)
    }
  }
  private func serverFields(
    _ name: String, host: Binding<String>, port: Binding<Int>, tls: Binding<Bool>,
    sslPort: Int, startTLSPort: Int
  ) -> some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: name)
      WorkflowTextInput(label: name + " 地址", placeholder: "服务器地址", text: host, font: UIType.caption)
        .frame(width: SettingsFormLayout.fieldWidth)
      TextField("端口", value: port, format: .number.grouping(.never)).settingsTextInput()
        .frame(width: SettingsFormLayout.portWidth).accessibilityLabel(name + " 端口")
      WorkflowSelection(
        title: name + " 加密方式", selection: tls,
        options: [(true, "SSL/TLS"), (false, "STARTTLS")]
      ).frame(width: SettingsFormLayout.menuWidth)
    }.onChange(of: tls.wrappedValue) { oldValue, newValue in
      let oldPort = oldValue ? sslPort : startTLSPort
      if port.wrappedValue == oldPort {
        port.wrappedValue = newValue ? sslPort : startTLSPort
      }
    }
  }
  private func testMail() {
    guard !loading else { return }
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
    guard !loading else { return }
    loading = true
    Task {
      defer { loading = false }
      do {
        var value = account
        if value.username.isEmpty { value.username = value.email }
        let refreshed = try await store.saveAccount(value, password: password)
        onSaved(refreshed ? "账户已保存，可以开始同步" : "账户已保存，邮件列表刷新未完成。请重新加载列表。")
        dismiss()
      } catch { status = "保存失败：\(error.localizedDescription)" }
    }
  }
}
