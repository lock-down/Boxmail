import AppKit
import BoxmailCore
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationSettingsView: View {
  @Bindable var store: MailStore
  @Binding var transferring: Bool
  @ViewState<String?> private var status: String?
  @ViewState<String?> private var failure: String?
  @ViewState<PendingConfigurationImport?> private var pending: PendingConfigurationImport?
  @ViewState<Bool> private var importing = false

  var body: some View {
    SectionCard(title: "配置导出与导入", icon: "slider.horizontal.3") {
      VStack(alignment: .leading, spacing: 18) {
        configurationRow(title: "导出配置", detail: "邮箱账号与授权码、AI 配置与密钥、签名及其他偏好", icon: "square.and.arrow.up") {
          WorkflowAction(title: "导出配置…", icon: "square.and.arrow.up", color: Palette.blue) { export() }
        }
        Divider().overlay(Palette.softBorder)
        configurationRow(title: "导入配置", detail: "按邮箱合并账号，应用 AI、签名和其他偏好", icon: "square.and.arrow.down") {
          WorkflowAction(title: "选择配置…", icon: "folder") { chooseConfiguration() }
        }
      }.disabled(transferring || !store.ready || !store.busy.isEmpty || store.composer != nil)
      if !store.ready {
        WorkflowNotice(text: "本机服务尚未启动，配置导入导出暂不可用。关闭设置后，在主窗口重试启动。",
          icon: "info.circle", color: Palette.muted)
      }
      if transferring && pending == nil {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(status ?? "正在处理配置…").font(UIType.small).foregroundStyle(Palette.muted)
        }
      } else if pending == nil, let status {
        WorkflowNotice(text: status, icon: "checkmark.circle", color: Palette.success)
      }
      if pending == nil, let failure {
        WorkflowNotice(text: failure, icon: "exclamationmark.circle", color: Palette.amber)
      }
      Text("JSON 包含授权码与 API Key，未加密，请妥善保管。导出已保存的配置，不含邮件、附件和本机数据位置。")
        .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }.sheet(item: $pending, onDismiss: { transferring = false; failure = nil }) { candidate in
      ConfigurationImportReview(candidate: candidate, importing: importing, failure: failure,
        cancel: { pending = nil }, apply: { apply(candidate) })
        .interactiveDismissDisabled(importing)
    }
  }

  private func configurationRow<Action: View>(title: String, detail: String, icon: String,
    @ViewBuilder action: () -> Action) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.muted).frame(width: 24).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(detail).font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
      action().fixedSize()
    }
  }

  private func export() {
    let panel = NSSavePanel()
    panel.title = "导出 Boxmail 配置"
    panel.allowedContentTypes = [.json]
    let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd"
    panel.nameFieldStringValue = "Boxmail-配置-\(date.string(from: .now)).json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    transferring = true; failure = nil; status = "正在读取本机凭证并导出配置…"
    Task {
      defer { transferring = false }
      do {
        let archive = try await ConfigurationTransferService.export(to: url)
        status = "已导出 \(archive.configuration.accounts.count) 个邮箱账号、\(archive.configuration.settings.ai.providers.count) 个 AI 服务商及签名和偏好设置。\n\(url.path)"
      } catch { status = nil; failure = error.localizedDescription }
    }
  }

  private func chooseConfiguration() {
    let panel = NSOpenPanel()
    panel.title = "选择 Boxmail 配置"
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    transferring = true; failure = nil; status = "正在校验配置…"
    Task {
      do {
        let candidate = try await ConfigurationTransferService.inspect(url)
        status = nil; pending = candidate
      } catch { transferring = false; status = nil; failure = error.localizedDescription }
    }
  }

  private func apply(_ candidate: PendingConfigurationImport) {
    importing = true; failure = nil
    store.busy.insert("configuration-import")
    Task {
      defer { importing = false; store.busy.remove("configuration-import") }
      do {
        let refreshed = try await ConfigurationTransferService.apply(candidate, store: store)
        let added = candidate.plan.accounts.filter { !$0.existing }.count
        let updated = candidate.plan.accounts.count - added
        status = "配置已导入：新增 \(added) 个账号，更新 \(updated) 个账号；AI、签名和其他偏好已应用。"
          + (refreshed ? "" : "\n配置已生效，邮件列表暂未刷新，可稍后重新打开 Boxmail。")
        pending = nil
      } catch { failure = error.localizedDescription }
    }
  }
}

private struct ConfigurationImportReview: View {
  let candidate: PendingConfigurationImport
  let importing: Bool
  let failure: String?
  let cancel, apply: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("导入配置").font(.system(size: 15, weight: .semibold))
        Spacer()
        IconButton(icon: "xmark", help: "取消导入") { cancel() }.disabled(importing)
      }.padding(.horizontal, 22).frame(height: 54).background(Palette.chrome)
      Divider()
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text(candidate.fileName).font(UIType.body).lineLimit(2).textSelection(.enabled)
          VStack(alignment: .leading, spacing: 10) {
            let added = candidate.plan.accounts.filter { !$0.existing }.count
            Text("邮箱账号 · 新增 \(added) 个，更新 \(candidate.plan.accounts.count - added) 个")
              .font(UIType.section)
            ForEach(candidate.plan.accounts) { account in
              HStack(spacing: 10) {
                Image(systemName: "envelope").foregroundStyle(Palette.muted).frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                  Text(account.email).font(UIType.caption).textSelection(.enabled)
                  Text(candidate.archive.credentials.mailPasswords[account.sourceId]?.isEmpty == false ? "包含邮箱授权码" : "未配置授权码")
                    .font(UIType.small).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(account.existing ? "更新" : "新增").font(UIType.small).foregroundStyle(Palette.muted)
              }
            }
            if candidate.plan.accounts.isEmpty {
              Text("文件未包含邮箱账号，将只应用 AI、签名和偏好设置。").font(UIType.small).foregroundStyle(Palette.muted)
            }
          }
          Divider()
          VStack(alignment: .leading, spacing: 7) {
            Text("AI、签名与偏好").font(UIType.section)
            Text("\(candidate.archive.configuration.settings.ai.providers.count) 个 AI 服务商 · 当前：\(candidate.archive.configuration.settings.ai.activeProvider.name)")
              .font(UIType.small).foregroundStyle(Palette.muted)
            Text("模型：\(candidate.archive.configuration.settings.ai.model.isEmpty ? "未选择" : candidate.archive.configuration.settings.ai.model) · 协议：\(candidate.archive.configuration.settings.ai.apiProtocol.title)")
              .font(UIType.small).foregroundStyle(Palette.muted)
            ForEach(candidate.archive.configuration.settings.ai.providers) { provider in
              VStack(alignment: .leading, spacing: 3) {
                Text(provider.name).font(UIType.caption)
                Text(provider.baseURL).font(UIType.small).textSelection(.enabled)
                Text("\(provider.apiProtocol.title) · \(provider.models.count) 个目录模型 · \(hasKey(provider) ? "包含 API 密钥" : "未配置 API 密钥")")
                  .font(UIType.small)
              }.foregroundStyle(Palette.muted).padding(.vertical, 3)
            }
            Text("包括自定义提示词、邮件签名、同步和阅读设置。").font(UIType.small).foregroundStyle(Palette.muted)
          }
          Text("将更新同邮箱账号的参数与授权码，替换 AI、签名和偏好设置。其他账号及已有邮件、附件和草稿保留。")
            .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
          if let failure { WorkflowNotice(text: failure, icon: "exclamationmark.circle", color: Palette.amber) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      }
      Divider()
      HStack(spacing: 12) {
        if importing { ProgressView().controlSize(.small); Text("正在导入…").font(UIType.small).foregroundStyle(Palette.muted) }
        Spacer()
        ActionButton(title: "取消") { cancel() }.keyboardShortcut(.cancelAction).disabled(importing)
        ActionButton(title: "导入配置", icon: "square.and.arrow.down", kind: .primary) { apply() }
          .keyboardShortcut(.defaultAction).disabled(importing)
      }.padding(.horizontal, 22).frame(height: 60).background(Palette.chrome)
    }.frame(width: 560, height: 540).background(Palette.paper).tint(Palette.blue)
  }

  private func hasKey(_ provider: AIProvider) -> Bool {
    (provider.id == "default" ? candidate.archive.credentials.aiKey
      : candidate.archive.credentials.aiProviderKeys?[provider.id] ?? "").isEmpty == false
  }
}
