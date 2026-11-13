import Foundation

struct RecipientField: Codable, Equatable, Identifiable {
  enum Kind: String, Codable {
    case to, cc, bcc
    var title: String {
      switch self {
      case .to: return "收件人"
      case .cc: return "抄送"
      case .bcc: return "密送"
      }
    }
  }
  let kind: Kind
  let value: String
  var id: Kind { kind }
  var title: String { kind.title }
}
