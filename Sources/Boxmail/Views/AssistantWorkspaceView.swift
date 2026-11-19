import BoxmailCore
import SwiftUI

struct AssistantWorkspaceView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: AssistantWorkspaceStore
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
      Divider().overlay(Palette.softBorder)
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
          icon: "text.bubble")
      }
      VStack(alignment: .leading, spacing: 8) {
        if let error = workspace.error {
          WorkflowNotice(text: error, color: error == "已停止回答" ? Palette.muted : Palette.amber)
        }
        if !store.settings.ai.enabled {
          ActionButton(title: "在设置中启用 AI", icon: "gearshape", color: Palette.blue, size: .compact) {
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
    .confirmationDialog(
      "确认采用建议？",
      isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
      titleVisibility: .visible
    ) {
      if let action = pendingAction, let turn = pendingTurn {
        Button("确认\(AssistantPresentation.actionTitle(action))") {
          Task {
            await workspace.apply(action, turn: turn)
            try? await store.refresh()
            pendingAction = nil
          }
        }
      }
      Button("取消", role: .cancel) { pendingAction = nil }
    } message: {
      Text(pendingAction.map(AssistantPresentation.actionTitle) ?? "")
    }
  }

  private var toolbar: some View {
    HStack(spacing: 4) {
      Label("邮件助手", systemImage: "text.bubble").font(UIType.section)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: 8)
      IconButton(icon: "plus", help: "新建问答", size: 24) { workspace.begin() }
        .disabled(workspace.busy)
      IconMenu(icon: "clock", help: "历史问答") {
        ForEach(history) { session in
          if let question = session.turns.first?.prompt {
            Button(menuTitle(question)) { workspace.select(session) }
          }
        }
      }.disabled(workspace.busy || history.isEmpty)
      IconButton(icon: "sidebar.right", help: "收起邮件助手", size: 24) {
        workspace.isPresented = false
      }
    }.padding(.horizontal, 12).frame(height: 36).background(Palette.chrome)
  }

  private var scopeBar: some View {
    HStack(spacing: 8) {
      Menu {
        ForEach(MailStore.assistantFolders) { folder in
          let selection = store.assistantScope(for: folder)
          Button {
            if scope != selection { workspace.begin(scope: selection) }
          } label: {
            if scope == selection { Label(folder.title, systemImage: "checkmark") }
            else { Text(folder.title) }
          }
        }
      } label: {
        Label {
          Text(scopeTitle).lineLimit(1).truncationMode(.middle)
        } icon: {
          Image(systemName: scope.kind == "attachments" ? "paperclip" : "folder")
        }
      }.menuStyle(.borderlessButton).frame(height: 30)
        .help(AssistantPresentation.scopeHelp(scope, store: store))
        .accessibilityLabel("选择文件夹")
        .accessibilityValue(scopeTitle)
        .disabled(workspace.busy)
      Spacer(minLength: 0)
    }.font(UIType.caption).foregroundStyle(Palette.muted)
      .padding(.horizontal, 12).padding(.vertical, 3).background(Palette.canvas)
      .overlay(alignment: .bottom) { Divider().overlay(Palette.softBorder) }
  }
}
