import BoxmailCore
import SwiftUI

struct AIStreamingView: View {
  let output: AIStreamOutput
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if output.status == "running" {
        HStack(spacing: 8) {
          ProgressView().controlSize(.mini)
          Text(output.stage ?? "正在生成…").font(UIType.small).foregroundStyle(Palette.muted)
        }
      }
      if !output.text.isEmpty {
        AnalysisDocumentView(text: output.text)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}
