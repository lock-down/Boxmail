import SwiftUI

struct CossProgressStyle: ProgressViewStyle {
  func makeBody(configuration: Configuration) -> some View {
    let fraction = configuration.fractionCompleted ?? 0
    VStack(alignment: .leading, spacing: 6) {
      configuration.label
      GeometryReader { geometry in
        Capsule().fill(Palette.selected).overlay(alignment: .leading) {
          Capsule().fill(Palette.primary).frame(width: geometry.size.width * fraction)
        }
      }.frame(height: 6)
      configuration.currentValueLabel
    }.accessibilityRepresentation {
      ProgressView(value: fraction) { configuration.label }
        .progressViewStyle(.linear).accessibilityLabel("完成进度")
    }
  }
}
