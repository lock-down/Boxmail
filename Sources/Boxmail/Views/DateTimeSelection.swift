import BoxmailCore
import SwiftUI

struct DateTimeSelection: View {
  let title: String
  @Binding var date: Date
  var wholeHours = false
  private var day: Binding<Date?> {
    Binding(get: { date }, set: { value in
      guard let value else { return }
      if wholeHours {
        date = FollowUpHour.move(date, to: value)
        return
      }
      let time = Calendar.current.dateComponents([.hour, .minute], from: date)
      if let selected = Calendar.current.date(bySettingHour: time.hour ?? 0,
        minute: time.minute ?? 0, second: 0, of: value) { date = selected }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if wholeHours {
        HStack(alignment: .center, spacing: 16) {
          CalendarMonthView(title: title, selection: day)
          VStack(spacing: 8) {
            Text("整点").font(UIType.caption).foregroundStyle(Palette.muted)
            HourScrollPicker(title: title, date: $date)
          }
        }
        Divider().overlay(Palette.softBorder)
      } else {
        CalendarMonthView(title: title, selection: day)
        Divider().overlay(Palette.softBorder)
        HStack {
          Text("时间").font(UIType.body)
          Spacer()
          DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
            .datePickerStyle(.field).labelsHidden().font(UIType.body)
            .accessibilityLabel(title)
        }
      }
      HStack(spacing: 8) {
        ActionButton(title: wholeHours ? "下个整点" : "一小时后", emphasis: .secondary, size: .compact) {
          date = wholeHours ? FollowUpHour.next(after: .now) : Date().addingTimeInterval(3600)
        }
        ActionButton(title: wholeHours ? "明日同点" : "明天此时", emphasis: .secondary, size: .compact) {
          let reference = wholeHours ? date : Date()
          if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: reference) {
            date = wholeHours ? FollowUpHour.move(reference, to: tomorrow) : tomorrow
          }
        }
      }
      Text("\(date.formatted(date: .complete, time: .shortened)) · \(TimeZone.current.identifier)")
        .font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
    }
  }
}

struct FollowUpDateTimeField: View {
  let title: String
  @Binding var date: Date
  @ViewState<Bool> private var showingCalendar = false
  @ViewState<Date> private var selection = .now
  var body: some View {
    SearchDatePicker(title: title, value: .constant(date.formatted(date: .abbreviated, time: .shortened))) {
      selection = FollowUpHour.roundedUp(date)
      showingCalendar = true
    }.popover(isPresented: $showingCalendar) {
      VStack(alignment: .leading, spacing: 16) {
        Text(title).font(UIType.heading)
        DateTimeSelection(title: title, date: $selection, wholeHours: true)
        HStack {
          Spacer()
          ActionButton(title: "完成", emphasis: .primary) {
            date = selection
            showingCalendar = false
          }
        }
      }.padding(24).frame(width: 480).background(Palette.paper)
    }
  }
}
