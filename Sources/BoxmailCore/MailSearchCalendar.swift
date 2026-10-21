import Foundation

public enum MailSearchCalendar {
  public static func calendar(timeZone: TimeZone = .current) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    calendar.firstWeekday = 2
    return calendar
  }
  public static func date(year: Int, month: Int, day: Int, timeZone: TimeZone = .current) -> Date? {
    guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
    let calendar = calendar(timeZone: timeZone)
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return parts.year == year && parts.month == month && parts.day == day ? date : nil
  }
  public static func parse(_ value: String, timeZone: TimeZone = .current) -> Date? {
    let parts = value.split(separator: "-").map(String.init)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
    return date(year: year, month: month, day: day, timeZone: timeZone)
  }
  public static func value(_ date: Date, timeZone: TimeZone = .current) -> String {
    let parts = calendar(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
  public static func monthDays(containing date: Date, timeZone: TimeZone = .current) -> [Date?] {
    let calendar = calendar(timeZone: timeZone)
    let parts = calendar.dateComponents([.year, .month], from: date)
    guard let first = self.date(year: parts.year!, month: parts.month!, day: 1, timeZone: timeZone),
      let days = calendar.range(of: .day, in: .month, for: first) else { return [] }
    let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    let cellCount = ((leading + days.count + 6) / 7) * 7
    return (0..<cellCount).map { index in
      let day = index - leading + 1
      return days.contains(day) ? calendar.date(byAdding: .day, value: day - 1, to: first) : nil
    }
  }
}
