import BoxmailCore
import SwiftUI

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
    VStack(alignment: .leading, spacing: 16) {
      CalendarMonthView(title: title, selection: day)
      CossSeparator()
      if wholeHours {
        WorkflowField(title: "整点") {
          WorkflowSelection(title: title + "整点",
            selection: Binding(get: { calendar.component(.hour, from: date) }, set: { hour in
              if let selected = FollowUpHour.time(on: date, hour: hour, calendar: calendar) {
                date = selected
              }
            }), options: FollowUpHour.hours(on: date, calendar: calendar).map { ($0, String(format: "%02d:00", $0)) })
            .frame(width: 156)
        }
      } else {
        HStack(spacing: 12) {
          WorkflowField(title: "小时") {
            CossNumberField(title: title + "小时", value: time(.hour), range: 0...23, digits: 2)
          }
          WorkflowField(title: "分钟") {
            CossNumberField(title: title + "分钟", value: time(.minute), range: 0...59, digits: 2)
          }
        }.frame(maxWidth: 244)
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

  private func time(_ component: Calendar.Component) -> Binding<Int> {
    Binding(get: { calendar.component(component, from: date) }, set: { value in
      let hour = component == .hour ? value : calendar.component(.hour, from: date)
      let minute = component == .minute ? value : calendar.component(.minute, from: date)
      if let selected = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date,
        matchingPolicy: .strict), calendar.isDate(selected, inSameDayAs: date) {
        date = selected
      }
    })
  }
}

struct FollowUpDateTimeField: View {
  let title: String
  @Binding var date: Date
  @ViewState<Bool> private var showingCalendar = false
  @ViewState<Date> private var selection = .now
  var body: some View {
    CossDateTrigger(title: title, value: date.formatted(date: .abbreviated, time: .shortened)) {
      selection = FollowUpHour.roundedUp(date)
      showingCalendar = true
    }.cossPopover(isPresented: $showingCalendar) {
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
      }.padding(UILayout.sectionInset).frame(width: 360).background(Palette.paper)
    }
  }
}
