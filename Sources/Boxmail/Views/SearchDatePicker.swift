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
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }.buttonStyle(.plain).controlFocus().accessibilityLabel(title)
      .accessibilityValue(value.isEmpty ? "未选择日期" : value)

  }
}

struct SearchCalendarPanel: View {
  let title: String
  @Binding var selection: String
  let close: () -> Void
  @ViewState<Date> private var month: Date
  private var calendar: Calendar { MailSearchCalendar.calendar() }
  private var year: Int { calendar.component(.year, from: month) }
  private var monthNumber: Int { calendar.component(.month, from: month) }
  private var years: [(Int, String)] { (max(1, year - 50)...min(9999, year + 20)).map { ($0, "\($0) 年") } }
  private var yearSelection: Binding<Int> {
    Binding(get: { year }, set: { if let date = MailSearchCalendar.date(year: $0, month: monthNumber, day: 1) { month = date } })
  }
  private var monthSelection: Binding<Int> {
    Binding(get: { monthNumber }, set: { if let date = MailSearchCalendar.date(year: year, month: $0, day: 1) { month = date } })
  }
  init(title: String, selection: Binding<String>, close: @escaping () -> Void) {
    self.title = title; _selection = selection; self.close = close
    _month = ViewState(wrappedValue: MailSearchCalendar.parse(selection.wrappedValue) ?? .now)
  }
  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 0) {
        WorkflowAction(title: "", icon: "chevron.left", help: "上个月") { moveMonth(-1) }
          .frame(width: 32)
        Spacer(minLength: 8)
        HStack(spacing: 8) {
          WorkflowSelection(title: "日历年份", selection: yearSelection, options: years, compact: true).frame(width: 80)
          WorkflowSelection(title: "日历月份", selection: monthSelection,
            options: (1...12).map { ($0, "\($0) 月") }, compact: true).frame(width: 64)
        }
        Spacer(minLength: 8)
        WorkflowAction(title: "", icon: "chevron.right", help: "下个月") { moveMonth(1) }
          .frame(width: 32)
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
      Divider().overlay(Palette.softBorder)
      HStack {
        WorkflowAction(title: "清除日期") { selection = ""; close() }.disabled(selection.isEmpty)
        Spacer()
        WorkflowAction(title: "今天", color: Palette.blue) { choose(.now) }
      }
    }.frame(maxWidth: .infinity).background(Palette.paper).tint(Palette.blue)
      .accessibilityElement(children: .contain).accessibilityLabel(title + "日历")
      .onExitCommand { close() }
  }
  private func dayButton(_ date: Date) -> some View {
    let value = MailSearchCalendar.value(date)
    let selected = selection == value
    let today = calendar.isDateInToday(date)
    return Button { choose(date) } label: {
      Text("\(calendar.component(.day, from: date))")
        .font(.system(size: 12, weight: selected || today ? .semibold : .regular))
        .foregroundStyle(selected || today ? Palette.blue : Palette.ink)
        .frame(maxWidth: .infinity).frame(height: 32)
        .background(selected ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) {
          if today && !selected { Circle().fill(Palette.blue).frame(width: 3, height: 3).padding(.bottom, 3) }
        }.contentShape(RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(ControlFeedback(selected: selected, corner: 6)).controlFocus(corner: 6)
      .accessibilityLabel(value).accessibilityAddTraits(selected ? .isSelected : [])
  }
  private func choose(_ date: Date) { selection = MailSearchCalendar.value(date); close() }
  private func moveMonth(_ offset: Int) {
    if let date = calendar.date(byAdding: .month, value: offset, to: month),
      (1...9999).contains(calendar.component(.year, from: date)) { month = date }
  }
}
