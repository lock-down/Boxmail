import BoxmailCore
import SwiftUI

struct RuleAgentView: View {
  @Bindable var store: MailStore
  let policyChanged: () -> Void
  @Environment(\.dismiss) private var dismiss
  @FocusState private var composerFocused: Bool
  @ViewState private var accountID = ""
  @ViewState private var text = ""
  @ViewState private var messages: [Message] = []
  @ViewState private var draft: Answer?
  @ViewState private var labelPlan: LabelPlan?
  @ViewState private var requestID: String?
  @ViewState private var started: Date?
  @ViewState private var latestTrace: AIStreamOutput?
  @ViewState private var expandedThinking: Set<String> = []
  @ViewState private var saving = false
  @ViewState private var error: String?

  private static let composerToolbarInset: CGFloat = 8
  private static let composerToolbarRadius = UILayout.innerRadius(UILayout.cardRadius, inset: composerToolbarInset)

  private enum LabelMode: String, Decodable {
    case existing, automatic
    var title: String { self == .existing ? "使用现有标签" : "让 AI 创建标签" }
  }

  private struct LabelProposal: Decodable {
    let mode: LabelMode
    let accountId: String?
    let labelIds: [String]
  }

  private struct LabelPlan {
    let mode: LabelMode
    var accountId: String
    var labelIds: Set<String> = []
  }

  private struct Message: Identifiable {
    let id = UUID()
    let role, text: String
    var trace: AIStreamOutput? = nil
    var user: Bool { role == "user" }
  }

  private struct Answer: Decodable {
    let question, explanation: String?
    let rule: MailRule?
    let classification: LabelProposal?
    let total: Int?
    let samples: [Sample]?
    let trace: AIStreamOutput?

    struct Sample: Decodable, Identifiable {
      let id, subject, sender: String
    }
  }

  private var running: Bool { requestID != nil }
  private var currentOutput: AIStreamOutput? { requestID.flatMap { store.aiOutputs[$0] } }

  private var hasConversation: Bool { !messages.isEmpty || running || draft != nil || labelPlan != nil || error != nil }
  private var canSend: Bool { !saving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      header
      CossSeparator()
      if hasConversation {
        conversation
      } else {
        Spacer(minLength: 16)
        welcome
      }
      VStack(spacing: 12) {
        composer
        if !hasConversation { suggestions }
        Text("模型会收到对话、适用邮箱和标签名称。匹配样例在本机生成。")
          .font(UIType.small).foregroundStyle(Palette.muted)
          .frame(maxWidth: .infinity, alignment: hasConversation ? .leading : .center)
      }.padding(.horizontal, 24).padding(.vertical, 14)
        .frame(maxWidth: 640)
      if !hasConversation { Spacer(minLength: 16) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Palette.paper)
    .workspaceWindowSize(.agent)
    .interactiveDismissDisabled(saving)
    .onAppear {
      if !store.unifiedInbox { accountID = store.accountId }
      store.watchAIOutput()
    }
    .task(id: requestID) {
      if let id = requestID { await requestDraft(id) }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      AppicaIcon(.sparkles, size: 17).foregroundStyle(Palette.accent).accessibilityHidden(true)
      Text("整理助手").font(UIType.section).accessibilityAddTraits(.isHeader)
      Spacer()
      IconButton(icon: .x, help: "关闭整理助手") { dismiss() }
        .keyboardShortcut(.cancelAction).disabled(saving)
    }.padding(.horizontal, 20).frame(height: 52)
  }

  private var welcome: some View {
    VStack(spacing: 10) {
      AppicaIcon(.messageAi, size: 25).foregroundStyle(Palette.accent)
        .frame(width: 48, height: 48)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous))
        .accessibilityHidden(true)
      Text("想怎样整理邮件？").font(UIType.title).accessibilityAddTraits(.isHeader)
      Text("描述你的整理需求，或从下面的建议开始。")
        .font(UIType.body).foregroundStyle(Palette.muted)
    }.multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 8)
  }

  private var conversation: some View {
    ScrollViewReader { scroll in
      OverlayScrollView(followsContent: true) {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(messages) { message in
            if message.user {
              Text(message.text).font(UIType.body).lineSpacing(3).textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.chrome, in: RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous))
                .frame(maxWidth: 484, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("你，\(message.text)")
            } else {
              assistantTurn {
                if let trace = message.trace { activity(trace) }
                assistantText(message.text)
              }
            }
          }
          if let draft, let rule = draft.rule {
            assistantTurn {
              if let trace = draft.trace { activity(trace) }
              if let explanation = draft.explanation, !explanation.isEmpty { assistantText(explanation) }
              draftCard(rule, answer: draft).id(rule.id)
            }
          } else if running {
            let output = currentOutput ?? latestTrace
            assistantTurn {
              activity(output, started: started)
              if let partial = output?.text, !partial.isEmpty { assistantText(partial) }
            }
          }
          if let labelPlan {
            labelCard(labelPlan).padding(.leading, 36)
          }
          if let error {
            WorkflowNotice(text: error, icon: .infoCircle, color: Palette.destructive)
          }
          Color.clear.frame(height: 1).id("agent-end")
        }.padding(.horizontal, 24).padding(.vertical, 20)
          .frame(maxWidth: 640).frame(maxWidth: .infinity, alignment: .top)
      }
      .onChange(of: currentOutput) { _, output in
        if let output { latestTrace = output }
      }
      .onChange(of: requestID) { _, id in
        if id != nil { scroll.scrollTo("agent-end", anchor: .bottom) }
      }
      .onChange(of: labelPlan?.mode) { _, mode in
        if mode != nil { scroll.scrollTo("agent-end", anchor: .bottom) }
      }
    }.frame(maxHeight: .infinity)
  }

  private func activity(_ output: AIStreamOutput?, started: Date? = nil) -> some View {
    let id = output?.id ?? requestID
    return AgentActivityCard(output: output, started: started, showsThinking: Binding(
      get: { id.map { expandedThinking.contains($0) } ?? false },
      set: { expanded in
        guard let id else { return }
        if expanded { expandedThinking.insert(id) } else { expandedThinking.remove(id) }
      }
    ))
  }

  private func assistantTurn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 10) {
      AppicaIcon(.sparkles, size: 14).foregroundStyle(Palette.accent)
        .frame(width: 26, height: 26)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 10, content: content)
        .padding(.top, 4).frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func assistantText(_ text: String) -> some View {
    Text(text).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityLabel("Agent，\(text)")
  }

  private var suggestions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) { suggestionButtons }
      WrappingFlowLayout(spacing: 8) { suggestionButtons }
    }.frame(maxWidth: .infinity)
      .accessibilityElement(children: .contain).accessibilityLabel("对话建议")
  }

  @ViewBuilder private var suggestionButtons: some View {
    suggestion("现有标签", icon: .tag, help: LabelMode.existing.title) { suggestLabels(.existing) }
    suggestion("创建标签", icon: .wand, help: LabelMode.automatic.title) { suggestLabels(.automatic) }
    suggestion("起草规则", icon: .listCheck, help: "起草邮箱规则") {
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        text = "给收到的账单邮件加星标"
      }
      composerFocused = true
    }
  }

  private func suggestion(_ title: String, icon: AppicaGlyph, help: String, select: @escaping () -> Void) -> some View {
    ActionButton(title: title, icon: icon, emphasis: .secondary, help: help, action: select)
  }

  private var composer: some View {
    let shape = RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous)
    return VStack(alignment: .leading, spacing: 8) {
      TextField("", text: $text, axis: .vertical)
        .textFieldStyle(.plain).font(.system(size: 14)).lineLimit(1...5).focused($composerFocused)
        .accessibilityLabel("给整理助手发消息")
        .accessibilityHint("描述要整理的邮件和操作")
        .overlay(alignment: .topLeading) {
          if text.isEmpty {
            Text("整理要求").font(.system(size: 14)).foregroundStyle(Palette.muted)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }.padding(.horizontal, Self.composerToolbarInset + UIControlSize.compact.horizontalInset).padding(.top, 12)
      HStack(spacing: 8) {
        scopeMenu
        Spacer(minLength: 4)
        if running {
          composerAction("停止生成", icon: .square, enabled: true, action: stop)
        } else {
          composerAction("发送", icon: .arrowUp, shortcut: "⌘↵", enabled: canSend, action: send)
            .keyboardShortcut(.return, modifiers: .command)
        }
      }.padding(.horizontal, Self.composerToolbarInset).padding(.bottom, Self.composerToolbarInset)
    }
    .background(Palette.canvas, in: shape)
    .overlay { shape.strokeBorder(composerFocused ? Palette.accent.opacity(0.72) : Palette.border).allowsHitTesting(false) }
  }

  private var scopeMenu: some View {
    let scope = store.accounts.first { $0.id == accountID }?.email ?? "所有账户"
    return CossMenu(title: "对话使用的邮箱", value: scope, width: 244, prefersSelection: true,
      corner: Self.composerToolbarRadius) {
      CossMenuItem.command("所有账户", mark: .choice(accountID.isEmpty)) { accountID = "" }
      for account in store.accounts {
        CossMenuItem.command(account.email, mark: .choice(accountID == account.id)) { accountID = account.id }
      }
    } trigger: {
      CossMenuLabel(title: scope, icon: .inbox, size: .compact, color: Palette.muted)
    }.frame(maxWidth: 244, alignment: .leading).disabled(running || saving)
  }

  private func composerAction(
    _ title: String, icon: AppicaGlyph, shortcut: String? = nil, enabled: Bool, action: @escaping () -> Void
  ) -> some View {
    let corner = Self.composerToolbarRadius
    return Button(action: action) {
      HStack(spacing: 8) {
        if let shortcut {
          Text(shortcut).font(UIType.small.weight(.medium)).accessibilityHidden(true)
        }
        AppicaIcon(icon, size: UILayout.compactIconSize).accessibilityHidden(true)
      }.foregroundStyle(enabled ? Palette.primaryForeground : Palette.muted)
        .controlLabel(size: .regular, horizontalInset: Self.composerToolbarInset)
        .background(enabled ? Palette.primary : Palette.selected,
          in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }.buttonStyle(ControlFeedback(corner: corner)).controlFocus(corner: corner).disabled(!enabled)
      .accessibilityLabel(Text(title)).help(title)
  }

  private func labelCard(_ plan: LabelPlan) -> some View {
    let chosen = store.mailLabels.filter { plan.labelIds.contains($0.id) }
    return AgentApprovalCard(title: plan.mode.title, icon: plan.mode == .existing ? .tag : .wand) {
      WorkflowField(title: "适用邮箱") {
        WorkflowSelection(title: "应用标签设置的邮箱", selection: Binding(get: { plan.accountId }, set: { id in
          labelPlan?.accountId = id
        }), options: [("", "选择邮箱")] + store.accounts.map { ($0.id, $0.email) })
      }
      if plan.mode == .existing {
        WorkflowField(title: "可用标签", detail: "已选 \(chosen.count) 个") {
          if store.mailLabels.isEmpty {
            Text("还没有可选标签。可以告诉 Agent 按内容创建标签。")
              .font(UIType.caption).foregroundStyle(Palette.muted)
          }
          WrappingFlowLayout(spacing: 6) {
            ForEach(store.mailLabels) { label in
              let selected = plan.labelIds.contains(label.id)
              let shape = RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous)
              Button {
                if selected { labelPlan?.labelIds.remove(label.id) } else { labelPlan?.labelIds.insert(label.id) }
              } label: {
                HStack(spacing: 6) {
                  Circle().fill(store.categoryTone(label.name).swatch).frame(width: 7, height: 7)
                  Text(label.name).font(UIType.caption)
                  AppicaIcon(.check, size: 12).opacity(selected ? 1 : 0).accessibilityHidden(true)
                }.controlLabel(size: .compact)
                  .background(selected ? Palette.accentSoft : Palette.paper, in: shape)
                  .overlay { shape.strokeBorder(selected ? Palette.accent : Palette.border).allowsHitTesting(false) }
              }.buttonStyle(ControlFeedback(selected: selected)).controlFocus()
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
          }
        }
      }
      Text("此设置在所选邮箱整理邮件时生效。").font(UIType.small).foregroundStyle(Palette.muted)
    } actions: {
      ActionButton(title: "取消", width: UILayout.pairedActionWidth) { labelPlan = nil; error = nil }
      ActionButton(title: saving ? "保存中…" : "保存设置", emphasis: .primary,
        width: UILayout.pairedActionWidth) { saveLabels(plan, labels: chosen) }
        .disabled(plan.accountId.isEmpty || (plan.mode == .existing && chosen.isEmpty))
    }.disabled(saving || running)
  }

  private func draftCard(_ rule: MailRule, answer: Answer) -> some View {
    let account = store.accounts.first { $0.id == rule.query.accountId }?.email ?? "所有账户"
    let folder = rule.query.folder == "all" ? "所有文件夹" : MailDestination(rawValue: rule.query.folder)?.title ?? rule.query.folder
    return AgentApprovalCard(title: rule.name, icon: .listCheck) {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
        ruleField("范围", "\(account) · \(folder) · \(rule.query.filter)")
        if !rule.query.query.isEmpty { ruleField("条件", rule.query.query) }
        if let category = rule.query.category { ruleField("现有分类", category) }
        ruleField("动作", rule.actions.description)
        ruleField("运行方式", rule.automatic ? "收到新邮件时运行" : "用户确认后运行")
      }.font(UIType.caption)
      CossSeparator()
      Text("本机匹配 \(answer.total ?? 0) 封邮件").font(UIType.caption.weight(.semibold)).monospacedDigit()
      ForEach(answer.samples ?? []) { sample in
        HStack(alignment: .top, spacing: 8) {
          AppicaIcon(.mail, size: 14).foregroundStyle(Palette.muted).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 3) {
            Text(sample.subject.isEmpty ? "无主题" : sample.subject).font(UIType.caption)
            Text(sample.sender).font(UIType.small).foregroundStyle(Palette.muted)
          }
        }
      }
    } actions: {
      ActionButton(title: saving ? "创建中…" : "创建规则", emphasis: .primary) { saveRule(rule, trace: answer.trace) }
        .disabled(saving || running)
    }
  }

  private func ruleField(_ label: String, _ value: String) -> some View {
    GridRow(alignment: .top) {
      Text(label).foregroundStyle(Palette.muted).fixedSize()
      Text(value).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
  }

  private func suggestLabels(_ mode: LabelMode) {
    error = nil
    messages.append(.init(role: "user", text: mode.title))
    messages.append(.init(role: "assistant", text: mode == .existing
      ? "选择邮箱和可用标签，我会按邮件内容从中匹配。" : "我会先查找同义标签，需要新分类时再创建。请选择适用邮箱。"))
    labelPlan = .init(mode: mode, accountId: accountID)
  }

  private func send() {
    let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !running, !saving, !message.isEmpty else { return }
    if let response = draft, let rule = response.rule {
      let scope = [rule.name, rule.query.folder, rule.query.query, rule.actions.description].joined(separator: " · ")
      messages.append(.init(role: "assistant", text: scope, trace: response.trace))
    }
    if let plan = labelPlan {
      let selected = store.mailLabels.filter { plan.labelIds.contains($0.id) }.map(\.name)
      let account = store.accounts.first { $0.id == plan.accountId }?.email ?? "尚未指定邮箱"
      messages.append(.init(role: "assistant", text: ([plan.mode.title, account] + selected).joined(separator: " · ")))
    }
    messages.append(.init(role: "user", text: message))
    draft = nil; labelPlan = nil; text = ""; latestTrace = nil; error = nil
    started = Date()
    requestID = UUID().uuidString.lowercased()
  }

  private func stop() {
    requestID = nil
    started = nil
    latestTrace = nil
    if let prompt = messages.popLast() { text = [prompt.text, text].filter { !$0.isEmpty }.joined(separator: "\n") }
  }

  private func requestDraft(_ id: String) async {
    defer {
      if requestID == id { requestID = nil; started = nil }
    }
    let input: [String: Any] = ["messages": messages.map { ["role": $0.role, "text": $0.text] },
      "accountId": accountID.isEmpty ? NSNull() as Any : accountID, "requestId": id, "lockAccount": true]
    do {
      let reply: Answer = try await store.backend.request("/mail-rules/agent-draft", method: "POST", body: input, timeout: 610)
      guard !Task.isCancelled, requestID == id else { return }
      latestTrace = nil
      if let question = reply.question {
        messages.append(.init(role: "assistant", text: question, trace: reply.trace))
      } else if let proposal = reply.classification {
        messages.append(.init(role: "assistant", text: reply.explanation ?? proposal.mode.title, trace: reply.trace))
        labelPlan = .init(mode: proposal.mode, accountId: proposal.accountId ?? "", labelIds: Set(proposal.labelIds))
      } else { draft = reply }
    } catch {
      if !Task.isCancelled, requestID == id {
        self.error = error.localizedDescription
        if let prompt = messages.popLast() { text = [prompt.text, text].filter { !$0.isEmpty }.joined(separator: "\n") }
      }
    }
  }

  private func saveRule(_ rule: MailRule, trace: AIStreamOutput?) {
    saving = true; error = nil
    Task {
      defer { saving = false }
      if await store.rules.confirmAgentDraft(rule) {
        draft = nil
        messages.append(.init(role: "assistant", text: "已创建邮箱规则「\(rule.name)」。", trace: trace))
      } else { error = store.rules.error }
    }
  }

  private func saveLabels(_ plan: LabelPlan, labels: [MailCategory]) {
    saving = true; error = nil
    Task {
      defer { saving = false }
      do {
        _ = try await store.saveOrganizationPolicy(["accountId": plan.accountId, "confirmed": true,
          "classification": ["mode": plan.mode.rawValue, "labelIds": plan.mode == .existing ? labels.map(\.id) : []]])
        policyChanged()
        let email = store.accounts.first { $0.id == plan.accountId }?.email ?? "所选邮箱"
        labelPlan = nil
        messages.append(.init(role: "assistant", text: "已为 \(email) 保存「\(plan.mode.title)」。"))
      } catch { self.error = error.localizedDescription }
    }
  }
}

private struct AgentApprovalCard<Content: View, Actions: View>: View {
  let title: String
  let icon: AppicaGlyph
  @ViewBuilder var content: () -> Content
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: UILayout.cardRadius, style: .continuous)
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        AppicaIcon(icon, size: 16).foregroundStyle(Palette.accent).accessibilityHidden(true)
        Text(title).font(UIType.section).accessibilityAddTraits(.isHeader)
      }.padding(14)
      CossSeparator()
      VStack(alignment: .leading, spacing: 12, content: content)
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
      CossSeparator()
      HStack(spacing: 8) {
        Spacer()
        actions()
      }.padding(.horizontal, 12).padding(.vertical, 8).background(Palette.canvas)
    }.background(Palette.paper, in: shape).clipShape(shape)
      .overlay { shape.strokeBorder(Palette.border).allowsHitTesting(false) }
  }
}
