import AppKit
import BoxmailCore
import SwiftUI

struct SidebarView: View {
  private static let brandImage = BoxmailBrand.markURL.flatMap { NSImage(contentsOf: $0) }
  @Bindable var store: MailStore
  var closeDrawer: (() -> Void)? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Group {
          if let image = Self.brandImage {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
              .scaleEffect(1 / 0.9)
              .clipShape(RoundedRectangle(cornerRadius: 7, style: .circular))
          }
        }.frame(width: 28, height: 28).accessibilityHidden(true)
        Text("Boxmail").font(.system(size: 14, weight: .semibold))
        Spacer(minLength: 0)
        if let closeDrawer {
          IconButton(icon: .closeLine, help: "关闭邮箱导航", size: 28, action: closeDrawer)
            .keyboardShortcut(.cancelAction)
        }
      }.padding(.horizontal, 16).padding(.top, closeDrawer == nil ? 36 : 32).padding(.bottom, 14)
      ActionButton(title: "写邮件", icon: .editBoxLine,
        emphasis: .primary, size: .form, fillsWidth: true, alignment: .leading) {
          store.newDraft()
          closeDrawer?()
        }.padding(.horizontal, 12).padding(.bottom, 12)
      OverlayScrollView(persistentIndicators: true) {
        VStack(spacing: 4) {
          accountMenu
          sectionTitle("邮箱")
          ForEach([MailDestination.inbox, .followUps, .starred, .drafts, .outbox, .sent, .trash, .archive, .spam, .attachments])
          {
            destination in row(destination)
          }
          if !store.savedSearches.isEmpty { sectionTitle("保存的视图") }
          ForEach(store.savedSearches) { saved in
            Button {
              store.openSavedSearch(saved)
              closeDrawer?()
            } label: {
              HStack(spacing: 8) {
                RemixIcon(.bookmarkLine).frame(width: 20)
                Text(saved.name).font(UIType.body).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
              }.foregroundStyle(store.activeSavedSearchId == saved.id ? Palette.ink : Palette.muted)
                .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                .background(store.activeSavedSearchId == saved.id ? Palette.selected : .clear,
                  in: RoundedRectangle(cornerRadius: UILayout.navigationRadius))
            }.buttonStyle(ControlFeedback(corner: UILayout.navigationRadius))
              .controlFocus(corner: UILayout.navigationRadius)
              .cossTooltip(saved.name).accessibilityAddTraits(store.activeSavedSearchId == saved.id ? .isSelected : [])
          }
          sectionTitle("智能工具")
          ForEach([MailDestination.organize, .rules]) { destination in
            row(destination)
          }
        }.padding(.horizontal, 12).padding(.bottom, 12)
      }.accessibilityLabel("邮箱导航")
      if store.currentAccount?.isDemo == true {
        HStack {
          Text("演示邮箱").font(.system(size: 11, weight: .medium))
          Spacer()
          ActionButton(title: "添加邮箱", color: Palette.accent, size: .compact) {
            store.settingsTab = "账号"
            store.showSettings = true
          }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
      }
      HStack(spacing: 7) {
        RemixIcon(
          !store.credentialIssueAccounts.isEmpty
            ? .errorWarningLine
            : store.pendingMutations > 0 ? .loopRightLine : .checkboxCircleLine
        ).foregroundStyle(
          store.credentialIssueAccounts.isEmpty ? Palette.success : Palette.amber)
        if !store.credentialIssueAccounts.isEmpty {
          ActionButton(title: "检查邮箱凭证", color: Palette.amber, size: .compact) {
            store.settingsTab = "账号"
            store.showSettings = true
          }
        } else {
          Text(
            store.pendingMutations > 0
              ? "\(store.pendingMutations) 项更改待同步"
              : store.currentAccount?.isDemo == true ? "演示模式" : "本机邮件已保存"
          ).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        Spacer()
      }.padding(.horizontal, 16).padding(.vertical, 16)
    }.background(Palette.sidebar)
  }
  private var accountMenu: some View {
    let unified = store.unifiedInbox && store.supportsUnifiedScope
    let details = unified ? "跨账户收件与处理" : store.currentAccount?.email ?? "连接你的邮箱"
    return CossMenu(title: "选择邮箱账户", value: store.scopeTitle, width: 280,
      emphasis: .secondary, prefersSelection: true) {
      CossMenuItem.command("所有账户", icon: .inbox2Line, mark: .choice(unified)) {
        store.unifiedInbox = true
        store.navigate(.inbox)
        closeDrawer?()
      }
      for account in store.accounts {
        CossMenuItem.command(account.sidebarName, subtitle: account.email, icon: .accountCircleLine,
          mark: .choice(!unified && account.id == store.accountId)) {
          store.unifiedInbox = false
          store.accountId = account.id
          store.mailAITab = nil
          store.selectedMessageId = store.filteredMessages.first?.id
          closeDrawer?()
        }
      }
      CossMenuItem.divider
      CossMenuItem.command("添加邮箱账号…", icon: .addLine) {
        store.settingsTab = "账号"
        store.showSettings = true
      }
    } trigger: {
      HStack(spacing: 8) {
        SenderAvatar(name: store.currentAccount?.sidebarName ?? "Boxmail", size: 30)
        VStack(alignment: .leading, spacing: 3) {
          Text(store.scopeTitle).font(.system(size: 12, weight: .semibold))
          Text(details).font(UIType.small).foregroundStyle(Palette.muted)
        }.lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
        RemixIcon(.arrowDownSLine, size: 9).foregroundStyle(Palette.muted)
      }.padding(.horizontal, 8).frame(height: 48)
    }.cossTooltip(details)
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted).frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(.leading, 10).padding(.top, 16).padding(.bottom, 4)
  }
  private func count(_ destination: MailDestination) -> Int {
    switch destination {
    case .inbox: return store.unreadInboxMessages.count
    case .drafts: return store.drafts.filter { $0.accountId == store.accountId }.count
    case .sent: return store.cachedMessageCount(accountId: store.unifiedInbox && store.supportsUnifiedScope ? nil : store.accountId, folder: "sent")
    case .attachments: return store.accountAttachments.count
    default: return 0
    }
  }
  private func row(_ destination: MailDestination) -> some View {
    let selected = store.search.isEmpty && (store.destination == destination
      || destination == .followUps && store.destination == .summary)
    return Button {
      store.navigate(destination)
      closeDrawer?()
    } label: {
      HStack(spacing: 8) {
        RemixIcon(destination.icon).frame(width: 20)
          .foregroundStyle(selected ? Palette.ink : Palette.muted)
        Text(destination == .followUps ? "邮件工作台" : destination.title)
          .font(.system(size: 13, weight: selected ? .semibold : .regular))
        Spacer()
        if destination == .organize, store.latestOrganization?.status == "running" {
          CossSpinner(size: 12)
        }
        if count(destination) > 0 {
          Text(String(count(destination))).font(.system(size: 11, weight: .medium))
            .monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText()).foregroundStyle(
              selected ? Palette.ink : Palette.muted)
        }
      }.foregroundStyle(Palette.ink)
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 32)
        .contentShape(Rectangle()).background(
          selected ? Palette.selected : Color.clear,
          in: RoundedRectangle(cornerRadius: UILayout.navigationRadius, style: .continuous))
    }.buttonStyle(ControlFeedback(corner: UILayout.navigationRadius))
      .controlFocus(corner: UILayout.navigationRadius).accessibilityAddTraits(
      selected ? .isSelected : [])
      .animation(UIMotion.selection(reduceMotion), value: selected)
      .animation(UIMotion.selection(reduceMotion), value: count(destination))
  }
}
