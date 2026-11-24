import BoxmailCore
import SwiftUI

struct CossDateTrigger: View {
  let title: String
  let value: String
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      CossMenuLabel(title: value.isEmpty ? "选择日期" : value, icon: .calendarLine, size: .form,
        fillsWidth: true, color: value.isEmpty ? Palette.muted : Palette.ink)
    }.buttonStyle(ControlFeedback(emphasis: .secondary)).controlFocus().accessibilityLabel(title)
      .accessibilityValue(value.isEmpty ? "未选择日期" : value)
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
      .cossPopover(isPresented: $isOpen) {
        VStack(spacing: 12) {
          CalendarMonthView(title: title, selection: date) { isOpen = false }
          CossSeparator()
          HStack {
            ActionButton(title: "清除日期") { value = ""; isOpen = false }.disabled(value.isEmpty)
            Spacer()
            ActionButton(title: "今天", emphasis: .secondary) {
              value = MailSearchCalendar.value(.now)
              isOpen = false
            }
          }
        }.padding(16).frame(width: 300)
      }
  }
}
