import BoxmailCore
import SwiftUI

/// Search and date-time forms share the same month navigation and day grid.
struct CalendarMonthView: View {
  let title: String
  @Binding var selection: Date?
  var choose: () -> Void = {}
  @ViewState private var month: Date
  @ViewState private var showsDayFocus = false
  @FocusState private var focusedDay: Date?
  private var calendar: Calendar { MailSearchCalendar.calendar() }
  private var cell: CGFloat { CossDatePickerLayout.cell }
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
    VStack(spacing: 4) {
      HStack(spacing: 0) {
        IconButton(icon: .chevronLeft, help: "上个月", size: cell) { moveMonth(-1) }
        Spacer(minLength: 0)
        HStack(spacing: 0) {
          captionMenu(title: "日历年份", selection: yearSelection,
            options: max(1, year - 50)...min(9999, year + 20), unit: "年")
          captionMenu(title: "日历月份", selection: monthSelection, options: 1...12, unit: "月")
        }
        Spacer(minLength: 0)
        IconButton(icon: .chevronRight, help: "下个月", size: cell) { moveMonth(1) }
      }.frame(height: cell)
      HStack(spacing: 0) {
        ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { day in
          Text(day).font(UIType.caption).foregroundStyle(Palette.muted.opacity(0.9)).frame(width: cell, height: cell)
        }
      }.accessibilityHidden(true)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 0), count: 7), spacing: 0) {
        let days = MailSearchCalendar.monthDays(containing: month, firstWeekday: 1, showsOutsideDays: true)
        ForEach(days.indices, id: \.self) { index in
          let day = days[index]
          if let day { dayButton(day) }
          else { Color.clear.frame(height: cell).accessibilityHidden(true) }
        }
      }
    }.frame(width: cell * 7).tint(Palette.accent)
      .onKeyPress(.leftArrow) { moveDayFocus(-1) }
      .onKeyPress(.rightArrow) { moveDayFocus(1) }
      .onKeyPress(.upArrow) { moveDayFocus(-7) }
      .onKeyPress(.downArrow) { moveDayFocus(7) }
      .onKeyPress(.tab) { showsDayFocus = true; return .ignored }
      .accessibilityElement(children: .contain).accessibilityLabel(title + "日历")
      .onChange(of: selection) { _, value in
        if let value, !calendar.isDate(value, equalTo: month, toGranularity: .month) { month = value }
      }
  }

  private func captionMenu(title: String, selection: Binding<Int>, options: ClosedRange<Int>, unit: String) -> some View {
    let selected = selection.wrappedValue
    return CossMenu(title: title, value: "\(selected)\(unit)", width: 112, prefersSelection: true) {
      options.map { value in
        CossMenuItem.command("\(value)\(unit)", mark: .choice(value == selected)) {
          selection.wrappedValue = value
        }
      }
    } trigger: {
      Text(verbatim: "\(selected)\(unit)").font(.system(size: 14, weight: .medium))
        .frame(height: cell)
    }
  }

  private func dayButton(_ date: Date) -> some View {
    let selected = selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    let today = calendar.isDateInToday(date)
    let outside = !calendar.isDate(date, equalTo: month, toGranularity: .month)
    return Button {
      showsDayFocus = false
      chooseDay(date)
    } label: {
      Text("\(calendar.component(.day, from: date))")
        .font(.system(size: 14)).monospacedDigit()
        .foregroundStyle(selected ? Palette.primaryForeground : outside ? Palette.muted.opacity(0.9) : Palette.ink)
        .frame(width: cell, height: cell)
        .overlay(alignment: .bottom) {
          if today {
            Circle().fill(selected ? Palette.primaryForeground : Palette.primary).frame(width: 3, height: 3)
              .padding(.bottom, 4).accessibilityHidden(true)
          }
        }
    }.buttonStyle(ControlFeedback(emphasis: selected ? .primary : .plain))
      .focusable().focusEffectDisabled().focused($focusedDay, equals: date)
      .overlay {
        if showsDayFocus && focusedDay == date {
          RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous)
            .strokeBorder(Palette.accent, lineWidth: 2).allowsHitTesting(false)
        }
      }
      .onKeyPress(.return) { chooseDay(date); return .handled }
      .accessibilityLabel(MailSearchCalendar.value(date))
      .accessibilityValue(today ? "今天" : "")
      .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func chooseDay(_ date: Date) {
    if !calendar.isDate(date, equalTo: month, toGranularity: .month) { month = date }
    selection = date
    choose()
  }

  private func moveDayFocus(_ offset: Int) -> KeyPress.Result {
    guard let focusedDay, let next = calendar.date(byAdding: .day, value: offset, to: focusedDay),
      calendar.component(.era, from: next) == 1, calendar.component(.year, from: next) <= 9999 else { return .ignored }
    showsDayFocus = true
    if !calendar.isDate(next, equalTo: month, toGranularity: .month) { month = next }
    self.focusedDay = next
    return .handled
  }

  private func moveMonth(_ offset: Int) {
    if let date = calendar.date(byAdding: .month, value: offset, to: month),
      calendar.component(.era, from: date) == 1, calendar.component(.year, from: date) <= 9999 { month = date }
  }
}
