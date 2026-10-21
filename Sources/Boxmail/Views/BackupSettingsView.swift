import AppKit
import BoxmailCore
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var working = false
  @ViewState<String?> private var status = nil
  @ViewState<String?> private var failure = nil
  @ViewState<BackupSummary?> private var inspected = nil
  @ViewState<String> private var source = ""
  @ViewState<Bool> private var confirming = false

  var body: some View {
    SectionCard(title: "完整备份与恢复", icon: "externaldrive.badge.timemachine") {
      VStack(alignment: .leading, spacing: 18) {
        backupRow(title: "创建完整备份", detail: "保存全部账户的邮件、附件、草稿及 AI 结果", icon: "square.and.arrow.up") {
          WorkflowAction(title: "保存备份…", icon: "square.and.arrow.up", color: Palette.blue) { chooseDestination() }
        }
        Divider().overlay(Palette.softBorder)
        backupRow(title: "从备份恢复", detail: "校验 ZIP，并自动保留恢复前的完整数据", icon: "arrow.counterclockwise") {
          WorkflowAction(title: "选择备份…", icon: "folder") { chooseBackup() }
        }
      }.disabled(working || !store.ready || !store.busy.isEmpty || store.composer != nil)
      if working {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(status ?? "正在处理…").font(UIType.small).foregroundStyle(Palette.muted)
        }
      } else if let status {
        WorkflowNotice(text: status, icon: "checkmark.circle", color: Palette.success)
      }
      if let failure { WorkflowNotice(text: failure, icon: "exclamationmark.circle", color: Palette.amber) }
      Text("授权码与 API Key 仍由系统钥匙串管理，不随备份保存。ZIP 未加密，支持压缩后 512 MB、解压后 2 GB 以内。")
        .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }.alert("恢复完整备份？", isPresented: $confirming, presenting: inspected) { summary in
      Button("取消", role: .cancel) { inspected = nil }
      Button("恢复备份", role: .destructive) { restore(summary) }
    } message: { summary in
      Text("备份时间：\(backupTime(summary.createdAt))\n\(summary.counts["account"] ?? 0) 个账户、\(summary.counts["message"] ?? 0) 封邮件、\(summary.counts["draft"] ?? 0) 份草稿、\(summary.counts["attachment"] ?? 0) 个附件。\n\n将替换当前本机数据。恢复前会自动保存完整备份，服务器邮件与钥匙串保持原状。恢复的待同步操作会在下次同步时执行，请先核对。")
    }
  }
  private func backupRow<Action: View>(title: String, detail: String, icon: String, @ViewBuilder action: () -> Action) -> some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Palette.muted).frame(width: 24)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(detail).font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
      action()
    }
  }
  private func backupTime(_ value: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    return date?.formatted(date: .numeric, time: .standard) ?? value
  }
  private func chooseDestination() {
    let panel = NSSavePanel()
    panel.title = "保存 Boxmail 完整备份"
    panel.allowedContentTypes = [.zip]
    let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd"
    panel.nameFieldStringValue = "Boxmail-\(date.string(from: .now)).zip"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    working = true; status = "正在打包并逐文件校验…"; failure = nil
    Task {
      defer { working = false }
      do {
        let summary: BackupSummary = try await BackendService.shared.request("/backups/create", method: "POST",
          body: ["path": url.path], timeout: 600)
        status = "备份已保存：\(summary.path ?? url.path)\n\(summary.counts["message"] ?? 0) 封邮件及 \(summary.counts["attachment"] ?? 0) 个附件均已校验。"
      } catch { status = nil; failure = error.localizedDescription }
    }
  }
  private func chooseBackup() {
    let panel = NSOpenPanel()
    panel.title = "选择 Boxmail 完整备份"
    panel.allowedContentTypes = [.zip]
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    source = url.path; working = true; status = "正在检查备份及附件校验值…"; failure = nil
    Task {
      defer { working = false }
      do {
        inspected = try await BackendService.shared.request("/backups/inspect", method: "POST", body: ["path": source], timeout: 600)
        status = nil; confirming = true
      } catch { status = nil; failure = error.localizedDescription }
    }
  }
  private func restore(_ summary: BackupSummary) {
    working = true; status = "正在保存当前数据并恢复备份…"; failure = nil
    Task {
      defer { working = false; inspected = nil }
      do {
        let result: BackupSummary = try await BackendService.shared.request("/backups/restore", method: "POST",
          body: ["path": source, "sha256": summary.sha256 ?? "", "approved": true], timeout: 600)
        store.detailCache = [:]; store.attachmentCache = [:]; store.conversationBodies = [:]
        store.selectedMessageId = nil; store.conversation = nil; store.conversationAnchor = nil
        store.search = ""; store.pinnedMessageId = nil; store.pinnedQueryKey = ""
        store.previewAttachment = nil
        try await store.refresh()
        store.restoreRevision += 1
        status = "备份已恢复。恢复前的数据保存在：\n\(result.previousBackup ?? "本机数据目录的 backups 文件夹")\n请检查账户和待同步更改后再同步邮箱。"
      } catch { status = nil; failure = error.localizedDescription }
    }
  }
}

struct SearchIndexSettingsView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var working = false
  @ViewState<String?> private var status = nil
  @ViewState<Bool> private var failed = false
  var body: some View {
    SectionCard(title: "本机搜索索引", icon: "magnifyingglass") {
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          if let index = store.searchIndex {
            Text("已索引 \(index.indexed) / \(index.cached) 封邮件").font(UIType.body).monospacedDigit()
            if index.pending > 0 {
              Text("\(index.pending) 项变化将在搜索时自动更新").font(UIType.small).foregroundStyle(Palette.muted)
            }
          }
          Text("检索正文、附件名称与提取文本、AI 结果，仅覆盖本机已缓存内容。")
            .font(UIType.small).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        WorkflowAction(title: working ? "正在重建…" : "重建索引", icon: "arrow.clockwise") { rebuild() }
          .disabled(working || !store.ready || !store.busy.isEmpty)
      }
      if working { ProgressView().controlSize(.small) }
      if let status {
        WorkflowNotice(text: status, icon: failed ? "exclamationmark.circle" : "checkmark.circle", color: failed ? Palette.amber : Palette.success)
      }
    }
  }
  private func rebuild() {
    working = true; status = nil; failed = false
    Task {
      defer { working = false }
      do {
        let result: SearchIndexStatus = try await BackendService.shared.request("/search/rebuild", method: "POST", body: [:], timeout: 600)
        store.searchIndex = result; status = "已重建 \(result.indexed) 封邮件的搜索索引，邮件内容保持不变。"
      } catch { failed = true; status = error.localizedDescription }
    }
  }
}
