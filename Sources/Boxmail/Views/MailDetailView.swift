import AppKit
import BoxmailCore
import SwiftUI

struct MailDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        HStack(spacing: 6) {
          if message.folder == "trash" {
            ActionButton(title: "恢复到收件箱", icon: "arrow.uturn.backward", kind: .primary) {
              store.update(message, ["folder": "inbox"])
            }
          } else {
            ActionButton(title: "回复", icon: "arrowshape.turn.up.left", kind: .primary) {
              store.newDraft(reply: message)
            }
            ActionButton(title: "全部回复", icon: "arrowshape.turn.up.left.2") {
              store.newDraft(reply: message, all: true)
            }
            ActionButton(title: "转发", icon: "arrowshape.turn.up.right") {
              store.newDraft(reply: message, forward: true)
            }
          }
        }
        Divider().frame(height: 18).padding(.horizontal, 2)
        HStack(spacing: 4) {
          IconButton(icon: "archivebox", help: "归档") {
            store.update(message, ["folder": "archive"])
          }
          IconMenu(icon: "tag", help: "分类邮件") {
            ForEach(["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来", "未分类"], id: \.self) { category in
              Button(category) { store.update(message, ["category": category]) }
            }
          }
          IconButton(icon: "trash", help: "移到已删除") { store.update(message, ["folder": "trash"]) }
          IconButton(
            icon: message.starred ? "star.fill" : "star", help: message.starred ? "取消星标" : "添加星标",
            color: message.starred ? Palette.amber : Palette.muted
          ) { store.update(message, ["starred": !message.starred]) }
          IconMenu(icon: "ellipsis", help: "更多邮件操作") {
            Button("复制邮件正文") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.body, forType: .string)
            }
            Button("标记为未读") { store.update(message, ["unread": true]) }
          }
        }
        Spacer(minLength: 0)
      }.padding(.horizontal, 16).frame(height: 52).background(.white)
      Divider()
      MailAIBar(store: store, message: message)
      Divider()
      ScrollViewReader { reader in
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Text(message.subject).font(.system(size: 21, weight: .semibold)).tracking(-0.35)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
            HStack {
              Tag(text: message.category)
              if message.starred { Tag(text: "星标邮件") }
            }
            HStack(alignment: .top, spacing: 11) {
              SenderAvatar(name: message.sender, size: 34)
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(message.sender).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                  Spacer(minLength: 8)
                  Text(displayTime(message.date)).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(Palette.muted).fixedSize()
                }
                Text(message.senderEmail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                  .textSelection(.enabled)
                  .lineLimit(1).truncationMode(.middle)
                RecipientDetailsView(to: message.to, cc: message.cc).id(message.id)
              }
            }
            if let tab = store.mailAITab {
              MailAssistantView(store: store, message: message, tab: tab).id("mail-assistant")
            }
            Text("邮件原文").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
            MailBodyView(message: message, preferences: store.settings.preferences).id(message.id)
            if !message.attachmentIds.isEmpty {
              HStack {
                Label("\(message.attachmentIds.count) 个附件", systemImage: "paperclip").font(
                  .system(size: 12, weight: .semibold))
                Spacer()
                Button("理解本封邮件附件") { store.mailAITab = .attachment }
                  .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
              }.padding(.top, 5)
              LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9) {
                ForEach(message.attachmentIds, id: \.self) { id in
                  if let attachment = store.attachments.first(where: { $0.id == id }) {
                    AttachmentCard(attachment: attachment) { store.previewAttachment = attachment }
                  }
                }
              }
            }
          }.frame(maxWidth: UILayout.reading, alignment: .leading)
            .padding(.horizontal, 26).padding(.vertical, 28).frame(
              maxWidth: .infinity, alignment: .top)
        }.defaultScrollAnchor(.top).id(message.id).background(.white)
          .onChange(of: store.mailAITab) { _, tab in
            if tab != nil { withAnimation { reader.scrollTo("mail-assistant", anchor: .top) } }
          }
      }
    }.background(.white)
  }
}
struct SummaryCard: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let summary: MailSummary
  var embedded = false
  @ViewState<Bool> private var collapsed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles").foregroundStyle(Palette.blue)
        VStack(alignment: .leading, spacing: 3) {
          Text("AI 邮件总结").font(.system(size: 12, weight: .semibold))
          Text(message.accountId == "demo" ? "设计示例摘要" : "已读取正文与可解析附件")
            .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        Spacer(minLength: 8)
        IconButton(icon: "arrow.clockwise", help: "重新生成") {
          store.generate(task: "summary", message: message)
        }
        IconButton(icon: "doc.on.doc", help: "复制总结") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(summary.points.joined(separator: "\n"), forType: .string)
        }
        IconButton(
          icon: collapsed ? "chevron.down" : "chevron.up", help: collapsed ? "展开总结" : "折叠总结"
        ) {
          collapsed.toggle()
        }
      }
      if store.destination == .summary, let error = store.mailAIErrors[message.id] {
        Text(error).font(.system(size: 12)).foregroundStyle(Palette.amber)
      }
      if !collapsed {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(Array(summary.points.enumerated()), id: \.offset) { index, point in
            HStack(alignment: .top, spacing: 10) {
              Text(String(index + 1)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(Palette.blue).frame(width: 20, height: 20)
                .background(Palette.blueSoft, in: Circle())
              Text(point).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true).frame(
                  maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        Divider().overlay(Palette.softBorder)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 24) {
            todos.frame(minWidth: 320, maxWidth: .infinity)
            keyInfo.frame(minWidth: 360, maxWidth: .infinity)
          }
          VStack(alignment: .leading, spacing: 20) {
            todos
            keyInfo
          }
        }
      }
    }.padding(embedded ? 0 : 18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(embedded ? Color.clear : Palette.canvas, in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).stroke(embedded ? .clear : Palette.softBorder))
      .disabled(store.busy.contains("agent"))
  }
  private var todos: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("待办事项").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
      ForEach(summary.todos) { todo in
        Button {
          store.toggleTodo(message: message, todo: todo)
        } label: {
          HStack(spacing: 9) {
            Image(systemName: todo.done ? "checkmark.square.fill" : "square").foregroundStyle(
              Palette.blue)
            Text(todo.title).font(.system(size: 12)).strikethrough(todo.done)
              .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            if !todo.due.isEmpty {
              Text(todo.due).font(.system(size: 11)).foregroundStyle(Palette.amber).lineLimit(2)
            }
          }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 6)).contentShape(
            Rectangle())
        }.buttonStyle(ControlFeedback())
      }
      if summary.todos.isEmpty {
        Text("无明确待办").font(.system(size: 12)).foregroundStyle(Palette.muted)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var keyInfo: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("关键信息").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
      ForEach(summary.keyInfo, id: \.label) { info in
        HStack(alignment: .top, spacing: 12) {
          Text(info.label).foregroundStyle(Palette.muted).frame(width: 116, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
          Text(info.value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 12)).lineSpacing(4)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct AttachmentCard: View {
  let attachment: MailAttachment
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: "doc.text").font(.system(size: 15)).foregroundStyle(
          attachment.name.hasSuffix("pdf") ? .red : Palette.blue
        ).frame(width: 31, height: 31).background(
          Palette.blueSoft, in: RoundedRectangle(cornerRadius: 7))
        VStack(alignment: .leading, spacing: 4) {
          Text(attachment.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            .truncationMode(.middle).help(attachment.name)
          HStack {
            Text(fileSize(attachment.size)).font(.system(size: 9)).foregroundStyle(Palette.muted)
            if !attachment.text.isEmpty {
              Tag(text: attachment.analysis == nil ? "已提取文本" : "AI 已解析", ai: true)
            }
          }
        }
        Spacer(minLength: 0)
      }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(
        RoundedRectangle(cornerRadius: 8).stroke(Palette.border)
      ).contentShape(
        RoundedRectangle(cornerRadius: 8))
    }.buttonStyle(ControlFeedback(corner: 8))
  }
}
