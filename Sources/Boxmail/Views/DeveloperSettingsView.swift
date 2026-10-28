import AppKit
import BoxmailCore
import SwiftUI

struct DeveloperSettingsView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var exporting = false
  @ViewState<String?> private var status = nil
  @ViewState<String?> private var failure = nil

  var body: some View {
    VStack(spacing: 16) {
      SectionCard(title: "运行日志", icon: "doc.text.magnifyingglass") {
        Text("自动记录账户同步阶段、进度、超时与连接错误，以及本机 API 和模型请求错误。日志在后台轮转保存，应用与本机服务各保留最多约 3 MB。")
          .font(UIType.body).fixedSize(horizontal: false, vertical: true)
        Text("复现问题后导出 ZIP，提供给开发者排查。即使同步正在运行或本机服务未连接，也可以导出已保存的日志。")
          .font(UIType.caption).foregroundStyle(Palette.muted).fixedSize(
            horizontal: false, vertical: true)
        ActionButton(
          title: exporting ? "正在导出…" : "导出诊断日志…", icon: "square.and.arrow.up", kind: .primary
        ) {
          export()
        }.disabled(exporting)
        if exporting { ProgressView().controlSize(.small) }
        if let status {
          WorkflowNotice(text: status, icon: "checkmark.circle", color: Palette.success)
        }
        if let failure {
          WorkflowNotice(text: failure, icon: "exclamationmark.circle", color: Palette.amber)
        }
        Text("账户使用匿名标识。导出不含授权码、API Key、邮件正文、主题、附件或请求正文。日志从安装此版本后开始记录。")
          .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(
            horizontal: false, vertical: true)
      }
      SectionCard(title: "当前状态", icon: "stethoscope") {
        Text(
          "本机服务：\(store.ready && store.backend.isRunning ? "已连接" : "未连接")\n同步：\(store.busy.contains("sync") ? store.syncProgressText : "空闲")\n应用版本：\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")"
        )
        .font(UIType.caption).lineSpacing(8).textSelection(.enabled)
        if let issue = store.syncStatusIssue {
          WorkflowNotice(text: issue, icon: "exclamationmark.circle", color: Palette.amber)
        }
      }
    }
  }

  private func export() {
    Task { @MainActor in
      guard let destination = await DiagnosticExportService.chooseDestination() else { return }
      exporting = true
      status = nil
      failure = nil
      defer { exporting = false }
      let backend = store.backend
      let directory = backend.dataDirectory
      do {
        if backend.hasExited { store.markSyncServiceExited() }
        let manifest = try DiagnosticArchive.manifest(
          version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
          build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev",
          connected: store.ready && backend.isRunning, syncing: store.busy.contains("sync"),
          snapshot: store.syncSnapshot
        )
        await backend.diagnostics.flush()
        try await Task.detached(priority: .utility) {
          try DiagnosticArchive.export(from: directory, to: destination, manifest: manifest)
        }.value
        status = "诊断日志已导出：\n\(destination.path)"
      } catch { failure = error.localizedDescription }
    }
  }
}
