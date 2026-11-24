import BoxmailCore
import SwiftUI

struct AssistantTurnView: View {
  @Bindable var store: MailStore
  let turn: AssistantTurn
  let busy: Bool
  let openMailSource: (String) -> Void
  let review: (AssistantAction) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      AssistantQuestionView(text: turn.prompt)
      AnalysisDocumentView(text: turn.text)
      if let coverage = turn.contextCoverage, coverage.partial {
        let unit = turn.scope.query?.folder == "drafts" ? "份草稿" : "封邮件"
        Text("本轮查阅 \(coverage.included) / \(coverage.total) \(unit)，部分资料未纳入。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
      if !turn.sources.isEmpty {
        AssistantSourcesView(store: store, turn: turn, openMailSource: openMailSource)
      }
      ForEach(turn.actions) { action in
        VStack(alignment: .leading, spacing: 12) {
          Text(AssistantPresentation.actionTitle(action)).font(.system(size: 13, weight: .medium))
          Text(
            action.messageIds.compactMap { id in turn.sources.first { $0.id == id }?.subject }
              .joined(separator: "、")
          )
          .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(2)
          ActionButton(
            title: action.status == "applied" ? "已采用" : "审阅动作", color: Palette.accent,
            emphasis: .tinted
          ) { review(action) }
          .disabled(action.status == "applied" || busy)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
          .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.radius))
      }
      CossSeparator()
    }
  }
}

struct AssistantQuestionView: View {
  let text: String
  var body: some View {
    HStack {
      Spacer(minLength: 32)
      Text(text).font(UIType.body).lineSpacing(5).textSelection(.enabled)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.radius))
        .frame(maxWidth: 640, alignment: .trailing)
    }.frame(maxWidth: .infinity)
  }
}
