import BoxmailCore
import SwiftUI

enum CossDatePickerLayout {
  static let cell: CGFloat = 36
  static let inset: CGFloat = 8
  static let radius = UILayout.fieldRadius + inset
  static let width = cell * 7 + inset * 2
}

struct CossDateTrigger: View {
  let title: String
  let value: String
  var icon: AppicaGlyph = .calendar
  var fillsWidth = true
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      CossDateTriggerLabel(value: value.isEmpty ? "选择日期" : value, icon: icon, fillsWidth: fillsWidth)
    }.buttonStyle(ControlFeedback()).controlFocus().accessibilityLabel(title)
      .accessibilityValue(value.isEmpty ? "未选择日期" : value == title ? "" : value)
  }
}

struct CossDateTriggerLabel: View {
  let value: String
  let icon: AppicaGlyph
  var fillsWidth = true

  var body: some View {
    HStack(spacing: 8) {
      AppicaIcon(icon, size: UILayout.compactIconSize).foregroundStyle(Palette.muted).accessibilityHidden(true)
      Text(value).lineLimit(1).monospacedDigit()
    }.font(UIControlSize.form.font)
      .controlLabel(size: .form, fillsWidth: fillsWidth, alignment: .leading)
      .controlFieldSurface(focused: false, fill: Palette.canvas, radius: UILayout.controlRadius)
  }
}

struct CossDatePicker: View {
  let title: String
  @Binding var value: String
  @ViewState private var isOpen = false

  private var date: Binding<Date?> {
    Binding(get: { MailSearchCalendar.parse(value) }, set: {
      value = $0.map { MailSearchCalendar.value($0) } ?? ""
    })
  }

  var body: some View {
    CossDateTrigger(title: title, value: value) { isOpen.toggle() }
      .cossPopover(isPresented: $isOpen, radius: CossDatePickerLayout.radius) {
        VStack(spacing: 8) {
          CalendarMonthView(title: title, selection: date) { isOpen = false }
          CossSeparator()
          HStack {
            ActionButton(title: "清除日期", width: UILayout.pairedActionWidth) {
              value = ""
              isOpen = false
            }.disabled(value.isEmpty)
            Spacer()
            ActionButton(title: "今天", emphasis: .secondary, width: UILayout.pairedActionWidth) {
              value = MailSearchCalendar.value(.now)
              isOpen = false
            }
          }
        }.padding(CossDatePickerLayout.inset).frame(width: CossDatePickerLayout.width)
      }
  }
}
