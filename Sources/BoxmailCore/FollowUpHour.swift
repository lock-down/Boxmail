import Foundation

public enum FollowUpHour {
  public static func next(after date: Date, calendar: Calendar = .current) -> Date {
    calendar.nextDate(after: date, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .strict) ?? date
  }

  public static func roundedUp(_ date: Date, calendar: Calendar = .current) -> Date {
    let parts = calendar.dateComponents([.minute, .second, .nanosecond], from: date)
    return parts.minute == 0 && parts.second == 0 && parts.nanosecond == 0 ? date : next(after: date, calendar: calendar)
  }

  public static func time(on day: Date, hour: Int, calendar: Calendar = .current) -> Date? {
    guard let time = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day, matchingPolicy: .strict),
      calendar.isDate(time, inSameDayAs: day), calendar.component(.hour, from: time) == hour else { return nil }
    return time
  }

  public static func hours(on day: Date, calendar: Calendar = .current) -> [Int] {
    (0..<24).filter { time(on: day, hour: $0, calendar: calendar) != nil }
  }

  public static func move(_ date: Date, to day: Date, calendar: Calendar = .current) -> Date {
    let hour = calendar.component(.hour, from: date)
    let valid = hours(on: day, calendar: calendar)
    guard let chosen = valid.first(where: { $0 >= hour }) ?? valid.last else { return date }
    return time(on: day, hour: chosen, calendar: calendar) ?? date
  }
}
