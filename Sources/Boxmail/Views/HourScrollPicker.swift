import BoxmailCore
import SwiftUI

struct HourScrollPicker: View {
  let title: String
  @Binding var date: Date
  @ViewState<Int?> private var centeredHour = nil
  @ViewState<Int?> private var requestedHour = nil
  @Namespace private var viewport
  private let rowHeight: CGFloat = 28
  private var hour: Int { Calendar.current.component(.hour, from: date) }

  init(title: String, date: Binding<Date>) {
    self.title = title
    self._date = date
    self._requestedHour = ViewState(wrappedValue: Calendar.current.component(.hour, from: date.wrappedValue))
  }

  var body: some View {
    let choices = FollowUpHour.hours(on: date)
    ScrollViewReader { reader in
      ScrollView(.vertical) {
        VStack(spacing: 0) {
          ForEach(choices, id: \.self) { choice in
            Button { select(choice) } label: {
              Text(String(format: "%02d:00", choice))
                .font(.system(size: 13, weight: choice == hour ? .semibold : .regular))
                .monospacedDigit().foregroundStyle(choice == hour ? Palette.blue : Palette.muted)
                .frame(maxWidth: .infinity).frame(height: rowHeight).contentShape(Rectangle())
            }.buttonStyle(ControlFeedback(selected: choice == hour)).controlFocus()
              .accessibilityAddTraits(choice == hour ? .isSelected : []).id(choice)
          }
        }.scrollTargetLayout()
          .onGeometryChange(for: Int.self) { [viewport, rowHeight] geometry in
            Int(((rowHeight - geometry.frame(in: .named(viewport)).minY) / rowHeight).rounded())
          } action: { index in
            guard let first = choices.first, let last = choices.last else { return }
            let choice = index < 0 ? first : index >= choices.count ? last : choices[index]
            centeredHour = choice
            if let requestedHour {
              if requestedHour == choice { self.requestedHour = nil }
            } else if choice != hour {
              select(choice)
            }
          }
      }.coordinateSpace(name: viewport)
        .contentMargins(.vertical, rowHeight, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .onAppear { reader.scrollTo(hour, anchor: .center) }
        .onChange(of: hour) { _, value in
          guard centeredHour != value else { return }
          requestedHour = value
          reader.scrollTo(value, anchor: .center)
        }
    }.frame(width: 104, height: rowHeight * 3)
      .background {
        RoundedRectangle(cornerRadius: UILayout.controlRadius).fill(Palette.blueSoft)
          .frame(height: rowHeight).padding(.horizontal, 3)
      }
      .overlay { RoundedRectangle(cornerRadius: UILayout.controlRadius).strokeBorder(Palette.softBorder) }
      .accessibilityElement(children: .contain).accessibilityLabel(title + "整点选择")
  }

  private func select(_ value: Int) {
    if let selection = FollowUpHour.time(on: date, hour: value) {
      date = selection
    }
  }
}
