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
  @ViewState private var writing: WritingPreferencesStore
  @ViewState private var generatedSource = ""
  @ViewState<RichTextDocument?> private var generatedDocument: RichTextDocument?
  @ViewState private var generatedSubject = ""
  @ViewState<RichTextController.RewriteSelection?> private var rewriteSelection: RichTextController.RewriteSelection?
  @ViewState private var scheduledSend = false
  @ViewState private var sendDate = Date().addingTimeInterval(3600)
  @ViewState private var showSchedule = false
  @ViewState<AgentResult?> private var generated: AgentResult?
  @ViewState<Bool> private var saving = false
  @ViewState<Bool> private var saved = false
  @ViewState<Bool> private var sending = false
  @ViewState<Bool> private var closing = false
  @ViewState<String?> private var saveError: String?
  @ViewState<Bool> private var confirmSend = false
  @ViewState<Task<Void, Never>?> private var autosave: Task<Void, Never>?
  @ViewState<String?> private var focusedAddress: String?
  @FocusState private var subjectFocused: Bool
  @ViewState<Bool> private var importingAttachments = false
  @ViewState<Bool> private var showingAssistant = false
  @ViewState<Bool> private var showingCC = false
  @ViewState<Bool> private var showingBCC = false
  @ViewState<RichTextController> private var richEditor = RichTextController()
  @ViewState<Bool> private var showingLink = false
  @ViewState<Bool> private var syncingDraft = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(store: MailStore, initial: MailDraft) {
    self.store = store
    self.initial = initial
    _writing = ViewState(initialValue: WritingPreferencesStore(backend: store.backend))
    _draft = State(initialValue: initial)
    _showingCC = ViewState(wrappedValue: !initial.cc.isEmpty)
    _showingBCC = ViewState(wrappedValue: !initial.bcc.isEmpty)
  }
  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Text("写邮件").font(UIType.heading).accessibilityAddTraits(.isHeader)
          Spacer(minLength: 8)
          HStack(spacing: 8) {
            Text("发件人").font(UIType.caption).foregroundStyle(Palette.muted)
            WorkflowSelection(
              title: "发件账户", selection: $draft.accountId,
              options: store.accounts.map { ($0.id, $0.email) }
            )
            .frame(minWidth: 160, idealWidth: 220, maxWidth: 240)
          }
          ActionButton(title: showingAssistant ? "收起 AI" : "AI 写信", icon: .pencilAiLine,
            emphasis: showingAssistant ? .tinted : .secondary) {
            withAnimation(UIMotion.disclosure(reduceMotion)) { showingAssistant.toggle() }
          }
          .accessibilityValue(showingAssistant ? "已展开" : "已收起")
          .cossPopover(
            isPresented: Binding(
              get: { showingAssistant && geometry.size.width < 940 },
              set: { if !$0 { showingAssistant = false } }), arrowEdge: .bottom
          ) {
            writingAssistant.frame(
              width: 320, height: min(520, max(400, geometry.size.height - 80))
            )
            .disabled(sending || closing || draft.status != "draft")
          }
          IconButton(icon: .closeLine, help: "保存草稿并关闭") { closeComposer() }
            .keyboardShortcut(.cancelAction).disabled(sending || importingAttachments)
        }.padding(.horizontal, 20).frame(height: 56).background(Palette.chrome)
        CossSeparator()
        HStack(spacing: 0) {
          VStack(spacing: 0) {
            VStack(spacing: 8) {
              recipientField("收件人", text: $draft.to, others: [draft.cc, draft.bcc]).zIndex(
                focusedAddress == "收件人" ? 20 : 0)
              if showingCC || !draft.cc.isEmpty {
                recipientField("抄送", text: $draft.cc, others: [draft.to, draft.bcc]).zIndex(
                  focusedAddress == "抄送" ? 20 : 0)
              }
              if showingBCC || !draft.bcc.isEmpty {
                recipientField("密送", text: $draft.bcc, others: [draft.to, draft.cc]).zIndex(
                  focusedAddress == "密送" ? 20 : 0)
              }
              addressField("主题", text: $draft.subject)
            }.padding(.horizontal, 20).padding(.vertical, 12).zIndex(1)
            if draft.status == "uncertain" {
              WorkflowNotice(
                text: "上次发送结果待确认。请先检查服务器已发送邮箱，确认未送达后再复制内容到新草稿。",
                icon: .errorWarningLine, color: Palette.amber
              ).padding(12).background(Palette.canvas)
            }
            CossSeparator()
            if let forwardedText = draft.forwardedText {
              OverlayScrollView {
                VStack(spacing: 0) {
                  bodyEditor(label: "转发说明", placeholder: "在此填写转发说明")
                    .frame(
                      height: max(
                        140,
                        min(240, CGFloat(draft.body.components(separatedBy: "\n").count) * 22 + 44))
                    )
                  CossSeparator()
                  ForwardedMailPreview(
                    html: draft.forwardedHTML, text: forwardedText,
                    preferences: store.settings.preferences)
                }
              }.background(.white)
            } else {
              bodyEditor(label: "邮件正文").frame(minHeight: 120).background(.white)
            }
            if !draft.attachmentIds.isEmpty {
              CossSeparator()
              OverlayScrollView(.horizontal) {
                HStack(spacing: 8) {
                  ForEach(draft.attachmentIds, id: \.self) { id in
                    if let a = store.attachments.first(where: { $0.id == id }) {
                      HStack {
                        AttachmentIcon(attachment: a, size: 19)
                        VStack(alignment: .leading, spacing: 3) {
                          Text(a.name).font(.system(size: 11)).lineLimit(1)
                          Text(fileSize(a.size)).font(UIType.small).foregroundStyle(Palette.muted)
                        }
                        IconButton(icon: .closeLine, help: "移除附件") {
                          draft.attachmentIds.removeAll { $0 == id }
                        }
                      }.padding(8).framedSurface()
                    }
                  }
                }.padding(.horizontal, 20).padding(.vertical, 8)
              }
              .background(Palette.canvas).fixedSize(horizontal: false, vertical: true)
              .disabled(importingAttachments)
            }
          }.frame(maxWidth: .infinity)
          if showingAssistant && geometry.size.width >= 940 {
            CossSeparator(axis: .vertical)
            writingAssistant.frame(width: 300)
          }
        }.disabled(sending || draft.status == "uncertain")
        composeFooter
      }.disabled(sending || closing)
    }.frame(minWidth: 680, minHeight: 480).background(.white).tint(Palette.accent)
      .interactiveDismissDisabled()
      .onChange(of: subjectFocused) { _, focused in
        if focused { focusedAddress = "主题" } else if focusedAddress == "主题" { focusedAddress = nil }
      }
      .onChange(of: draft) { old, new in if !old.hasSameContent(as: new) { scheduleSave() } }
      .onDisappear { autosave?.cancel() }
      .storeAlert(
        "操作未完成", text: { store.error }, isPresented: { store.error != nil },
        dismiss: { store.error = nil })
      .cossAlert("确认发送邮件", isPresented: $confirmSend) {
        CossAlertAction("取消", role: .cancel)
        CossAlertAction("确认发送") { send() }
      } message: {
        Text(
          "收件人：\(draft.to)\n主题：\(draft.subject.isEmpty ? "无主题" : draft.subject)\n附件：\(draft.attachmentIds.count) 个\n" + (scheduledSend ? "计划于 \(sendDate.formatted(date: .complete, time: .shortened))（\(TimeZone.current.identifier)）发送" : "确认后等待 10 秒提交，可在发送管理中取消")
        )
      }
  }

  private var composeFooter: some View {
    HStack(spacing: 8) {
      ActionButton(title: importingAttachments ? "正在添加附件…" : "添加附件", icon: .attachment2) {
        addAttachments()
      }.disabled(importingAttachments || draft.status == "uncertain")
      draftSaveStatus
      Spacer(minLength: 8)
      ActionButton(title: "定时发送", icon: .timeLine, emphasis: .secondary) { showSchedule = true }
        .disabled(syncingDraft || importingAttachments || draft.status != "draft")
        .cossPopover(isPresented: $showSchedule) {
          VStack(alignment: .leading, spacing: 16) {
            Text("定时发送").font(UIType.heading).accessibilityAddTraits(.isHeader)
            SendScheduleForm(date: $sendDate)
            ActionButton(title: "确认时间", emphasis: .primary) {
              scheduledSend = true
              showSchedule = false
              confirmSend = true
            }.disabled(draft.to.isEmpty || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
          }.padding(24).frame(width: 440).background(Palette.paper)
        }
      ActionButton(title: sending ? "正在发送…" : "发送", icon: .sendPlaneLine, emphasis: .primary) {
        scheduledSend = false
        confirmSend = true
      }.disabled(
        syncingDraft || importingAttachments || draft.status == "uncertain" || draft.to.isEmpty
          || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
    }.padding(.horizontal, 20).padding(.vertical, 10).background(Palette.chrome)
      .overlay(alignment: .top) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
  }
  private var draftSaveMessage: String {
    saveError ?? (saving ? "正在保存…" : saved ? "草稿已保存" : "自动保存草稿")
  }
  private var draftSaveStatus: some View {
    Text(draftSaveMessage).font(UIType.small)
      .foregroundStyle(saveError == nil ? Palette.muted : Palette.destructive)
      .lineLimit(1).cossTooltip(draftSaveMessage)
  }
  private var writingAssistant: some View {
    OverlayScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 8) {
          Text("AI 写作").font(UIType.section)
        }
        Text("描述要写的内容，或对现有正文提出修改要求").font(.system(size: 12)).foregroundStyle(Palette.muted)
          .lineSpacing(4)
        PlainTextEditor(
          text: $prompt, placeholder: "例如：礼貌确认收到，并询问下一步安排", accessibilityLabel: "AI 写信要求"
        ).frame(height: 136).background(
          .white, in: RoundedRectangle(cornerRadius: 8)
        ).clipShape(RoundedRectangle(cornerRadius: 8))

        AIWritingParameters(tone: $tone, length: $length)
        WritingPreferencesView(store: store, writing: writing, accountId: draft.accountId)
        HStack {
          ActionButton(
            title: store.busy.contains("compose-ai") ? "正在拟稿…" : "生成草稿", icon: .pencilAiLine, color: Palette.accent, emphasis: .tinted
          ) { generate() }.disabled(
            prompt.isEmpty || store.busy.contains("agent"))
          if store.busy.contains("agent") { CossSpinner() }
        }
        ActionButton(title: "改写选中文本", icon: .inputCursorMove) { generate(selectionOnly: true) }
          .disabled(!richEditor.hasSelection || store.busy.contains("agent"))
        if store.busy.contains("compose-ai"), let output = store.aiOutput(task: "compose") {
          AIStreamingView(output: output)
        } else if let generated {
          VStack(alignment: .leading, spacing: 14) {
            CossSeparator()
            Text("AI 生成草稿").font(UIType.section)
            Text(generated.subject ?? "").font(.system(size: 13, weight: .medium))
            AnalysisDocumentView(text: generated.body ?? "")
            ActionButton(title: rewriteSelection == nil ? "替换正文（保留签名）" : "替换原选区", icon: .findReplaceLine, color: Palette.accent) {
              guard let body = generated.body, draft.body == generatedSource, draft.richText == generatedDocument else { return }
              let replacement = rewriteSelection == nil ? MailSignature.replacingContent(with: body, in: generatedSource, signature: store.signature(for: draft.accountId)) : body
              if richEditor.adopt(replacement, expectedSource: generatedSource, selection: rewriteSelection) {
                if rewriteSelection == nil && draft.subject == generatedSubject { draft.subject = generated.subject ?? draft.subject }
                self.generated = nil
              } else { store.error = "正文已在生成期间修改，候选仍保留，请重新生成后再采用。" }
            }.disabled(draft.body != generatedSource || draft.richText != generatedDocument)
            if draft.body != generatedSource || draft.richText != generatedDocument { Text("正文已修改，此候选不能覆盖当前编辑。").font(UIType.small).foregroundStyle(Palette.muted) }
          }.transition(UIMotion.reveal(reduceMotion))
        }
      }.padding(20).animation(UIMotion.disclosure(reduceMotion), value: generated != nil)
    }.background(Palette.canvas)
  }
  private func closeComposer() {
    guard !closing && !sending && !importingAttachments else { return }
    closing = true
    autosave?.cancel()
    Task {
      defer { closing = false }
      do {
        if store.drafts.contains(where: { $0.id == draft.id }) || draft != initial {
          try await persist()
        }
        dismiss()
      } catch { store.error = error.localizedDescription }
    }
  }
  private var addressOptions: some View {
    CossMenu(title: "显示抄送或密送字段", width: 156) {
      CossMenuItem.command("抄送", mark: .checkbox(showingCC), enabled: draft.cc.isEmpty) { showingCC.toggle() }
      CossMenuItem.command("密送", mark: .checkbox(showingBCC), enabled: draft.bcc.isEmpty) { showingBCC.toggle() }
    } trigger: {
      CossMenuLabel(title: "抄送 / 密送", size: .compact, color: Palette.muted)
    }.fixedSize()
  }
  private func bodyEditor(label: String, placeholder: String = "") -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 4) {
        RichTextFormatBar(controller: richEditor, showingLink: $showingLink)
        Spacer(minLength: 0)
        if store.accounts.first(where: { $0.id == draft.accountId })?.isDemo == false {
          ActionButton(title: syncingDraft ? "正在同步…" : "同步草稿", icon: .loopRightLine) {
            syncDraft()
          }.disabled(syncingDraft || store.busy.contains("sync"))
        }
        if saveError != nil {
          ActionButton(title: "另存为新草稿", icon: .fileCopyLine) { saveCopy() }
        }
      }.padding(.horizontal, 16).frame(height: 36).background(Palette.chrome)
      RichTextEditor(text: $draft.body, document: $draft.richText, controller: richEditor,
        placeholder: placeholder, accessibilityLabel: label, signature: store.signature(for: draft.accountId),
        onPaste: pasteAttachments, onLink: { showingLink = true })
    }
  }
  private func saveCopy() {
    guard !saving, !sending, !closing else { return }
    autosave?.cancel()
    draft.id = UUID().uuidString
    draft.revision = nil; draft.syncState = "local"; draft.syncError = nil; draft.conflictOf = nil
    Task { do { try await persist() } catch { saveError = error.localizedDescription } }
  }
  private func syncDraft() {
    guard !syncingDraft, !saving, !sending, !closing else { return }
    autosave?.cancel(); syncingDraft = true
    Task {
      defer { syncingDraft = false }
      do {
        try await persist()
        let syncedID = draft.id, syncedAccount = draft.accountId
        await store.syncAll(folder: "drafts", accountID: syncedAccount)
        guard draft.id == syncedID, draft.accountId == syncedAccount, store.composer?.id == syncedID
        else { return }
        let current: MailDraft = try await store.backend.request("/drafts/\(draft.id)")
        guard draft.id == syncedID, draft.accountId == syncedAccount, store.composer?.id == syncedID
        else { return }
        if draft.hasSameContent(as: current) {
          draft.revision = current.revision; draft.syncState = current.syncState;
          draft.syncError = current.syncError
        } else {
          saveError = "服务器草稿已更新，当前编辑内容仍保留，可另存为新草稿。"
        }
      } catch { saveError = error.localizedDescription }
    }
  }
  private func recipientField(_ title: String, text: Binding<String>, others: [String]) -> some View
  {
    HStack(spacing: 10) {
      Text(title).font(UIType.caption).foregroundStyle(Palette.ink).frame(width: 52, alignment: .leading)
      RecipientEntryView(title: title, accountID: draft.accountId, text: text, otherRecipients: others) { focused in
        if focused { focusedAddress = title } else if focusedAddress == title { focusedAddress = nil }
      }.padding(.horizontal, 10).frame(height: 34)
        .controlFieldSurface(focused: focusedAddress == title)
      if title == "收件人" { addressOptions }
    }
  }
  private func addressField(_ title: String, text: Binding<String>) -> some View {
    HStack(spacing: 10) {
      Text(title).font(UIType.caption).foregroundStyle(Palette.ink).frame(width: 52, alignment: .leading)
      TextField("", text: text).textFieldStyle(.plain)
        .font(.system(size: 14, weight: .medium)).padding(.horizontal, 10).frame(height: 34)
        .focused($subjectFocused).accessibilityLabel(title)
        .controlFieldSurface(focused: subjectFocused)
        .inputPlaceholder("填写邮件主题", visible: text.wrappedValue.isEmpty)
    }.animation(UIMotion.feedback(reduceMotion), value: focusedAddress == title)
  }
  private func scheduleSave() {
    guard draft.status == "draft", !sending, !closing else { return }
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
    saved = snapshot.hasSameContent(as: draft)
    saveError = nil
    if draft.id == snapshot.id {
      draft.revision = result.revision
      draft.syncState = result.syncState
      draft.syncError = result.syncError
    }
    if let index = store.drafts.firstIndex(where: { $0.id == result.id }) {
      store.drafts[index] = result.compact
    } else {
      store.drafts.append(result.compact)
    }
  }
  private func generate(selectionOnly: Bool = false) {
    let selection = selectionOnly ? richEditor.rewriteSelection() : nil
    if selectionOnly && selection == nil { return }
    generated = nil
    generatedDocument = draft.richText
    generatedSource = draft.body; generatedSubject = draft.subject; rewriteSelection = selection
    let source = selection?.text ?? draft.body
    store.action("compose-ai") {
      let job = try await store.runAI(task: "compose", prompt: selectionOnly ? "仅改写提供的选区，保持原意。" + prompt : prompt,
        body: source, tone: tone, length: length, outputLanguage: writing.language, writingStyle: writing.selectedInstruction)
      generated = job.result
    }
  }
  private func send() {
    guard !sending, !syncingDraft, !closing, !importingAttachments, draft.status == "draft" else { return }
    sending = true
    autosave?.cancel()
    Task {
      defer { sending = false }
      do {
        try await persist()
        let _: SendPlan = try await store.backend.request("/send-plans", method: "POST",
          body: ["draftId": draft.id, "approved": true,
            "scheduledAt": ISO8601DateFormatter().string(from: scheduledSend ? sendDate : Date().addingTimeInterval(10)),
            "timeZone": TimeZone.current.identifier])
        try await store.refresh()
        store.notice = scheduledSend ? "已安排投递，可在发送管理中改期或取消。" : "正在等待发送，可在发送管理中取消并返回草稿。"
        store.navigate(.outbox)
        await store.sendQueue.load()
        dismiss()
      } catch {
        store.error = error.localizedDescription
        try? await store.refresh()
        if let current = store.drafts.first(where: { $0.id == draft.id }) {
          if current.bodyLoaded != false { draft = current } else { draft.status = current.status }
        }
      }
    }
  }
  private func addAttachments() {
    if let urls = FilePanel.openURLs(allowsMultipleSelection: true) {
      importAttachments(urls.map { .file($0) })
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
