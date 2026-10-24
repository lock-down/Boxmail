import Foundation

extension MailAccount {
  public var sidebarName: String {
    let label = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !label.isEmpty && label.caseInsensitiveCompare(email) != .orderedSame { return label }
    let host = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
    if host == "qq.com" || host.hasSuffix(".qq.com") { return "QQ 邮箱" }
    if host == "163.com" || host == "126.com" || host == "yeah.net" { return "网易邮箱" }
    if host == "gmail.com" { return "Gmail" }
    if ["outlook.com", "hotmail.com", "live.com"].contains(host) { return "Outlook" }
    return host.isEmpty ? "邮箱账户" : host
  }
}
