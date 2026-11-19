import BoxmailCore
import SwiftUI

struct AssistantTranscriptView: View {
  @Bindable var store: MailStore
  @Bindable var workspace: AssistantWorkspaceStore
  let openMailSource: (String) -> Void
  let review: (AssistantTurn, AssistantAction) -> Void
  private var answering: Bool { !workspace.pendingPrompt.isEmpty }
  private var output: AIStreamOutput? {
    guard let id = workspace.session?.id else { return nil }
    return store.aiOutputs["assistant-\(id)"]
  }

  var body: some View {
    ScrollViewReader { scroll in
      OverlayScrollView(scrollPosition: workspace.scrollPosition, followsContent: true) {
        LazyVStack(alignment: .leading, spacing: 16) {
          ForEach(workspace.session?.turns ?? []) { turn in
            AssistantTurnView(store: store, turn: turn, busy: workspace.busy, openMailSource: openMailSource) {
              review(turn, $0)
            }
          }
          if answering {
            AssistantQuestionView(text: workspace.pendingPrompt)
            if let output { AIStreamingView(output: output) }
            else {
              HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("正在查阅邮件与附件…").font(UIType.small).foregroundStyle(Palette.muted)
              }
            }
          }
          Color.clear.frame(height: 1).id("latest-answer")
        }.padding(.vertical, 8).padding(.trailing, 4)
      }.onChange(of: workspace.pendingPrompt) { _, value in
        if !value.isEmpty { scroll.scrollTo("latest-answer", anchor: .bottom) }
      }
    }.id(workspace.session?.id)
  }
}
