import BoxmailCore
import SwiftUI

struct SidebarView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var showAccounts = false
  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 4) {
        Button {
          store.newDraft()
        } label: {
          Label("写邮件", systemImage: "square.and.pencil").font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: 36).foregroundStyle(.white).background(
              Palette.blue, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.bottom, 4)
        Button {
          showAccounts.toggle()
        } label: {
          HStack(spacing: 8) {
            Text(String(store.currentAccount?.name.prefix(1) ?? "B")).font(
              .system(size: 11, weight: .medium)
            ).foregroundStyle(.white).frame(width: 27, height: 27).background(
              Palette.blue, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
              Text(store.currentAccount?.name ?? "添加邮箱账号").font(
                .system(size: 12, weight: .semibold)
              ).lineLimit(1)
              Text(store.currentAccount?.email ?? "连接你的邮箱").font(.system(size: 10)).foregroundStyle(
                Palette.muted
              ).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(
              Palette.muted)
          }.padding(.horizontal, 4).frame(height: 58)
        }.buttonStyle(.plain)
          .popover(isPresented: $showAccounts) {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(store.accounts) { account in
                Button {
                  store.accountId = account.id
                  store.selectedMessageId = store.filteredMessages.first?.id
                  showAccounts = false
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(account.name).font(.system(size: 13, weight: .medium))
                    Text(account.email).font(.system(size: 11)).foregroundStyle(Palette.muted)
                  }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }.buttonStyle(.plain)
              }
              Divider()
              Button("添加邮箱账号…") {
                showAccounts = false
                store.settingsTab = "账号"
                store.showSettings = true
              }.buttonStyle(.plain).foregroundStyle(Palette.blue)
            }.padding(14).frame(width: 280)
          }
        sectionTitle("邮箱")
        ForEach([MailDestination.inbox, .starred, .drafts, .sent, .attachments, .trash, .archive]) {
          destination in row(destination)
        }
        sectionTitle("AI 助手").padding(.top, 7)
        ForEach([MailDestination.summary, .replies, .organize, .analysis]) { destination in
          row(destination)
        }
      }.padding(12)
      Spacer()
      if store.currentAccount?.isDemo == true {
        VStack(alignment: .leading, spacing: 7) {
          Text("当前为演示数据").font(.system(size: 11, weight: .medium))
          Button("添加真实邮箱") {
            store.settingsTab = "账号"
            store.showSettings = true
          }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.blue)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
          Palette.blueSoft, in: RoundedRectangle(cornerRadius: 8)
        ).padding(.horizontal, 12).padding(.bottom, 14)
      }
      HStack(spacing: 7) {
        Image(
          systemName: store.pendingMutations > 0
            ? "arrow.triangle.2.circlepath" : "checkmark.circle"
        ).foregroundStyle(Palette.success)
        Text(
          store.pendingMutations > 0
            ? "\(store.pendingMutations) 项更改待同步"
            : store.currentAccount?.isDemo == true ? "演示模式" : "本机邮件已保存"
        ).font(.system(size: 11)).foregroundStyle(Palette.muted)
        Spacer()
        IconButton(icon: "gearshape", help: "设置") { store.showSettings = true }
      }.padding(.horizontal, 16).padding(.bottom, 13)
    }.background(Palette.sidebar)
  }
  private func sectionTitle(_ text: String) -> some View {
    Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.muted).frame(
      maxWidth: .infinity, alignment: .leading
    ).padding(.leading, 10).padding(.top, 10).padding(.bottom, 6)
  }
  private func count(_ destination: MailDestination) -> Int {
    switch destination {
    case .inbox: return store.accountMessages.filter { $0.folder == "inbox" && $0.unread }.count
    case .drafts: return store.drafts.filter { $0.accountId == store.accountId }.count
    case .attachments: return store.accountAttachments.count
    case .summary: return store.accountMessages.filter { $0.summary != nil }.count
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
        Image(systemName: destination.icon).font(.system(size: 14)).frame(width: 16)
          .foregroundStyle(destination.isAI ? Palette.purple : Palette.muted)
        Text(destination.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
        Spacer()
        if count(destination) > 0 {
          Text(String(count(destination))).font(.system(size: 10)).foregroundStyle(
            destination.isAI ? Palette.purple : Palette.muted)
        }
      }.padding(.horizontal, 10).frame(height: 32).background(
        selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(.plain)
  }
}
