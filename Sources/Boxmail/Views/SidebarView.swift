import AppKit
import BoxmailCore
import SwiftUI

struct SidebarView: View {
  private static let brandImage = BoxmailBrand.markURL.flatMap { NSImage(contentsOf: $0) }
  @Bindable var store: MailStore
  @ViewState<Bool> private var showAccounts = false
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
      }.padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 16)
        .accessibilityElement(children: .combine).accessibilityLabel("Boxmail")
      ActionButton(title: "写邮件", icon: "square.and.pencil", color: Palette.blue,
        emphasis: .tinted, size: .form, fillsWidth: true, alignment: .leading) { store.newDraft() }
        .padding(.horizontal, 12).padding(.bottom, 16)
      OverlayScrollView {
        VStack(spacing: 4) {
          Button {
            showAccounts.toggle()
          } label: {
            HStack(spacing: 8) {
              SenderAvatar(name: store.currentAccount?.sidebarName ?? "Boxmail", size: 30).fixedSize()
              VStack(alignment: .leading, spacing: 3) {
                Text(store.scopeTitle).font(
                  .system(size: 12, weight: .semibold)
                ).lineLimit(1).truncationMode(.middle)
                  .help(store.scopeTitle)
                Text(store.unifiedInbox && store.supportsUnifiedScope ? "跨账户收件与处理" : store.currentAccount?.email ?? "连接你的邮箱").font(.system(size: 11))
                  .foregroundStyle(
                    Palette.muted
                  ).lineLimit(1).truncationMode(.middle)
                  .help(store.unifiedInbox && store.supportsUnifiedScope ? "跨账户收件与处理" : store.currentAccount?.email ?? "连接你的邮箱")
              }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
              Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(
                Palette.muted).frame(width: 12)
            }.padding(.horizontal, 8).frame(height: 56).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback()).controlFocus()
            .popover(isPresented: $showAccounts) {
              VStack(alignment: .leading, spacing: 10) {
                ActionButton(title: "所有账户", icon: "tray.full") {
                  store.unifiedInbox = true
                  store.navigate(.inbox)
                  showAccounts = false
                }
                ForEach(store.accounts) { account in
                  Button {
                    store.unifiedInbox = false
                    store.accountId = account.id
                    store.mailAITab = nil
                    store.selectedMessageId = store.filteredMessages.first?.id
                    showAccounts = false
                  } label: {
                    HStack(spacing: 10) {
                      SenderAvatar(name: account.sidebarName, size: 30).fixedSize()
                      VStack(alignment: .leading, spacing: 4) {
                        Text(account.sidebarName).font(.system(size: 13, weight: .medium))
                          .lineLimit(1).truncationMode(.middle).help(account.sidebarName)
                        Text(account.email).font(.system(size: 11)).foregroundStyle(Palette.muted)
                          .lineLimit(1).truncationMode(.middle).help(account.email)
                      }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                      Image(systemName: "checkmark").foregroundStyle(Palette.blue).frame(width: 18)
                        .opacity(account.id == store.accountId ? 1 : 0).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                      .background(
                        account.id == store.accountId ? Palette.blueSoft : .clear,
                        in: RoundedRectangle(
                          cornerRadius: UILayout.navigationRadius, style: .continuous)
                      )
                      .contentShape(Rectangle())
                  }.buttonStyle(ControlFeedback(corner: UILayout.navigationRadius))
                    .controlFocus(corner: UILayout.navigationRadius)
                    .accessibilityAddTraits(account.id == store.accountId ? .isSelected : [])
                }
                Divider()
                ActionButton(title: "添加邮箱账号…", color: Palette.blue) {
                  showAccounts = false
                  store.settingsTab = "账号"
                  store.showSettings = true
                }
              }.padding(12).frame(width: 360)
            }
          sectionTitle("邮箱")
          ForEach([MailDestination.inbox, .followUps, .starred, .drafts, .outbox, .sent, .trash, .archive, .spam, .attachments])
          {
            destination in row(destination)
          }
          if !store.savedSearches.isEmpty { sectionTitle("保存的视图") }
          ForEach(store.savedSearches) { saved in
            Button { store.openSavedSearch(saved) } label: {
              HStack(spacing: 8) {
                Image(systemName: "bookmark").font(.system(size: UILayout.iconSize)).frame(width: 20)
                Text(saved.name).font(UIType.body).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
              }.foregroundStyle(store.activeSavedSearchId == saved.id ? Palette.blue : Palette.muted)
                .padding(.horizontal, 10).frame(height: 32).contentShape(Rectangle())
                .background(store.activeSavedSearchId == saved.id ? Palette.blueSoft : .clear,
                  in: RoundedRectangle(cornerRadius: UILayout.navigationRadius))
            }.buttonStyle(ControlFeedback(selected: store.activeSavedSearchId == saved.id)).controlFocus()
              .help(saved.name).accessibilityAddTraits(store.activeSavedSearchId == saved.id ? .isSelected : [])
          }
          sectionTitle("智能工具")
          ForEach([MailDestination.organize, .rules]) { destination in
            row(destination)
          }
        }.padding(.horizontal, 12).padding(.bottom, 12)
      }.scrollIndicators(.hidden)
      if store.currentAccount?.isDemo == true {
        HStack {
          Text("演示邮箱").font(.system(size: 11, weight: .medium))
          Spacer()
          ActionButton(title: "添加邮箱", color: Palette.blue, size: .compact) {
            store.settingsTab = "账号"
            store.showSettings = true
          }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
      }
      HStack(spacing: 7) {
        Image(
          systemName: !store.credentialIssueAccounts.isEmpty
            ? "exclamationmark.circle"
            : store.pendingMutations > 0 ? "arrow.triangle.2.circlepath" : "checkmark.circle"
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
    } label: {
      HStack(spacing: 8) {
        Image(systemName: destination.icon).font(.system(size: UILayout.iconSize, weight: .regular)).frame(width: 20)
          .foregroundStyle(selected ? Palette.blue : Palette.muted)
        Text(destination == .followUps ? "邮件工作台" : destination.title)
          .font(.system(size: 13, weight: selected ? .semibold : .regular))
        Spacer()
        if destination == .organize, store.latestOrganization?.status == "running" {
          ProgressView().controlSize(.mini)
        }
        if count(destination) > 0 {
          Text(String(count(destination))).font(.system(size: 11, weight: .medium))
            .monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText()).foregroundStyle(
              selected ? Palette.blue : Palette.muted)
        }
      }.foregroundStyle(selected ? Palette.blue : Palette.ink)
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 32)
        .contentShape(Rectangle()).background(
          selected ? Palette.blueSoft : Color.clear,
          in: RoundedRectangle(cornerRadius: UILayout.navigationRadius, style: .continuous))
    }.buttonStyle(ControlFeedback(selected: selected, corner: UILayout.navigationRadius))
      .controlFocus(corner: UILayout.navigationRadius).accessibilityAddTraits(
      selected ? .isSelected : [])
      .animation(UIMotion.selection(reduceMotion), value: selected)
      .animation(UIMotion.selection(reduceMotion), value: count(destination))
  }
}
