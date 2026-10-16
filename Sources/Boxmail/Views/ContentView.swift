import BoxmailCore
import SwiftUI

struct ContentView: View {
  @Bindable var store: MailStore
  @ViewState<Bool> private var activity = false
  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(Palette.border)
      HStack(spacing: 0) {
        SidebarView(store: store).frame(width: 232)
        Divider()
        if !store.ready {
          VStack(spacing: 14) {
            ProgressView()
            Text("正在启动本机邮件服务…").foregroundStyle(Palette.muted)
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !store.search.isEmpty {
          mailSplit
        } else {
          switch store.destination {
          case .attachments: AttachmentsView(store: store)
          case .organize: OrganizeView(store: store)
          case .summary: SummaryOverviewView(store: store)
          case .drafts: DraftsView(store: store)
          default: mailSplit
          }
        }
      }
    }.foregroundStyle(Palette.ink).background(Palette.canvas).ignoresSafeArea(
      .container, edges: .top
    )
    .sheet(isPresented: $store.showSettings) { SettingsView(store: store) }
    .sheet(item: $store.composer) { draft in ComposerView(store: store, initial: draft) }
    .sheet(item: $store.previewAttachment) { attachment in
      AttachmentPreviewView(store: store, attachmentId: attachment.id)
    }
    .sheet(isPresented: $activity) { ActivityView(store: store) }
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: {
          store.error != nil && !store.showSettings && store.composer == nil
            && store.previewAttachment == nil
        }, set: { if !$0 { store.error = nil } })
    ) {
      Button("确定") { store.error = nil }
    } message: {
      Text(store.error ?? "")
    }
    .alert(
      "Boxmail",
      isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    ) {
      Button("确定") { store.notice = nil }
    } message: {
      Text(store.notice ?? "")
    }
  }
  private var mailSplit: some View {
    HStack(spacing: 0) {
      MailListView(store: store).frame(width: 355)
      Divider()
      if let message = store.selectedMessage,
        store.filteredMessages.contains(where: { $0.id == message.id })
      {
        MailDetailView(store: store, message: message)
      } else {
        EmptyState(
          title: store.filteredMessages.isEmpty ? "这里还没有邮件" : "选择一封邮件",
          subtitle: store.currentAccount?.isDemo == true
            ? "你正在浏览演示数据。添加邮箱后可同步真实邮件。" : "同步邮箱，或从列表中选择邮件查看内容。")
      }
    }
  }
  private var header: some View {
    HStack(spacing: 18) {
      HStack(spacing: 7) {
        Image(systemName: "envelope.fill").font(.system(size: 11)).foregroundStyle(.white).frame(
          width: 19, height: 19
        ).background(Palette.blue, in: RoundedRectangle(cornerRadius: 4))
        Text("Boxmail").font(.system(size: 13, weight: .semibold))
      }.padding(.leading, 78).frame(width: 232, alignment: .leading)
      Spacer(minLength: 10)
      HStack(spacing: 7) {
        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
        TextField("搜索邮件、联系人，或直接搜附件里的内容", text: $store.search).textFieldStyle(.plain).onChange(
          of: store.search
        ) { _, _ in store.selectedMessageId = store.filteredMessages.first?.id }
        if !store.search.isEmpty {
          IconButton(icon: "xmark.circle.fill", help: "清除搜索") { store.search = "" }
        }
        Tag(text: "AI", ai: true)
      }.font(.system(size: 12)).padding(.horizontal, 10).frame(width: 420, height: 30).background(
        .white, in: RoundedRectangle(cornerRadius: 8)
      ).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
      Spacer(minLength: 10)
      HStack(spacing: 9) {
        Button {
          store.settingsTab = "AI 助手"
          store.showSettings = true
        } label: {
          Label(store.settings.ai.enabled ? "AI 助手已开启" : "AI 助手已关闭", systemImage: "sparkles").font(
            .system(size: 11)
          ).foregroundStyle(Palette.purple).padding(.horizontal, 9).padding(.vertical, 4)
            .background(Palette.purpleSoft, in: Capsule())
        }.buttonStyle(.plain)
        if store.busy.contains("sync") {
          ProgressView().controlSize(.small).frame(width: 26)
        } else {
          IconButton(icon: "arrow.triangle.2.circlepath", help: "同步所有账户") {
            Task { await store.syncAll() }
          }
        }
        IconButton(icon: "bell", help: "活动记录") { activity = true }
        IconButton(icon: "gearshape", help: "设置") { store.showSettings = true }
      }.padding(.trailing, 14)
    }.frame(height: 46).background(Palette.chrome)
  }
}

struct ActivityView: View {
  @Bindable var store: MailStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("活动记录").font(.title2.bold())
        Spacer()
        IconButton(icon: "xmark", help: "关闭") { dismiss() }
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(store.events) { event in
            HStack {
              Image(systemName: event.type == "send" ? "paperplane" : "clock").foregroundStyle(
                Palette.purple)
              VStack(alignment: .leading, spacing: 4) {
                Text(event.detail)
                Text(displayTime(event.time)).font(.caption).foregroundStyle(Palette.muted)
              }
              Spacer()
            }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
          }
          if store.events.isEmpty { Text("还没有活动记录").foregroundStyle(Palette.muted) }
        }
      }
    }.padding(24).frame(width: 640, height: 480)
  }
}
