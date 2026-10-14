import AppKit
import BoxmailCore
import SwiftUI

struct MailDetailView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  var body: some View {
    VStack(spacing: 0) {
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
        IconButton(icon: "archivebox", help: "归档") { store.update(message, ["folder": "archive"]) }
        Menu {
          ForEach(["工作项目", "订阅资讯", "账单票据", "社交通知", "个人往来", "未分类"], id: \.self) { category in
            Button(category) { store.update(message, ["category": category]) }
          }
        } label: {
          Image(systemName: "tag").foregroundStyle(Palette.muted)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
        IconButton(icon: "trash", help: "移到已删除") { store.update(message, ["folder": "trash"]) }
        Spacer(minLength: 5)
        if store.busy.contains("agent") { ProgressView().controlSize(.small) }
        ActionButton(title: "AI 总结", icon: "sparkles", kind: .softAI) {
          store.generate(task: "summary", message: message)
        }.disabled(store.busy.contains("agent"))
        IconButton(
          icon: message.starred ? "star.fill" : "star", help: message.starred ? "取消星标" : "添加星标",
          color: message.starred ? Palette.amber : Palette.muted
        ) { store.update(message, ["starred": !message.starred]) }
        Menu {
          Button("复制邮件正文") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.body, forType: .string)
          }
          Button("标记为未读") { store.update(message, ["unread": true]) }
          Button("翻译全文") { store.generate(task: "translate", message: message) }
        } label: {
          Image(systemName: "ellipsis").foregroundStyle(Palette.muted)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
      }.padding(.horizontal, 18).frame(height: 47).background(.white)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text(message.subject).font(.system(size: 21, weight: .bold)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
          HStack {
            Tag(text: message.category)
            if message.starred { Tag(text: "星标邮件") }
          }
          HStack(spacing: 10) {
            Text(String(message.sender.prefix(1))).font(.system(size: 17)).foregroundStyle(.white)
              .frame(width: 36, height: 36).background(Palette.blue, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(message.sender).font(.system(size: 13, weight: .medium))
                Text(message.senderEmail).font(.system(size: 11)).foregroundStyle(Palette.muted)
              }
              Text("发送至 \(message.to)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                .lineLimit(2)
            }
            Spacer()
            Text(displayTime(message.date)).font(.system(size: 11)).foregroundStyle(Palette.muted)
          }
          if let summary = message.summary {
            SummaryCard(store: store, message: message, summary: summary)
          }
          Text("邮件原文").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
          MailBodyView(message: message, preferences: store.settings.preferences).id(message.id)
          if !message.attachmentIds.isEmpty {
            HStack {
              Label("\(message.attachmentIds.count) 个附件", systemImage: "paperclip").font(
                .system(size: 12, weight: .semibold))
              Text("可解析附件内容并用于搜索").font(.system(size: 10)).foregroundStyle(Palette.purple)
            }.padding(.top, 5)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9) {
              ForEach(message.attachmentIds, id: \.self) { id in
                if let attachment = store.attachments.first(where: { $0.id == id }) {
                  AttachmentCard(attachment: attachment) { store.previewAttachment = attachment }
                }
              }
            }
          }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
      }.defaultScrollAnchor(.top).id(message.id).background(.white)
    }.background(.white)
  }
}
struct SummaryCard: View {
  @Bindable var store: MailStore
  let message: MailMessage
  let summary: MailSummary
  @ViewState<Bool> private var collapsed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack {
        Image(systemName: "sparkles").foregroundStyle(.white).frame(width: 23, height: 23)
          .background(Palette.purple, in: RoundedRectangle(cornerRadius: 5))
        Text("AI 邮件总结").font(.system(size: 13, weight: .semibold))
        Text(message.accountId == "demo" ? "设计示例摘要" : "已读取正文与可解析附件").font(.system(size: 10))
          .foregroundStyle(Palette.muted)
        Spacer()
        IconButton(icon: "arrow.clockwise", help: "重新生成", color: Palette.purple) {
          store.generate(task: "summary", message: message)
        }
        IconButton(icon: "doc.on.doc", help: "复制总结", color: Palette.purple) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(summary.points.joined(separator: "\n"), forType: .string)
        }
        IconButton(
          icon: collapsed ? "chevron.down" : "chevron.up", help: "折叠总结", color: Palette.purple
        ) { collapsed.toggle() }
      }.foregroundStyle(Palette.purple)
      if !collapsed {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(summary.points.enumerated()), id: \.offset) { index, point in
            HStack(alignment: .top, spacing: 9) {
              Text(String(index + 1)).font(.system(size: 10)).foregroundStyle(Palette.purple).frame(
                width: 18, height: 18
              ).background(.white, in: Circle())
              Text(point).font(.system(size: 12)).lineSpacing(3).fixedSize(
                horizontal: false, vertical: true)
            }
          }
        }
        Divider().overlay(Palette.purple.opacity(0.15))
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("AI 提取的待办").font(.system(size: 10)).foregroundStyle(Palette.purple)
            ForEach(summary.todos) { todo in
              Button {
                store.toggleTodo(message: message, todo: todo)
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: todo.done ? "checkmark.square.fill" : "square").foregroundStyle(
                    Palette.purple)
                  Text(todo.title).font(.system(size: 11)).strikethrough(todo.done).frame(
                    maxWidth: .infinity, alignment: .leading)
                  if !todo.due.isEmpty {
                    Text(todo.due).font(.system(size: 10)).foregroundStyle(Palette.amber)
                  }
                }.padding(9).background(.white, in: RoundedRectangle(cornerRadius: 6))
              }.buttonStyle(.plain)
            }
            if summary.todos.isEmpty {
              Text("无明确待办").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
          }.frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: 9) {
            Text("关键信息").font(.system(size: 10)).foregroundStyle(Palette.purple)
            ForEach(summary.keyInfo, id: \.label) { info in
              HStack(alignment: .top) {
                Text(info.label).foregroundStyle(Palette.muted)
                Spacer()
                Text(info.value).multilineTextAlignment(.trailing)
              }.font(.system(size: 11))
            }
          }.frame(width: 200)
        }
        HStack {
          ActionButton(title: "AI 一键生成回复", icon: "arrowshape.turn.up.left", kind: .ai) {
            store.generate(task: "reply", message: message)
          }
          ActionButton(title: "翻译全文", icon: "character.bubble", kind: .normal) {
            store.generate(task: "translate", message: message)
          }
          Spacer()
        }
      }
    }.padding(16).background(Palette.purpleSoft, in: RoundedRectangle(cornerRadius: 12)).overlay(
      RoundedRectangle(cornerRadius: 12).stroke(Palette.purple.opacity(0.18))
    ).disabled(store.busy.contains("agent"))
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
          HStack {
            Text(fileSize(attachment.size)).font(.system(size: 9)).foregroundStyle(Palette.muted)
            if !attachment.text.isEmpty {
              Tag(text: attachment.analysis == nil ? "已提取文本" : "AI 已解析", ai: true)
            }
          }
        }
        Spacer(minLength: 0)
      }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(
        RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
    }.buttonStyle(.plain)
  }
}
