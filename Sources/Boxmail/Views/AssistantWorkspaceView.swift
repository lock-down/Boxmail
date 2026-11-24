import BoxmailCore
import SwiftUI

struct AssistantWorkspaceView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: AssistantWorkspaceStore
  var dismissOnEscape = false
  let openMailSource: (String) -> Void
  @ViewState private var pendingAction: AssistantAction?
  @ViewState private var pendingTurn: AssistantTurn?

  private var scope: AssistantScope {
    workspace.session?.scope ?? workspace.pendingScope ?? store.suggestedAssistantScope
  }
  private var scopeTitle: String { AssistantPresentation.scopeTitle(scope, store: store) }
  private var history: [AssistantSession] { workspace.sessions.reversed().filter { !$0.turns.isEmpty } }
  private var showTranscript: Bool {
    workspace.session?.turns.isEmpty == false || !workspace.pendingPrompt.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      CossSeparator()
      scopeBar
      if showTranscript {
        AssistantTranscriptView(store: store, workspace: workspace, openMailSource: openMailSource) { turn, action in
          pendingTurn = turn
          pendingAction = action
        }.padding(.horizontal, 14)
      } else {
        EmptyState(title: "想了解什么？",
          subtitle: scope.kind == "attachments" ? "输入要比较的内容，例如版本差异或金额变化。"
            : "直接提问，助手会在当前范围查找相关邮件。",
          icon: .chatAiLine)
      }
      VStack(alignment: .leading, spacing: 8) {
        if let error = workspace.error {
          WorkflowNotice(text: error, color: error == "已停止回答" ? Palette.muted : Palette.amber)
        }
        if !store.settings.ai.enabled {
          ActionButton(title: "在设置中启用 AI", icon: .settings3Line, color: Palette.accent, size: .compact) {
            store.settingsTab = "AI 助手"
            store.showSettings = true
          }
        }
        AssistantComposerView(workspace: workspace, scope: scope, canSubmit: store.settings.ai.enabled)
      }.padding(12)
    }
    .frame(maxHeight: .infinity).background(Palette.paper)
    .accessibilityElement(children: .contain)
    .task { await workspace.load() }
    .cossAlert(
      "确认采用建议？",
      isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
      presenting: pendingAction
    ) { action in
      CossAlertAction("取消", role: .cancel)
      if let turn = pendingTurn {
        CossAlertAction("确认采用") {
          Task {
            await workspace.apply(action, turn: turn)
            try? await store.refresh()
          }
        }
      }
    } message: { action in
      Text(AssistantPresentation.actionTitle(action))
    }
  }

  private var toolbar: some View {
    HStack(spacing: 4) {
      Label("邮件助手", icon: .chatAiLine).font(UIType.section)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      IconButton(icon: .addLine, help: "新建问答", size: 24) { workspace.begin() }
        .disabled(workspace.busy)
      IconMenu(icon: .timeLine, help: "历史问答") {
        for session in history {
          if let question = session.turns.first?.prompt {
            CossMenuItem.command(question, icon: .chatAiLine) { workspace.select(session) }
          }
        }
      }.disabled(workspace.busy || history.isEmpty)
      IconButton(icon: .closeLine, help: "收起邮件助手", size: 28) {
        workspace.isPresented = false
      }.keyboardShortcut(dismissOnEscape ? .cancelAction : nil)
    }.padding(.horizontal, 14).frame(height: 44).background(Palette.canvas)
  }

  private var scopeBar: some View {
    HStack(spacing: 8) {
      CossMenu(title: "选择文件夹", value: scopeTitle, prefersSelection: true) {
        for folder in MailStore.assistantFolders {
          let selection = store.assistantScope(for: folder)
          CossMenuItem.command(folder.title, mark: .choice(scope == selection)) {
            if scope != selection { workspace.begin(scope: selection) }
          }
        }
      } trigger: {
        CossMenuLabel(title: scopeTitle, icon: scope.kind == "attachments" ? .attachment2 : .folderLine,
          size: .compact, color: Palette.muted)
      }.frame(height: 30)
        .cossTooltip(AssistantPresentation.scopeHelp(scope, store: store))
        .accessibilityLabel("选择文件夹")
        .accessibilityValue(scopeTitle)
        .disabled(workspace.busy)
      Spacer(minLength: 0)
    }.font(UIType.caption).foregroundStyle(Palette.muted)
      .padding(.horizontal, 12).padding(.vertical, 3).background(Palette.canvas)
      .overlay(alignment: .bottom) { CossSeparator() }
  }
}
