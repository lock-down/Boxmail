import BoxmailCore
import SwiftUI

struct SearchDatePicker: View {
  let title: String
  @Binding var value: String
  let open: () -> Void
  var body: some View {
    Button(action: open) {
      HStack(spacing: 8) {
        Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(Palette.muted)
        Text(value.isEmpty ? "选择日期" : value).font(UIType.body)
          .foregroundStyle(value.isEmpty ? Palette.muted : Palette.ink)
        Spacer(minLength: 0)
        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(Palette.muted)
      }.padding(.horizontal, 10).frame(height: 32)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
    }.buttonStyle(ControlFeedback()).controlFocus().accessibilityLabel(title)
      .accessibilityValue(value.isEmpty ? "未选择日期" : value)

  }
}

struct SearchCalendarPanel: View {
  let title: String
  @Binding var selection: String
  let close: () -> Void

  private var date: Binding<Date?> {
    Binding(get: { MailSearchCalendar.parse(selection) }, set: {
      selection = $0.map { MailSearchCalendar.value($0) } ?? ""
    })
  }
  var body: some View {
    VStack(spacing: 12) {
      CalendarMonthView(title: title, selection: date, choose: close)
      Divider().overlay(Palette.softBorder)
      HStack {
        ActionButton(title: "清除日期") { selection = ""; close() }.disabled(selection.isEmpty)
        Spacer()
        ActionButton(title: "今天", color: Palette.blue) { selection = MailSearchCalendar.value(.now); close() }
      }
    }.onExitCommand { close() }
  }
}
