import AppKit
import BoxmailCore
import SwiftUI

struct ComposerView: View {
  @Bindable var store: MailStore
  let initial: MailDraft
  @Environment(\.dismiss) private var dismiss
  @ViewState<MailDraft> private var draft: MailDraft
  @ViewState<String> private var prompt = ""
  @ViewState<String> private var tone = "正式"
  @ViewState<String> private var length = "适中"
  @ViewState<AgentResult?> private var generated: AgentResult?
  @ViewState<Bool> private var saving = false
  @ViewState<Bool> private var saved = false
  @ViewState<Bool> private var sending = false
  @ViewState<String?> private var saveError: String?
  @ViewState<Bool> private var confirmSend = false
  @ViewState<Task<Void, Never>?> private var autosave: Task<Void, Never>?
  @ViewState<String?> private var focusedAddress: String?
  @FocusState private var subjectFocused: Bool
  @ViewState<Bool> private var importingAttachments = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(store: MailStore, initial: MailDraft) {
    self.store = store
    self.initial = initial
    _draft = State(initialValue: initial)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ActionButton(title: sending ? "正在发送…" : "发送", icon: "paperplane", kind: .primary) {
          confirmSend = true
        }.disabled(
          sending || importingAttachments || draft.status == "uncertain" || draft.to.isEmpty
            || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
        HStack(spacing: 8) {
          Text("发件人").font(UIType.caption).foregroundStyle(Palette.muted)
          WorkflowSelection(title: "发件账户", selection: $draft.accountId,
            options: store.accounts.map { ($0.id, $0.email) }).frame(width: 240)
        }
        Spacer()
        Text(saveError ?? (saving ? "正在保存…" : saved ? "草稿已保存到本机" : "编辑中 · 自动保存")).font(
          .system(size: 11)
        ).foregroundStyle(saveError == nil ? Palette.muted : Palette.amber)
          .contentTransition(.opacity)
          .animation(UIMotion.feedback(reduceMotion), value: saved)
        ActionButton(title: "保存并关闭") {
          Task {
            do {
              try await persist()
              dismiss()
            } catch { store.error = error.localizedDescription }
          }
        }.disabled(sending || importingAttachments)
        IconButton(icon: "xmark", help: "保存并关闭") {
          Task {
            do {
              try await persist()
              dismiss()
            } catch { store.error = error.localizedDescription }
          }
        }.disabled(sending || importingAttachments)
      }.padding(16).background(Palette.chrome).fixedSize(horizontal: false, vertical: true)
      Divider()
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          recipientField("收件人", text: $draft.to, others: [draft.cc, draft.bcc]).zIndex(focusedAddress == "收件人" ? 20 : 0)
          recipientField("抄送", text: $draft.cc, others: [draft.to, draft.bcc]).zIndex(focusedAddress == "抄送" ? 20 : 0)
          recipientField("密送", text: $draft.bcc, others: [draft.to, draft.cc]).zIndex(focusedAddress == "密送" ? 20 : 0)
          addressField("主题", text: $draft.subject)
          if draft.status == "uncertain" {
            Text("上次发送结果待确认。请先检查服务器已发送邮箱，确认未送达后再复制内容到新草稿。").font(.system(size: 12)).foregroundStyle(
              Palette.amber
            ).padding(14).background(Palette.blueSoft)
          }
          PlainTextEditor(
            text: $draft.body, fontSize: 14, lineSpacing: 5, inset: NSSize(width: 24, height: 18),
            accessibilityLabel: "邮件正文", bottomAnchoredText: store.settings.preferences.signature,
            onPaste: pasteAttachments
          ).frame(minHeight: 120).background(.white)
          Divider()
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text(importingAttachments ? "正在添加附件…" : "附件 · \(draft.attachmentIds.count) 个")
                .font(.system(size: 12, weight: .medium))
              Spacer()
              ActionButton(title: "添加附件", icon: "paperclip") { addAttachments() }
            }
            OverlayScrollView(.horizontal) {
              HStack {
                ForEach(draft.attachmentIds, id: \.self) { id in
                  if let a = store.attachments.first(where: { $0.id == id }) {
                    HStack {
                      AttachmentIcon(attachment: a, size: 19)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(.system(size: 11)).lineLimit(1)
                        Text(fileSize(a.size)).font(UIType.small).foregroundStyle(Palette.muted)
                      }
                      IconButton(icon: "xmark", help: "移除附件") {
                        draft.attachmentIds.removeAll { $0 == id }
                      }
                    }.padding(8).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
                  }
                }
              }
            }
          }.padding(16).background(.white).fixedSize(horizontal: false, vertical: true)
            .disabled(importingAttachments)
        }.frame(maxWidth: .infinity)
        Divider()
        OverlayScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
              Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                .symbolEffect(.pulse, options: .repeating,
                  isActive: store.busy.contains("compose-ai") && !reduceMotion)
              Text("AI 写作助手").font(.system(size: 15, weight: .semibold))
            }
            Text("描述要写的内容，或对现有正文提出修改要求").font(.system(size: 12)).foregroundStyle(Palette.muted)
              .lineSpacing(4)
            PlainTextEditor(
              text: $prompt, placeholder: "例如：礼貌确认收到，并询问下一步安排", accessibilityLabel: "AI 写信要求"
            ).frame(height: 136).background(
              .white, in: RoundedRectangle(cornerRadius: 8)
            ).clipShape(RoundedRectangle(cornerRadius: 8))

            Text("语气").font(.system(size: 11)).foregroundStyle(Palette.muted)
            FilterBar(values: ["正式", "亲切", "简洁", "专业"], selection: $tone, compact: true)
            Text("长度").font(.system(size: 11)).foregroundStyle(Palette.muted)
            FilterBar(values: ["简短", "适中", "详细"], selection: $length, compact: true)
            HStack {
              ActionButton(title: store.busy.contains("compose-ai") ? "正在拟稿…" : "生成草稿", icon: "sparkles", kind: .ai) { generate() }.disabled(
                prompt.isEmpty || store.busy.contains("agent"))
              if store.busy.contains("agent") { ProgressView().controlSize(.small) }
            }
            if let generated {
              VStack(alignment: .leading, spacing: 14) {
                Divider()
                Text("AI 生成草稿").font(UIType.section)
                Text(generated.subject ?? "").font(.system(size: 13, weight: .medium))
                Text(generated.body ?? "").font(UIType.body).lineSpacing(6).textSelection(.enabled)
                ActionButton(title: "插入到正文", icon: "text.insert", kind: .softAI) {
                  draft.subject = generated.subject ?? draft.subject
                  if let body = generated.body {
                    draft.body = MailSignature.replacingContent(
                      with: body, in: draft.body, signature: store.settings.preferences.signature)
                  }
                }
              }.transition(UIMotion.reveal(reduceMotion))
            }
          }.padding(22).animation(UIMotion.disclosure(reduceMotion), value: generated != nil)
        }.frame(width: 320).background(Palette.canvas)
      }.disabled(sending || draft.status == "uncertain")
    }.frame(width: 1080, height: 720).background(.white).tint(Palette.blue)
      .interactiveDismissDisabled()
      .onChange(of: subjectFocused) { _, focused in
        if focused { focusedAddress = "主题" } else if focusedAddress == "主题" { focusedAddress = nil }
      }
      .onChange(of: draft) { _, _ in scheduleSave() }
      .alert(
        "操作未完成",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("确定") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
      .alert("确认发送邮件", isPresented: $confirmSend) {
        Button("取消", role: .cancel) {}
        Button("确认发送") { send() }
      } message: {
        Text(
          "收件人：\(draft.to)\n主题：\(draft.subject.isEmpty ? "无主题" : draft.subject)\n附件：\(draft.attachmentIds.count) 个"
        )
      }
  }
  private func recipientField(_ title: String, text: Binding<String>, others: [String]) -> some View {
    HStack {
      Text(title).font(UIType.caption).foregroundStyle(Palette.muted).frame(width: 52, height: 30, alignment: .trailing)
      RecipientEntryView(title: title, accountID: draft.accountId, text: text, otherRecipients: others) { focused in
        if focused { focusedAddress = title } else if focusedAddress == title { focusedAddress = nil }
      }.padding(.leading, 10)
    }.padding(.horizontal, 20).frame(height: 40).overlay(alignment: .bottom) {
      Rectangle().fill(focusedAddress == title ? Palette.blue : Palette.softBorder)
        .frame(height: focusedAddress == title ? 2 : 1)
    }
  }
  private func addressField(_ title: String, text: Binding<String>) -> some View {
    HStack {
      Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
        width: 52, alignment: .trailing)
      TextField(title == "主题" ? "填写邮件主题" : "邮箱地址，多个地址用逗号分隔", text: text).textFieldStyle(.plain)
        .font(.system(size: title == "主题" ? 14 : 13, weight: title == "主题" ? .medium : .regular)).padding(.leading, 10)
        .focused($subjectFocused).accessibilityLabel(title)
    }.padding(.horizontal, 20).frame(height: title == "主题" ? 46 : 40).overlay(alignment: .bottom) {
      Rectangle().fill(focusedAddress == title ? Palette.blue : Palette.softBorder).frame(
        height: focusedAddress == title ? 2 : 1)
    }.animation(UIMotion.feedback(reduceMotion), value: focusedAddress == title)
  }
  private func scheduleSave() {
    guard draft.status == "draft" else { return }
    saved = false
    autosave?.cancel()
    autosave = Task {
      do {
        try await Task.sleep(for: .milliseconds(900))
        try Task.checkCancellation()
        try await persist()
      } catch is CancellationError {} catch { saveError = error.localizedDescription }
    }
  }
  private func persist() async throws {
    if draft.status != "draft" { return }
    while saving { try await Task.sleep(for: .milliseconds(80)) }
    saving = true
    defer { saving = false }
    let snapshot = draft
    let result: MailDraft = try await BackendService.shared.request(
      "/drafts", method: "POST", body: try jsonObject(snapshot))
    saved = snapshot == draft
    saveError = nil
    if let index = store.drafts.firstIndex(where: { $0.id == result.id }) {
      store.drafts[index] = result
    } else {
      store.drafts.append(result)
    }
  }
  private func generate() {
    store.action("compose-ai") {
      let job = try await store.runAI(
        task: "compose", prompt: prompt, body: draft.body, tone: tone, length: length)
      generated = job.result
    }
  }
  private func send() {
    sending = true
    autosave?.cancel()
    Task {
      defer { sending = false }
      do {
        try await persist()
        let password = try KeychainService.read("mail-\(draft.accountId)")
        let result: SendResponse = try await BackendService.shared.request(
          "/send", method: "POST",
          body: ["draftId": draft.id, "password": password, "approved": true])
        try await store.refresh()
        var message = "邮件已通过 SMTP 发送"
        if let rejected = result.rejected, !rejected.isEmpty {
          message += "\n部分收件人未接受：" + rejected.joined(separator: ", ")
        }
        if let warning = result.warning, !warning.isEmpty { message += "\n" + warning }
        store.notice = message
        dismiss()
      } catch {
        store.error = error.localizedDescription
        try? await store.refresh()
        if let current = store.drafts.first(where: { $0.id == draft.id }) { draft = current }
      }
    }
  }
  private func addAttachments() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    if panel.runModal() == .OK {
      importAttachments(panel.urls.map { .file($0) })
    }
  }
  @discardableResult private func pasteAttachments(_ pasteboard: NSPasteboard) -> Bool {
    guard !sending, draft.status == "draft" else { return false }
    do {
      let sources = try ComposerAttachmentSource.read(from: pasteboard)
      guard !sources.isEmpty else { return false }
      guard !importingAttachments else { return true }
      importAttachments(sources)
    } catch { store.error = error.localizedDescription }
    return true
  }
  private func importAttachments(_ sources: [ComposerAttachmentSource]) {
    guard !importingAttachments else { return }
    importingAttachments = true
    Task {
      defer { importingAttachments = false }
      do {
        for source in sources {
          let payload = try await Task.detached(priority: .userInitiated) { try source.payload() }.value
          let attachment: MailAttachment = try await BackendService.shared.request(
            "/attachments", method: "POST",
            body: [
              "draftId": draft.id, "name": payload.name, "contentType": payload.contentType,
              "content": payload.data.base64EncodedString(),
            ])
          store.attachments.append(attachment)
          draft.attachmentIds.append(attachment.id)
        }
        try await persist()
      } catch { store.error = error.localizedDescription }
    }
  }
}
