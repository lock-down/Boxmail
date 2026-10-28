import BoxmailCore
import SwiftUI

struct MailListDisplayMenu: View {
  @Bindable var store: MailStore
  private var showsDrafts: Bool { store.pageMessages.first?.draftId != nil }
  var body: some View {
    Menu {
      Picker("显示方式", selection: Binding(get: { store.groupMailBySender },
        set: { store.changeSenderGrouping($0) })) {
        Text("按发件人聚合").tag(true)
        Text("逐封显示").tag(false)
      }.pickerStyle(.inline)
    } label: {
      HStack(spacing: 4) {
        Text(store.groupMailBySender && !showsDrafts ? "发件人" : "逐封").font(UIType.small)
        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
      }.foregroundStyle(Palette.muted).padding(.horizontal, 6).frame(height: 28)
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
      .disabled(showsDrafts || store.mailActionInProgress)
      .help(showsDrafts ? "草稿搜索逐封显示" : "按发件人聚合，或逐封显示；均按最新时间排列")
      .accessibilityLabel("邮件列表显示方式：\(store.groupMailBySender && !showsDrafts ? "发件人聚合" : "逐封显示")")
  }
}

struct MailSenderGroupFooter: View {
  @Bindable var store: MailStore
  let group: MailSenderGroup
  var body: some View {
    if store.senderGroupLoading.contains(group.id) || store.senderGroupErrors[group.id] != nil
      || store.senderGroupNextOffsets[group.id] != nil {
      HStack(spacing: 8) {
        if store.senderGroupLoading.contains(group.id) {
          ProgressView().controlSize(.mini)
          Text("正在加载较早邮件…").font(UIType.small).foregroundStyle(Palette.muted)
        } else if let error = store.senderGroupErrors[group.id] {
          Text("较早邮件加载失败").font(UIType.small).foregroundStyle(Palette.amber).help(error)
          Button("重试") {
            Task { await store.loadSenderGroup(group.id, reset: store.senderGroupNextOffsets[group.id] == nil) }
          }.buttonStyle(.plain).font(UIType.small).foregroundStyle(Palette.blue)
        } else {
          Button("显示更早邮件") { Task { await store.loadSenderGroup(group.id, reset: false) } }
            .buttonStyle(.plain).font(UIType.small).foregroundStyle(Palette.blue)
        }
        Spacer(minLength: 0)
        Text("\(store.senderLoadedCount(group))/\(group.count)").font(UIType.small).monospacedDigit()
          .foregroundStyle(Palette.muted)
      }.padding(.leading, 40).padding(.trailing, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity).background(Palette.canvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
    }
  }
}
