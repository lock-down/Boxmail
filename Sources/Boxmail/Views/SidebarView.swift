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
      }.padding(.horizontal, 22).padding(.top, 38).padding(.bottom, 18)
        .accessibilityElement(children: .combine).accessibilityLabel("Boxmail")
      Button {
        store.newDraft()
      } label: {
        HStack(spacing: 9) {
          Image(systemName: "square.and.pencil").font(.system(size: 14))
            .frame(width: 18)
          Text("写邮件").font(.system(size: 13, weight: .semibold))
          Spacer(minLength: 0)
        }.foregroundStyle(Palette.blue).padding(.horizontal, 10).frame(height: 38)
          .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 7))
          .contentShape(RoundedRectangle(cornerRadius: 7))
      }.buttonStyle(ControlFeedback(selected: true)).controlFocus()
        .padding(.horizontal, 12).padding(.bottom, 16)
      OverlayScrollView {
        VStack(spacing: 4) {
          Button {
            showAccounts.toggle()
          } label: {
            HStack(spacing: 8) {
              SenderAvatar(name: store.currentAccount?.sidebarName ?? "Boxmail", size: 30).fixedSize()
              VStack(alignment: .leading, spacing: 3) {
                Text(store.currentAccount?.sidebarName ?? "添加邮箱账号").font(
                  .system(size: 12, weight: .semibold)
                ).lineLimit(1).truncationMode(.middle)
                  .help(store.currentAccount?.sidebarName ?? "添加邮箱账号")
                Text(store.currentAccount?.email ?? "连接你的邮箱").font(.system(size: 11))
                  .foregroundStyle(
                    Palette.muted
                  ).lineLimit(1).truncationMode(.middle)
                  .help(store.currentAccount?.email ?? "连接你的邮箱")
              }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
              Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(
                Palette.muted).frame(width: 12)
            }.padding(.horizontal, 7).frame(height: 58).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback()).controlFocus()
            .popover(isPresented: $showAccounts) {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(store.accounts) { account in
                  Button {
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
                        in: RoundedRectangle(cornerRadius: 7)
                      )
                      .contentShape(Rectangle())
                  }.buttonStyle(ControlFeedback()).controlFocus()
                    .accessibilityAddTraits(account.id == store.accountId ? .isSelected : [])
                }
                Divider()
                Button("添加邮箱账号…") {
                  showAccounts = false
                  store.settingsTab = "账号"
                  store.showSettings = true
                }.buttonStyle(.plain).foregroundStyle(Palette.blue)
              }.padding(12).frame(width: 360)
            }
          sectionTitle("邮箱")
          ForEach([MailDestination.inbox, .starred, .drafts, .sent, .attachments, .trash, .archive, .spam])
          {
            destination in row(destination)
          }
          sectionTitle("智能工具").padding(.top, 7)
          ForEach([MailDestination.summary, .organize]) { destination in
            row(destination)
          }
        }.padding(.horizontal, 12).padding(.bottom, 12)
      }.scrollIndicators(.hidden)
      if store.currentAccount?.isDemo == true {
        HStack {
          Text("演示邮箱").font(.system(size: 11, weight: .medium))
          Spacer()
          Button("添加邮箱") {
            store.settingsTab = "账号"
            store.showSettings = true
          }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(Palette.blue)
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
          Button("检查邮箱凭证") {
            store.settingsTab = "账号"
            store.showSettings = true
          }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.amber)
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
    ).padding(.leading, 10).padding(.top, 10).padding(.bottom, 6)
  }
  private func count(_ destination: MailDestination) -> Int {
    switch destination {
    case .inbox: return store.unreadInboxMessages.count
    case .drafts: return store.drafts.filter { $0.accountId == store.accountId }.count
    case .sent: return store.cachedMessageCount(accountId: store.accountId, folder: "sent")
    case .attachments: return store.accountAttachments.count
    case .summary: return store.summaryOverviewMessages.count
    case .replies:
      return store.drafts.filter { $0.accountId == store.accountId && $0.sourceMessageId != nil }
        .count
    default: return 0
    }
  }
  private func row(_ destination: MailDestination) -> some View {
    let selected = store.destination == destination
    return Button {
      store.navigate(destination)
    } label: {
      HStack(spacing: 9) {
        Image(systemName: destination.icon).font(.system(size: 14, weight: .regular)).frame(width: 18)
          .foregroundStyle(selected ? Palette.blue : Palette.muted)
        Text(destination.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
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
        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 36)
        .contentShape(Rectangle()).background(
          selected ? Palette.blueSoft : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(ControlFeedback(selected: selected)).controlFocus().accessibilityAddTraits(
      selected ? .isSelected : [])
      .animation(UIMotion.selection(reduceMotion), value: selected)
      .animation(UIMotion.selection(reduceMotion), value: count(destination))
  }
}
