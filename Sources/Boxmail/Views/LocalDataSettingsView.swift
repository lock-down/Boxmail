import AppKit
import BoxmailCore
import SwiftUI

struct LocalDataSettingsView: View {
  @Bindable var store: MailStore
  @Binding var pendingDirectory: URL?
  @ViewState<String?> private var selectionError = nil
  private var backend: BackendService { .shared }

  var body: some View {
    SectionCard(title: "本机数据", icon: "externaldrive") {
      VStack(alignment: .leading, spacing: 8) {
        Text("当前保存位置").font(UIType.small).foregroundStyle(Palette.muted)
        Text(backend.dataDirectory.path).font(UIType.body).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        Tag(text: backend.hasDataDirectoryOverride ? "环境变量指定" :
          backend.dataDirectory.standardizedFileURL == backend.defaultDataDirectory.standardizedFileURL
            ? "默认位置" : "自定义位置")
      }
      Text("邮件正文、附件、草稿、AI 结果与活动记录保存在此目录。授权码与 API Key 保存在系统钥匙串。")
        .font(UIType.caption).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
      WrappingFlowLayout(spacing: 8) {
        ActionButton(title: "打开数据目录", icon: "folder") {
          if !NSWorkspace.shared.open(backend.dataDirectory) {
            selectionError = "目录暂时无法打开，请接入原磁盘并检查文件夹权限。"
          }
        }
        ActionButton(title: "更改位置…", icon: "folder.badge.gearshape", kind: .primary) {
          chooseDirectory()
        }.disabled(backend.hasDataDirectoryOverride || !store.ready)
      }
      if store.ready {
        VStack(alignment: .leading, spacing: 12) {
          Text("全部账户合计：\(store.cachedMessageCount()) 封邮件 · \(store.attachments.count) 个附件文件")
            .font(UIType.caption).foregroundStyle(Palette.ink)
          ForEach(store.accounts) { account in
            VStack(alignment: .leading, spacing: 6) {
              Text("\(account.email)\(account.isDemo ? "（演示）" : "") · \(store.cachedMessageCount(accountId: account.id)) 封")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
              WrappingFlowLayout(spacing: 12) {
                ForEach(["inbox", "sent", "archive", "trash", "drafts", "spam"], id: \.self) { folder in
                  let count = store.cachedMessageCount(accountId: account.id, folder: folder)
                  if count > 0 || ["inbox", "sent", "archive", "trash"].contains(folder) {
                    Text("\(folderTitle(folder)) \(count) 封")
                      .font(UIType.small).foregroundStyle(Palette.muted).fixedSize()
                  }
                }
              }
            }
          }
          Text("列表底部仅统计当前账户的当前文件夹；附件文件包含邮件与写信草稿中的附件。")
            .font(UIType.small).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if backend.hasDataDirectoryOverride {
        Text("本次启动由 BOXMAIL_DATA 指定位置。退出并移除该环境变量后，可在此设置保存目录。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      } else if let pendingDirectory {
        Divider().overlay(Palette.softBorder)
        VStack(alignment: .leading, spacing: 8) {
          Label(isScheduled ? "下次启动时迁移至" : "待应用的新位置", systemImage: "arrow.right")
            .font(UIType.caption).foregroundStyle(Palette.ink)
          Text(pendingDirectory.path).font(UIType.caption).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          Text("应用后，重新打开 Boxmail 将复制现有数据并切换位置。原目录保留，迁移失败时继续使用原位置。")
            .font(UIType.small).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
          ActionButton(title: "取消更改", icon: "xmark") {
            self.pendingDirectory = nil
            selectionError = nil
          }
        }
      } else {
        Text("选择本机或已挂载磁盘中的空文件夹。应用设置后，重新打开 Boxmail 完成迁移。")
          .font(UIType.small).foregroundStyle(Palette.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let selectionError {
        Label(selectionError, systemImage: "exclamationmark.circle")
          .font(UIType.caption).foregroundStyle(Palette.amber)
          .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
    }
  }

  private func folderTitle(_ folder: String) -> String {
    switch folder {
    case "spam": return "垃圾邮件"
    case "drafts": return "邮箱草稿"
    default: return MailDestination(rawValue: folder)?.title ?? folder
    }
  }

  private var isScheduled: Bool {
    pendingDirectory?.standardizedFileURL == backend.pendingDataDirectory?.standardizedFileURL
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.title = "选择本机数据目录"
    panel.message = "选择一个空文件夹保存 Boxmail 数据。重新打开应用时迁移已有邮件和附件，原目录保留。"
    panel.prompt = "选择文件夹"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = pendingDirectory ?? backend.dataDirectory.deletingLastPathComponent()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      pendingDirectory = try LocalDataStorage.validateDestination(from: backend.dataDirectory, to: url)
      selectionError = nil
    } catch { selectionError = error.localizedDescription }
  }
}
