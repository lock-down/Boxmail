import BoxmailCore
import SwiftUI

struct ActivityView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  @ViewState<Bool> private var showsHistory = false

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        PageHeading(title: "活动记录", subtitle: "最近同步结果与任务记录")
        Spacer()
        IconButton(icon: "xmark", help: "关闭") { dismiss() }
      }
      OverlayScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(store.accounts.filter { !$0.isDemo }) { account in
            accountResult(account)
          }
          ForEach(store.events.filter { $0.type != "sync" }) { event in
            eventRow(event)
          }
          if !store.events.filter({ $0.type == "sync" }).isEmpty {
            DisclosureGroup("同步历史记录", isExpanded: $showsHistory) {
              ForEach(ActivityPresentation.history(store.events.filter { $0.type == "sync" })) { entry in
                if entry.events.count > 1 {
                  DisclosureGroup("相同无变化结果 · \(entry.events.count) 次") {
                    ForEach(entry.events) { event in eventRow(event) }
                  }.font(UIType.caption).padding(.vertical, 8)
                } else if let event = entry.events.first {
                  eventRow(event)
                }
              }
            }.font(UIType.caption)
          }
          if store.events.isEmpty && store.accounts.allSatisfy(\.isDemo) {
            EmptyState(title: "还没有活动记录", subtitle: "同步、AI 任务和发送状态会显示在这里。", icon: "clock")
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
    }.padding(24).frame(width: 640, height: 480)
  }

  private func accountResult(_ account: MailAccount) -> some View {
    let running = store.syncingAccountIds.contains(account.id)
      || store.syncSnapshot?.runningAccounts.contains(account.id) == true
    let result = store.syncSnapshot?.results.first { $0.accountId == account.id }
    let folders = store.syncSnapshot?.folders.filter { $0.accountId == account.id } ?? []
    let unfinished = folders.filter { $0.status == "failed" || $0.hasMore == true || $0.status == "paused" }
    let latest = store.events.first { ActivityPresentation.syncAccount($0, accounts: [account]) != nil }
    return VStack(alignment: .leading, spacing: 8) {
      Label(account.email, systemImage: running ? "arrow.triangle.2.circlepath"
        : result?.status == "failed" || !unfinished.isEmpty ? "exclamationmark.circle" : "clock")
        .font(UIType.caption)
      if running {
        Text("正在同步").font(UIType.small).foregroundStyle(Palette.accent)
      } else if let error = result?.error, !error.isEmpty {
        Text("最近同步未完成：\(error)").font(UIType.small).foregroundStyle(Palette.amber).textSelection(.enabled)
      }
      if !running, !unfinished.isEmpty {
        ForEach(unfinished) { folder in
          Text("\(MailDestination.title(forFolder: folder.folder) ?? folder.folder)：\(folder.lastError ?? "仍有邮件待同步")")
            .font(UIType.small).foregroundStyle(Palette.amber).textSelection(.enabled)
        }
      }
      if let latest {
        Text("最近结果：\(latest.detail.dropFirst(account.email.count + 1))").font(UIType.caption).textSelection(.enabled)
        Text(displayTime(latest.time)).font(UIType.small).foregroundStyle(Palette.muted)
      } else if !running {
        Text("暂无同步结果").font(UIType.small).foregroundStyle(Palette.muted)
      }
      Divider().overlay(Palette.softBorder)
    }.accessibilityElement(children: .contain)
  }

  private func eventRow(_ event: AuditEvent) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: ActivityPresentation.icon(event)).frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(ActivityPresentation.title(event)).font(UIType.caption).textSelection(.enabled)
        Text(displayTime(event.time)).font(UIType.small).foregroundStyle(Palette.muted)
      }
      Spacer(minLength: 0)
    }.foregroundStyle(event.type == "send-warning" ? Palette.amber : Palette.ink)
      .padding(.vertical, 8)
  }
}
