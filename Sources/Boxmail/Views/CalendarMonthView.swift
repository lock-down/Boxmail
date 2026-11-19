import BoxmailCore
import SwiftUI

/// Search and date-time forms share the same month navigation and day grid.
struct CalendarMonthView: View {
  let title: String
  @Binding var selection: Date?
  var choose: () -> Void = {}
  @ViewState private var month: Date
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
        IconButton(icon: "chevron.left", help: "上个月") { moveMonth(-1) }
        HStack(spacing: 24) {
          WorkflowSelection(title: "日历年份", selection: yearSelection,
            options: (max(1, year - 50)...min(9999, year + 20)).map { ($0, "\($0) 年") }, style: .inline)
          WorkflowSelection(title: "日历月份", selection: monthSelection,
            options: (1...12).map { ($0, "\($0) 月") }, style: .inline)
        }
        IconButton(icon: "chevron.right", help: "下个月") { moveMonth(1) }
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
    }.frame(maxWidth: .infinity).tint(Palette.blue)
      .accessibilityElement(children: .contain).accessibilityLabel(title + "日历")
      .onChange(of: selection) { _, value in
        if let value, !calendar.isDate(value, equalTo: month, toGranularity: .month) { month = value }
      }
  }
  private func dayButton(_ date: Date) -> some View {
    let selected = selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    let today = calendar.isDateInToday(date)
    return Button { selection = date; choose() } label: {
      Text("\(calendar.component(.day, from: date))")
        .font(.system(size: 12, weight: selected || today ? .semibold : .regular))
        .foregroundStyle(selected || today ? Palette.blue : Palette.ink)
        .frame(maxWidth: .infinity).frame(height: 32)
        .background(selected ? Palette.blueSoft : .clear,
          in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
        .overlay(alignment: .bottom) {
          if today && !selected { Circle().fill(Palette.blue).frame(width: 3, height: 3).padding(.bottom, 3) }
        }.contentShape(RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
    }.buttonStyle(ControlFeedback(selected: selected)).controlFocus()
      .accessibilityLabel(MailSearchCalendar.value(date)).accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func moveMonth(_ offset: Int) {
    if let date = calendar.date(byAdding: .month, value: offset, to: month),
      (1...9999).contains(calendar.component(.year, from: date)) { month = date }
  }
}
