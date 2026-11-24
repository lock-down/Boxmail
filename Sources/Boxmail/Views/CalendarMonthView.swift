import BoxmailCore
import SwiftUI

/// Search and date-time forms share the same month navigation and day grid.
struct CalendarMonthView: View {
  let title: String
  @Binding var selection: Date?
  var choose: () -> Void = {}
  @ViewState private var month: Date
  @FocusState private var focusedDay: Date?
  private var calendar: Calendar { MailSearchCalendar.calendar() }
  private var year: Int { calendar.component(.year, from: month) }
  private var monthNumber: Int { calendar.component(.month, from: month) }

  init(title: String, selection: Binding<Date?>, choose: @escaping () -> Void = {}) {
    self.title = title; _selection = selection; self.choose = choose
    _month = ViewState(wrappedValue: selection.wrappedValue ?? .now)
  }
  private var yearSelection: Binding<Int> {
    Binding(get: { year }, set: {
      if let date = MailSearchCalendar.date(year: $0, month: monthNumber, day: 1) { month = date }
    })
  }
  private var monthSelection: Binding<Int> {
    Binding(get: { monthNumber }, set: {
      if let date = MailSearchCalendar.date(year: year, month: $0, day: 1) { month = date }
    })
  }
  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 8) {
        IconButton(icon: .arrowLeftSLine, help: "上个月") { moveMonth(-1) }
        HStack(spacing: 24) {
          WorkflowSelection(title: "日历年份", selection: yearSelection,
            options: (max(1, year - 50)...min(9999, year + 20)).map { ($0, "\($0) 年") }, style: .inline)
          WorkflowSelection(title: "日历月份", selection: monthSelection,
            options: (1...12).map { ($0, "\($0) 月") }, style: .inline)
        }
        IconButton(icon: .arrowRightSLine, help: "下个月") { moveMonth(1) }
      }.frame(height: 32)
      HStack(spacing: 4) {
        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
          Text(day).font(UIType.small).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
        }
      }.accessibilityHidden(true)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
        ForEach(Array(MailSearchCalendar.monthDays(containing: month).enumerated()), id: \.offset) { _, day in
          if let day { dayButton(day) }
          else { Color.clear.frame(height: 32).accessibilityHidden(true) }
        }
      }
    }.frame(maxWidth: .infinity).tint(Palette.accent)
      .onKeyPress(.leftArrow) { moveDayFocus(-1) }
      .onKeyPress(.rightArrow) { moveDayFocus(1) }
      .onKeyPress(.upArrow) { moveDayFocus(-7) }
      .onKeyPress(.downArrow) { moveDayFocus(7) }
      .accessibilityElement(children: .contain).accessibilityLabel(title + "日历")
      .onChange(of: selection) { _, value in
        if let value, !calendar.isDate(value, equalTo: month, toGranularity: .month) { month = value }
      }
  }
  private func dayButton(_ date: Date) -> some View {
    let selected = selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    let today = calendar.isDateInToday(date)
    return Button { chooseDay(date) } label: {
      Text("\(calendar.component(.day, from: date))")
        .font(.system(size: 12, weight: selected || today ? .semibold : .regular))
        .foregroundStyle(selected ? Palette.primaryForeground : Palette.ink)
        .frame(maxWidth: .infinity).frame(height: 32)
        .background(today && !selected ? Palette.sidebar : .clear,
          in: RoundedRectangle(cornerRadius: UILayout.controlRadius))
    }.buttonStyle(ControlFeedback(emphasis: selected ? .primary : .plain))
      .focusable().focusEffectDisabled().focused($focusedDay, equals: date)
      .overlay {
        if focusedDay == date {
          RoundedRectangle(cornerRadius: UILayout.controlRadius)
            .strokeBorder(Palette.accent, lineWidth: 2).allowsHitTesting(false)
        }
      }
      .onKeyPress(.return) { chooseDay(date); return .handled }
      .accessibilityLabel(MailSearchCalendar.value(date))
      .accessibilityValue(today ? "今天" : "")
      .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func chooseDay(_ date: Date) {
    selection = date
    choose()
  }

  private func moveDayFocus(_ offset: Int) -> KeyPress.Result {
    guard let focusedDay, let next = calendar.date(byAdding: .day, value: offset, to: focusedDay),
      (1...9999).contains(calendar.component(.year, from: next)) else { return .ignored }
    if !calendar.isDate(next, equalTo: month, toGranularity: .month) { month = next }
    self.focusedDay = next
    return .handled
  }

  private func moveMonth(_ offset: Int) {
    if let date = calendar.date(byAdding: .month, value: offset, to: month),
      (1...9999).contains(calendar.component(.year, from: date)) { month = date }
  }
}
