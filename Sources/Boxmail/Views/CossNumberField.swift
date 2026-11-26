import SwiftUI

struct CossNumberField: View {
  let title: String
  @Binding var value: Int
  let range: ClosedRange<Int>
  var digits = 1
  @ViewState private var draft: String?
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 0) {
      stepButton(.minus, label: "减少" + title, offset: -1)
        .disabled(value <= range.lowerBound)
      TextField("", text: input)
        .textFieldStyle(.plain).font(UIControlSize.form.font)
        .monospacedDigit().multilineTextAlignment(.center)
        .frame(minWidth: 30, maxWidth: .infinity)
        .focused($focused).accessibilityLabel(title)
        .onSubmit { draft = nil }
        .onKeyPress(.upArrow) { step(1); return .handled }
        .onKeyPress(.downArrow) { step(-1); return .handled }
      stepButton(.plus, label: "增加" + title, offset: 1)
        .disabled(value >= range.upperBound)
    }.padding(.horizontal, 3).frame(height: UIControlSize.form.height)
      .controlFieldSurface(focused: focused)
      .onChange(of: focused) { _, editing in if !editing { draft = nil } }
      .onChange(of: value) { _, value in
        if let draft, Int(draft) != value { self.draft = nil }
      }
  }

  private var input: Binding<String> {
    Binding(get: { draft ?? String(format: "%0*d", digits, value) }, set: { text in
      let digits = text.filter { $0.isASCII && $0.isNumber }
      draft = digits
      if let number = Int(digits), range.contains(number) { value = number }
    })
  }

  private func stepButton(_ icon: AppicaGlyph, label: String, offset: Int) -> some View {
    IconButton(icon: icon, help: label, size: UIControlSize.compact.height) { step(offset) }
  }

  private func step(_ offset: Int) {
    draft = nil
    value = min(range.upperBound, max(range.lowerBound, value + offset))
  }
}
