import SwiftUI

struct SettingsActionFeedback: View {
  let action: SettingsActionState

  var body: some View {
    if action.isWorking {
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        if let progress = action.progress {
          Text(progress).font(UIType.small).foregroundStyle(Palette.muted)
        }
      }
    } else if let feedback = action.feedback {
      switch feedback {
      case .success(let text):
        WorkflowNotice(text: text, icon: "checkmark.circle", color: Palette.success)
      case .failure(let text):
        WorkflowNotice(text: text, icon: "exclamationmark.circle", color: Palette.amber)
      }
    }
  }
}
