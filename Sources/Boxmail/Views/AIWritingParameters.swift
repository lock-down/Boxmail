import SwiftUI

/// Selecting writing parameters never starts a model request.
struct AIWritingParameters: View {
  @Binding var tone: String
  @Binding var length: String
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("语气").font(UIType.small).foregroundStyle(Palette.muted)
      FilterBar(values: ["正式", "亲切", "简洁", "专业"], selection: $tone, compact: true)
      Text("长度").font(UIType.small).foregroundStyle(Palette.muted)
      FilterBar(values: ["简短", "适中", "详细"], selection: $length, compact: true)
    }
  }
}
