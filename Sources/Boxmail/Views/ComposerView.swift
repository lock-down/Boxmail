import AppKit
import BoxmailCore
import SwiftUI

struct ComposerView: View {
  @Bindable var store: MailStore
  let initial: MailDraft
  @Environment(\.dismissComposer) private var dismiss
  @ViewState<MailDraft> private var draft: MailDraft
  @ViewState private var writing: WritingPreferencesStore
  @ViewState private var writingSession = ComposerWritingSession()
  @ViewState private var scheduledSend = false
  @ViewState private var editingSendPlan: SendPlan?
  @ViewState private var sendDate = Date().addingTimeInterval(3600)
  @ViewState private var showSchedule = false
  @ViewState<Bool> private var saving = false
  @ViewState<Bool> private var saved = false
  @ViewState<Bool> private var sending = false
  @ViewState<Bool> private var closing = false
  @ViewState<String?> private var saveError: String?
  @ViewState private var closeError: String?
  @ViewState<Bool> private var confirmSend = false
  @ViewState<Task<Void, Never>?> private var autosave: Task<Void, Never>?
  @ViewState<String?> private var focusedAddress: String?
  @FocusState private var subjectFocused: Bool
  @ViewState<Bool> private var importingAttachments = false
  @ViewState private var attachmentGridHeight: CGFloat = 56
  @ViewState<Bool> private var showingAssistant = false
  @ViewState<Bool> private var showingCC = false
  @ViewState<Bool> private var showingBCC = false
  @ViewState<RichTextController> private var richEditor = RichTextController()
  @ViewState<Bool> private var showingLink = false
  @ViewState<Bool> private var syncingDraft = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  init(store: MailStore, initial: MailDraft, sendPlan: SendPlan? = nil) {
    self.store = store
    self.initial = initial
    _writing = ViewState(initialValue: WritingPreferencesStore(backend: store.backend))
    _draft = State(initialValue: initial)
    _editingSendPlan = ViewState(wrappedValue: sendPlan)
    if let sendPlan, let date = MailTimestamp.date(sendPlan.scheduledAt) {
      _sendDate = ViewState(wrappedValue: date)
    }
    _showingCC = ViewState(wrappedValue: !initial.cc.isEmpty)
    _showingBCC = ViewState(wrappedValue: !initial.bcc.isEmpty)
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Text(editingSendPlan == nil ? "写邮件" : "编辑待发送邮件")
          .font(UIType.heading).accessibilityAddTraits(.isHeader)
          .composerDragRegion()
        Spacer(minLength: 8).frame(height: 56).composerDragRegion()
        HStack(spacing: 8) {
          Text("发件人").font(UIType.caption).foregroundStyle(Palette.muted)
          WorkflowSelection(
            title: "发件账户", selection: senderSelection,
            options: store.accounts.map { ($0.id, $0.email) }
          )
          .frame(minWidth: 160, idealWidth: 220, maxWidth: 240).disabled(!editable)
        }
        IconButton(icon: .x, help: "保存草稿并关闭") { Task { await closeComposer() } }
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
              icon: .infoCircle, color: Palette.amber
            ).padding(12).background(Palette.canvas)
          }
          CossSeparator()
          if let forwardedText = draft.forwardedText {
            OverlayScrollView {
              VStack(spacing: 0) {
                bodyEditor(label: "转发说明", placeholder: "转发说明",
                  editorHeight: max(140, min(240, CGFloat(draft.body.components(separatedBy: "\n").count) * 22 + 44)))
                CossSeparator()
                ForwardedMailPreview(
                  html: draft.forwardedHTML, text: forwardedText,
                  preferences: store.settings.preferences)
              }
            }.background(.white)
          } else {
            bodyEditor(label: "邮件正文").background(.white)
          }
          if !draft.attachmentIds.isEmpty {
            CossSeparator()
            attachmentTray.disabled(importingAttachments)
          }
        }.frame(maxWidth: .infinity)
      }.disabled(sending || draft.status == "uncertain")
      composeFooter.fixedSize(horizontal: false, vertical: true)
    }.disabled(sending || closing)
      .frame(minWidth: 680, minHeight: 480).background(.white).tint(Palette.accent)
      .composerCloseDisabled(sending || closing || importingAttachments, action: closeComposer)
      .task { await writing.load() }
      .onChange(of: subjectFocused) { _, focused in
        if focused { focusedAddress = "主题" } else if focusedAddress == "主题" { focusedAddress = nil }
      }
      .onChange(of: draft) { old, new in if !old.hasSameContent(as: new) { scheduleSave() } }
      .onDisappear { autosave?.cancel() }
      .storeAlert(
        "操作未完成", text: { store.error }, isPresented: { store.error != nil },
        dismiss: { store.error = nil })
      .cossAlert("草稿未能保存", isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } }),
        presenting: closeError) { _ in
        CossAlertAction("继续编辑", role: .cancel)
        CossAlertAction("放弃更改", role: .destructive) { dismiss() }
      } message: { Text($0) }
      .cossAlert("确认发送邮件", isPresented: $confirmSend) {
        CossAlertAction("取消", role: .cancel)
        CossAlertAction("确认发送") { send() }
      } message: {
        Text(
          "收件人：\(draft.to)\n主题：\(draft.subject.isEmpty ? "无主题" : draft.subject)\n附件：\(draft.attachmentIds.count) 个\n" + (scheduledSend ? "计划于 \(sendDate.formatted(date: .complete, time: .shortened))（\(TimeZone.current.identifier)）发送" : "确认后等待 10 秒提交，可在草稿箱中取消")
        )
      }
  }

  private var attachmentTray: some View {
    let files = draft.attachmentIds.compactMap { id in store.attachments.first { $0.id == id } }
    return VStack(alignment: .leading, spacing: 8) {
      Label("\(draft.attachmentIds.count) 个附件", icon: .paperclip)
        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 20)
      if !files.isEmpty {
        OverlayScrollView(persistentIndicators: true) {
          AttachmentGrid {
            ForEach(files) { file in
              AttachmentCard(attachment: file, remove: {
                draft.attachmentIds.removeAll { $0 == file.id }
              })
            }
          }.padding(.horizontal, 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { attachmentGridHeight = $0 }
        }.frame(height: min(attachmentGridHeight, 128))
          .accessibilityLabel("草稿附件")
      }
    }.padding(.vertical, 8)
  }

  private var composeFooter: some View {
    let scheduleTitle = editingSendPlan == nil ? "定时发送" : "更改时间"
    return HStack(spacing: 8) {
      ActionButton(title: importingAttachments ? "添加中…" : "添加附件", icon: .paperclip,
        width: UILayout.pairedActionWidth) {
        addAttachments()
      }.disabled(importingAttachments || draft.status == "uncertain")
      draftSaveStatus.layoutPriority(-1)
      Spacer(minLength: 8)
      ActionButton(title: scheduleTitle, icon: .clock, emphasis: .secondary, width: UILayout.pairedActionWidth,
        help: editingSendPlan == nil ? nil : "更改发送时间") { showSchedule.toggle() }
        .disabled(syncingDraft || importingAttachments || !editable)
        .cossPopover(isPresented: $showSchedule, radius: CossDatePickerLayout.radius) {
          VStack(alignment: .leading, spacing: 8) {
            SendScheduleForm(date: $sendDate)
            ActionButton(title: "确认时间", emphasis: .primary) {
              scheduledSend = true
              showSchedule = false
              confirmSend = true
            }.disabled(draft.to.isEmpty || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
          }.padding(CossDatePickerLayout.inset).frame(width: CossDatePickerLayout.width)
        }
      ActionButton(title: sending ? "发送中…" : "发送", icon: .send, emphasis: .primary,
        width: UILayout.pairedActionWidth) {
        scheduledSend = false
        confirmSend = true
      }.disabled(
        syncingDraft || importingAttachments || draft.status == "uncertain" || draft.to.isEmpty
          || store.accounts.first { $0.id == draft.accountId }?.isDemo == true)
    }.padding(.horizontal, 20).padding(.vertical, 10).background(Palette.chrome)
      .overlay(alignment: .top) { Rectangle().fill(Palette.softBorder).frame(height: 1) }
  }
  private var draftSaveMessage: String {
    if let saveError { return saveError }
    if saving { return "正在保存…" }
    if editingSendPlan != nil { return saved ? "草稿已保存 · 投递已暂停" : "投递已暂停" }
    return saved ? "草稿已保存" : "自动保存草稿"
  }
  private var draftSaveStatus: some View {
    Text(draftSaveMessage).font(UIType.small)
      .foregroundStyle(saveError == nil ? Palette.muted : Palette.destructive)
      .lineLimit(1).cossTooltip(draftSaveMessage)
  }
  private var accountSignature: String { store.signature(for: draft.accountId) }
  private var editable: Bool { draft.status == "draft" || editingSendPlan != nil }
  private var senderSelection: Binding<String> {
    Binding(get: { draft.accountId }, set: { accountId in
      draft.signatureStart = draft.signatureStart
        ?? MailSignature.trailingRange(in: draft.body, signature: accountSignature)?.location
      draft.accountId = accountId
    })
  }
  private var signature: String {
    if let range = MailSignature.trailingRange(in: draft.body, startingAt: draft.signatureStart) {
      return (draft.body as NSString).substring(with: range)
    }
    return accountSignature
  }
  private var editableBody: String { MailSignature.editableContent(in: draft.body, signature: signature) }
  private var writingScope: ComposerWritingScope {
    if richEditor.hasSelection { return .selection }
    if !editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .body }
    if draft.sourceMessageId != nil { return writingSession.referenceThread && draft.forwardedText == nil ? .thread : .source }
    return .new
  }

  private var writingAssistant: some View {
    ComposerWritingPopover(session: writingSession, writing: writing, store: store,
      scope: { writingScope }, allowsThreadReference: draft.forwardedText == nil,
      subject: draft.subject, matches: stillMatches, generate: { generate($0, language: $1) },
      adopt: adopt, close: { showingAssistant = false })
  }

  private func stillMatches(_ candidate: ComposerWritingCandidate) -> Bool {
    draft.id == candidate.draftId && draft.accountId == candidate.accountId
      && draft.sourceMessageId == candidate.sourceMessageId && draft.body == candidate.body
      && draft.richText == candidate.document && signature == candidate.signature
  }

  private func adopt(_ candidate: ComposerWritingCandidate, text: String) {
    guard stillMatches(candidate) else { return }
    writingSession.adopting = true
    writingSession.error = nil
    Task {
      defer { writingSession.adopting = false }
      do {
        if candidate.scope == .source || candidate.scope == .thread {
          let _: EmptyResponse = try await store.backend.request("/jobs/\(candidate.job.id)/validate-writing")
        }
        guard stillMatches(candidate), richEditor.adopt(text, expectedSource: candidate.body,
          selection: candidate.selection, preservingSignature: candidate.signature) else {
          writingSession.error = "正文或格式已变化，原草稿已保留。"
          return
        }
        if candidate.scope == .new && draft.subject.isEmpty { draft.subject = candidate.job.result?.subject ?? "" }
        writingSession.candidate = nil
        showingAssistant = false
        richEditor.focus()
      } catch { writingSession.error = error.localizedDescription }
    }
  }

  private func openWriting() {
    richEditor.focus()
    showingAssistant = true
  }

  private func closeComposer() async -> Bool {
    guard !closing && !sending && !importingAttachments else { return false }
    closing = true
    autosave?.cancel()
    defer { closing = false }
    do {
      if editingSendPlan != nil || store.drafts.contains(where: { $0.id == draft.id }) || draft != initial {
        try await persist(resumeSendPlan: editingSendPlan?.status == "waiting")
      }
      if store.destination == .drafts, store.accountId == initial.accountId, draft.accountId != initial.accountId {
        store.accountId = draft.accountId
      }
      if editingSendPlan != nil { await store.sendQueue.load() }
      dismiss()
      return true
    } catch {
      saveError = error.localizedDescription
      closeError = error.localizedDescription
      return false
    }
  }
  private var addressOptions: some View {
    CossMenu(title: "显示抄送或密送字段", width: 156) {
      CossMenuItem.command("抄送", mark: .checkbox(showingCC), enabled: draft.cc.isEmpty) { showingCC.toggle() }
      CossMenuItem.command("密送", mark: .checkbox(showingBCC), enabled: draft.bcc.isEmpty) { showingBCC.toggle() }
    } trigger: {
      CossMenuLabel(title: "抄送密送", size: .compact, color: Palette.muted)
    }.fixedSize()
  }
  private func bodyEditor(label: String, placeholder: String = "", editorHeight: CGFloat? = nil) -> some View {
    let panel = showingAssistant ? writingAssistant : nil
    return VStack(spacing: 0) {
      HStack(spacing: 4) {
        RichTextFormatBar(controller: richEditor, showingLink: $showingLink)
        Spacer(minLength: 0)
        ActionButton(title: "帮我写", icon: .pencilAi, emphasis: .secondary, size: .compact) {
          openWriting()
        }.accessibilityValue(showingAssistant ? "已展开" : "已收起")
          .cossPopover(isPresented: $showingAssistant, alignment: .trailing) { panel }
        if editingSendPlan == nil, store.accounts.first(where: { $0.id == draft.accountId })?.isDemo == false {
          ActionButton(title: syncingDraft ? "同步中…" : "同步草稿", icon: .refresh, size: .compact) {
            syncDraft()
          }.disabled(syncingDraft || store.busy.contains("sync"))
        }
        if saveError != nil {
          ActionButton(title: "另存草稿", icon: .copy, size: .compact, help: "另存为新草稿") { saveCopy() }
        }
      }.padding(.horizontal, 16).frame(height: 36).background(Palette.chrome)
      RichTextEditor(text: $draft.body, document: $draft.richText, controller: richEditor,
        placeholder: placeholder, accessibilityLabel: label, signature: accountSignature,
        signatureStart: $draft.signatureStart,
        onPaste: pasteAttachments, onWriting: openWriting, onLink: { showingLink = true })
        .frame(height: editorHeight).frame(minHeight: 110)
    }
  }
  private func saveCopy() {
    guard !saving, !sending, !closing else { return }
    autosave?.cancel()
    draft.id = UUID().uuidString
    draft.status = "draft"
    draft.revision = nil; draft.syncState = "local"; draft.syncError = nil; draft.conflictOf = nil
    editingSendPlan = nil
    store.composer = draft
    store.composerSendPlan = nil
    Task { do { try await persist() } catch { saveError = error.localizedDescription } }
  }
  private func syncDraft() {
    guard !syncingDraft, !saving, !sending, !closing else { return }
    autosave?.cancel(); syncingDraft = true
    let syncedID = draft.id, syncedAccount = draft.accountId
    Task {
      defer { syncingDraft = false }
      do {
        try await persist()
        guard draft.id == syncedID, draft.accountId == syncedAccount else { return }
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
        .inputPlaceholder("邮件主题", visible: text.wrappedValue.isEmpty)
    }.animation(UIMotion.feedback(reduceMotion), value: focusedAddress == title)
  }
  private func scheduleSave() {
    guard editable, !sending, !closing else { return }
    saved = false
    autosave?.cancel()
    autosave = Task {
      do {
        try await Task.sleep(for: .milliseconds(900))
        while saving { try await Task.sleep(for: .milliseconds(80)) }
        try Task.checkCancellation()
        autosave = nil
        try await persist()
      } catch is CancellationError {} catch { saveError = error.localizedDescription }
    }
  }
  private func persist(resumeSendPlan: Bool = false) async throws {
    guard editable else { return }
    while saving { try await Task.sleep(for: .milliseconds(80)) }
    saving = true
    defer { saving = false }
    let snapshot = draft
    var input = try jsonObject(snapshot)
    if let plan = editingSendPlan {
      input["sendPlanId"] = plan.id
      input["resumeSendPlan"] = resumeSendPlan
    }
    let result: MailDraft = try await store.backend.request("/drafts", method: "POST", body: input)
    saved = snapshot.hasSameContent(as: draft)
    saveError = nil
    if draft.id == snapshot.id {
      draft.revision = result.revision
      draft.syncState = result.syncState
      draft.syncError = result.syncError
      draft.conflictOf = result.conflictOf
    }
    if let index = store.drafts.firstIndex(where: { $0.id == result.id }) {
      store.drafts[index] = result.compact
    } else {
      store.drafts.append(result.compact)
    }
  }
  private var writingUnavailable: Bool {
    writing.isLoading || store.busy.contains("agent") || store.busy.contains("compose-ai")
  }

  private func generate(_ request: String, language: MailTranslationLanguage? = nil) {
    guard !writingUnavailable else { return }
    let scope = writingScope
    let selection = scope == .selection ? richEditor.rewriteSelection(preservingSignature: signature) : nil
    if scope == .selection && selection == nil {
      writingSession.error = "请选择签名以外的正文。"
      return
    }
    let draftSnapshot = draft
    let signature = signature
    let body = selection?.text ?? (scope == .body ? editableBody : "")
    let task = scope == .thread ? "conversationReply" : scope == .source ? "reply" : "compose"
    let outputLanguage = (language ?? writing.language)?.title ?? scope.automaticLanguage
    let style = writing.style
    writingSession.error = nil
    writingSession.candidate = nil
    writingSession.lastRequest = (request, language)
    store.busy.insert("compose-ai")
    Task {
      defer { store.busy.remove("compose-ai") }
      do {
        var source: MailMessage?
        if scope == .source || scope == .thread, let id = draftSnapshot.sourceMessageId {
          source = try await store.backend.request("/messages/\(id)")
          guard source?.accountId == draftSnapshot.accountId else { throw store.backend.failure("原邮件与发件账户不匹配。") }
        }
        let job = try await store.runWriting(task: task, accountId: draftSnapshot.accountId, message: source, prompt: request,
          body: body, tone: style.tone, length: style.length, outputLanguage: outputLanguage, writingStyle: style.instruction,
          writingScope: scope.rawValue, writingSubject: scope == .new ? draftSnapshot.subject : nil)
        writingSession.candidate = .init(job: job, scope: scope, draftId: draftSnapshot.id, accountId: draftSnapshot.accountId,
          body: draftSnapshot.body, signature: signature, sourceMessageId: draftSnapshot.sourceMessageId,
          document: draftSnapshot.richText, selection: selection)
      } catch { writingSession.error = error.localizedDescription }
    }
  }

  private func send() {
    guard !sending, !syncingDraft, !closing, !importingAttachments, editable else { return }
    sending = true
    autosave?.cancel()
    Task {
      defer { sending = false }
      do {
        try await persist()
        let date = scheduledSend ? sendDate : Date().addingTimeInterval(10)
        if let plan = editingSendPlan {
          try await store.sendQueue.change(plan, date: date)
        } else {
          let plan: SendPlan = try await store.backend.request("/send-plans", method: "POST",
            body: ["draftId": draft.id, "approved": true,
              "scheduledAt": ISO8601DateFormatter().string(from: date), "timeZone": TimeZone.current.identifier])
          store.sendQueue.record(plan)
        }
        if let index = store.drafts.firstIndex(where: { $0.id == draft.id }) {
          store.drafts[index].status = "queued"
        }
        store.accountId = draft.accountId
        store.navigate(.drafts)
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
    guard !sending, editable else { return false }
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
