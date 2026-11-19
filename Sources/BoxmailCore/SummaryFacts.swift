import Foundation

public struct SummaryFactGroup: Identifiable, Hashable {
  public enum Kind: String, CaseIterable {
    case time = "时间与期限"
    case cost = "金额与费用"
    case contact = "联系与提交"
    case details = "事项与条件"

    fileprivate init(label: String) {
      let name = label.folding(options: [.widthInsensitive, .caseInsensitive], locale: nil)
      if let exact = Self(rawValue: name) { self = exact; return }
      if ["时间", "日期", "截止", "期限", "有效期", "时段", "周期", "排期"].contains(where: name.contains) {
        self = .time
      } else if ["金额", "费用", "价格", "报价", "预算", "限价", "税率", "折扣", "款项"].contains(where: name.contains) {
        self = .cost
      } else if ["联系", "邮箱", "邮件地址", "电话", "提交", "链接", "报名方式", "领取方式"].contains(where: name.contains) {
        self = .contact
      } else {
        self = .details
      }
    }
  }

  public let kind: Kind
  public let facts: [KeyInfo]
  public var id: Kind { kind }

  public static func organize(_ facts: [KeyInfo]) -> [Self] {
    var unique = Set<KeyInfo>()
    var groups: [Kind: [KeyInfo]] = [:]
    for item in facts {
      let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
      let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
      let fact = KeyInfo(label: label, value: value)
      guard !label.isEmpty, !value.isEmpty, unique.insert(fact).inserted else { continue }
      groups[Kind(label: label), default: []].append(fact)
    }
    return Kind.allCases.map { Self(kind: $0, facts: groups[$0, default: []]) }
  }
}
