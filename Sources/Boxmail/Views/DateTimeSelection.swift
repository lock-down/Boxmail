import BoxmailCore
import SwiftUI

private let pickerDateTimeFormat = Date.FormatStyle(date: .numeric, time: .shortened)
  .locale(Locale(identifier: "zh_CN"))
  .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

struct DateTimeSelection: View {
  let title: String
  @Binding var date: Date
  var wholeHours = false
  private var calendar: Calendar { .current }
  private var day: Binding<Date?> {
    Binding(get: { date }, set: { value in
      guard let value else { return }
      if wholeHours {
        date = FollowUpHour.move(date, to: value)
        return
      }
      let time = calendar.dateComponents([.hour, .minute], from: date)
      if let selected = calendar.date(bySettingHour: time.hour ?? 0,
        minute: time.minute ?? 0, second: 0, of: value) { date = selected }
    })
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CalendarMonthView(title: title, selection: day).frame(maxWidth: .infinity)
      CossSeparator()
      if wholeHours {
        let selectedHour = calendar.component(.hour, from: date)
        let value = String(format: "%02d:00", selectedHour)
        CossMenu(title: title + "整点", value: value, prefersSelection: true) {
          for hour in FollowUpHour.hours(on: date, calendar: calendar) {
            CossMenuItem.command(String(format: "%02d:00", hour), mark: .choice(hour == selectedHour)) {
              if let selected = FollowUpHour.time(on: date, hour: hour, calendar: calendar) {
                date = selected
              }
            }
          }
        } trigger: {
          CossDateTriggerLabel(value: value, icon: .clock)
        }
      } else {
        HStack(spacing: 8) {
          timeField("小时", component: .hour, options: 0..<24)
          timeField("分钟", component: .minute, options: 0..<60)
        }
      }
      HStack(spacing: 8) {
        ActionButton(title: wholeHours ? "下个整点" : "一小时后", emphasis: .secondary, size: .compact,
          fillsWidth: true) {
          date = wholeHours ? FollowUpHour.next(after: .now) : Date().addingTimeInterval(3600)
        }
        ActionButton(title: wholeHours ? "明日同点" : "明天此时", emphasis: .secondary, size: .compact,
          fillsWidth: true) {
          let reference = wholeHours ? date : Date()
          if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: reference) {
            date = wholeHours ? FollowUpHour.move(reference, to: tomorrow) : tomorrow
          }
        }
      }
      Text("\(date.formatted(pickerDateTimeFormat)) · \(TimeZone.current.identifier)")
        .font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
    }
  }

  private func timeField(_ label: String, component: Calendar.Component, options: Range<Int>) -> some View {
    let selected = calendar.component(component, from: date)
    let value = String(format: "%02d", selected)
    return WorkflowField(title: label) {
      CossMenu(title: title + label, value: value, width: 112, prefersSelection: true) {
        for option in options {
          let time = time(on: date, setting: component, to: option)
          CossMenuItem.command(String(format: "%02d", option), mark: .choice(option == selected), enabled: time != nil) {
            if let time { date = time }
          }
        }
      } trigger: {
        CossMenuLabel(title: value, size: .form, fillsWidth: true).monospacedDigit()
          .controlFieldSurface(focused: false, fill: Palette.canvas, radius: UILayout.controlRadius)
      }
    }
  }

  private func time(on day: Date, setting component: Calendar.Component, to value: Int) -> Date? {
    let hour = component == .hour ? value : calendar.component(.hour, from: day)
    let minute = component == .minute ? value : calendar.component(.minute, from: day)
    guard let selected = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
      matchingPolicy: .strict), calendar.isDate(selected, inSameDayAs: day) else { return nil }
    return selected
  }
}

struct FollowUpDateTimeField: View {
  let title: String
  @Binding var date: Date
  @ViewState<Bool> private var showingCalendar = false
  @ViewState<Date> private var selection = .now
  var body: some View {
    CossDateTrigger(title: title, value: date.formatted(pickerDateTimeFormat)) {
      selection = FollowUpHour.roundedUp(date)
      showingCalendar = true
    }.cossPopover(isPresented: $showingCalendar, arrowEdge: .top, radius: CossDatePickerLayout.radius) {
      VStack(alignment: .leading, spacing: 8) {
        DateTimeSelection(title: title, date: $selection, wholeHours: true)
        HStack {
          Spacer()
          ActionButton(title: "完成", emphasis: .primary) {
            date = selection
            showingCalendar = false
          }
        }
      }.padding(CossDatePickerLayout.inset).frame(width: CossDatePickerLayout.width)
    }
  }
}
