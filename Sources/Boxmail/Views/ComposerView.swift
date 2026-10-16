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
  @FocusState private var focusedAddress: String?
  init(store: MailStore, initial: MailDraft) {
    self.store = store
    self.initial = initial
    _draft = State(initialValue: initial)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        ActionButton(title: sending ? "正在发送…" : "发送", icon: "paperplane.fill", kind: .primary) {
          confirmSend = true
        }.disabled(
          sending || draft.status == "uncertain" || draft.to.isEmpty
            || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
        ChoiceMenu(title: "发件人：\(store.accounts.first{$0.id==draft.accountId}?.email ?? "请选择")") {
          ForEach(store.accounts) { account in
            Button(menuTitle(account.name)) { draft.accountId = account.id }
          }
        }
        Spacer()
        Text(saveError ?? (saving ? "正在保存…" : saved ? "草稿已保存到本机" : "编辑中 · 自动保存")).font(
          .system(size: 11)
        ).foregroundStyle(saveError == nil ? Palette.muted : .red)
        ActionButton(title: "保存并关闭") {
          Task {
            do {
              try await persist()
              dismiss()
            } catch { store.error = error.localizedDescription }
          }
        }.disabled(sending)
        IconButton(icon: "xmark", help: "保存并关闭") {
          Task {
            do {
              try await persist()
              dismiss()
            } catch { store.error = error.localizedDescription }
          }
        }.disabled(sending)
      }.padding(16).background(Palette.chrome)
      Divider()
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          addressField("收件人", text: $draft.to)
          addressField("抄送", text: $draft.cc)
          addressField("密送", text: $draft.bcc)
          addressField("主题", text: $draft.subject)
          if draft.status == "uncertain" {
            Text("上次发送结果待确认。请先检查服务器已发送邮箱，确认未送达后再复制内容到新草稿。").font(.system(size: 12)).foregroundStyle(
              Palette.amber
            ).padding(14).background(Palette.blueSoft)
          }
          PlainTextEditor(
            text: $draft.body, fontSize: 14, lineSpacing: 5, inset: NSSize(width: 24, height: 18),
            accessibilityLabel: "邮件正文"
          ).background(.white)
          Divider()
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Text("附件 · \(draft.attachmentIds.count) 个").font(.system(size: 12, weight: .medium))
              Spacer()
              ActionButton(title: "添加附件", icon: "paperclip") { addAttachments() }
            }
            ScrollView(.horizontal) {
              HStack {
                ForEach(draft.attachmentIds, id: \.self) { id in
                  if let a = store.attachments.first(where: { $0.id == id }) {
                    HStack {
                      Image(systemName: "doc").foregroundStyle(Palette.blue)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(a.name).font(.system(size: 11)).lineLimit(1)
                        Text(fileSize(a.size)).font(.system(size: 9)).foregroundStyle(Palette.muted)
                      }
                      IconButton(icon: "xmark", help: "移除附件") {
                        draft.attachmentIds.removeAll { $0 == id }
                      }
                    }.padding(8).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
                  }
                }
              }
            }
          }.padding(16).background(.white)
        }.frame(maxWidth: .infinity)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            Label("AI 写作助手", systemImage: "sparkles").font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Palette.ink)
            Text("描述要写的内容，或对现有正文提出修改要求").font(.system(size: 12)).foregroundStyle(Palette.muted)
              .lineSpacing(4)
            PlainTextEditor(
              text: $prompt, placeholder: "例如：礼貌确认收到，并询问下一步安排", accessibilityLabel: "AI 写信要求"
            ).frame(height: 136).background(
              .white, in: RoundedRectangle(cornerRadius: 8)
            ).clipShape(RoundedRectangle(cornerRadius: 8))
              .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            Text("语气").font(.system(size: 11)).foregroundStyle(Palette.muted)
            Picker("语气", selection: $tone) {
              ForEach(["正式", "亲切", "简洁", "专业"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text("长度").font(.system(size: 11)).foregroundStyle(Palette.muted)
            Picker("长度", selection: $length) {
              ForEach(["简短", "适中", "详细"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
              ActionButton(title: "生成草稿", icon: "sparkles", kind: .ai) { generate() }.disabled(
                prompt.isEmpty || store.busy.contains("agent"))
              if store.busy.contains("agent") { ProgressView().controlSize(.small) }
            }
            if let generated {
              Divider()
              Text("AI 生成草稿").font(.system(size: 13, weight: .semibold))
              Text(generated.subject ?? "").font(.system(size: 12, weight: .medium))
              Text(generated.body ?? "").font(.system(size: 12)).lineSpacing(5).textSelection(
                .enabled)
              ActionButton(title: "插入到正文", icon: "text.insert", kind: .softAI) {
                draft.subject = generated.subject ?? draft.subject
                draft.body = generated.body ?? draft.body
              }
            }
          }.padding(20)
        }.frame(width: 310).background(Palette.canvas)
      }.disabled(sending || draft.status == "uncertain")
    }.frame(width: 1080, height: 720).background(.white).tint(Palette.blue)
      .interactiveDismissDisabled()
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
  private func addressField(_ title: String, text: Binding<String>) -> some View {
    HStack {
      Text(title).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(
        width: 52, alignment: .trailing)
      TextField(title == "主题" ? "填写邮件主题" : "邮箱地址，多个地址用逗号分隔", text: text).textFieldStyle(.plain)
        .font(.system(size: 13, weight: title == "主题" ? .medium : .regular)).padding(.leading, 10)
        .focused($focusedAddress, equals: title).accessibilityLabel(title)
    }.padding(.horizontal, 20).frame(height: 40).overlay(alignment: .bottom) {
      Rectangle().fill(focusedAddress == title ? Palette.blue : Palette.softBorder).frame(
        height: focusedAddress == title ? 2 : 1)
    }
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
      let urls = panel.urls
      store.action("upload") {
        for url in urls {
          let data = try Data(contentsOf: url)
          guard data.count <= 25 * 1024 * 1024 else {
            throw BackendService.shared.failure("单个附件不能超过 25 MB")
          }
          let attachment: MailAttachment = try await BackendService.shared.request(
            "/attachments", method: "POST",
            body: [
              "draftId": draft.id, "name": url.lastPathComponent,
              "content": data.base64EncodedString(),
            ])
          store.attachments.append(attachment)
          draft.attachmentIds.append(attachment.id)
        }
      }
    }
  }
}
