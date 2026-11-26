import Foundation
import NaturalLanguage

public enum MailTranslationLanguage: String, CaseIterable, Identifiable, Codable {
  case simplified = "zh-Hans", traditional = "zh-Hant", english = "en", japanese = "ja", korean = "ko",
    french = "fr", german = "de", spanish = "es", portuguese = "pt", italian = "it", russian = "ru"

  public var id: String { rawValue }
  public var title: String {
    switch self {
    case .simplified: "简体中文"
    case .traditional: "繁體中文"
    case .english: "英语"
    case .japanese: "日语"
    case .korean: "韩语"
    case .french: "法语"
    case .german: "德语"
    case .spanish: "西班牙语"
    case .portuguese: "葡萄牙语"
    case .italian: "意大利语"
    case .russian: "俄语"
    }
  }

  public func detectsDifferentLanguage(in body: String) -> Bool {
    var fencedCode = false
    let lines = body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
      let text = line.trimmingCharacters(in: .whitespaces)
      if text.hasPrefix("```") || text.hasPrefix("~~~") { fencedCode.toggle(); return nil }
      guard !fencedCode, !line.hasPrefix("    "), !line.hasPrefix("\t") else { return nil }
      let cleaned = text.replacingOccurrences(of: #"https?://\S+|\S+@\S+\.\S+|`[^`]*`"#, with: " ", options: .regularExpression)
      if cleaned.range(of: #"^(?:(?:import|package|return|let|const|def|class|func)\s|[\w.]+\s*\([^)]*\)\s*;?$|[{}<>])"#,
        options: .regularExpression) != nil { return nil }
      return cleaned
    }
    let text = lines.joined(separator: "\n")
    guard text.unicodeScalars.filter(CharacterSet.letters.contains).count >= 16 else { return false }
    let recognizer = NLLanguageRecognizer()
    func confidentLanguage(_ sample: String) -> String? {
      recognizer.reset()
      recognizer.processString(sample)
      let ranked = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
      guard let first = ranked.first, first.value >= 0.65, first.value - (ranked.dropFirst().first?.value ?? 0) >= 0.25 else { return nil }
      return first.key.rawValue
    }
    guard let dominant = confidentLanguage(text), dominant != rawValue else { return false }
    let sentences = NLTokenizer(unit: .sentence)
    sentences.string = text
    var mixed = false
    sentences.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      let sample = String(text[range])
      if sample.unicodeScalars.filter(CharacterSet.letters.contains).count >= 12,
        let language = confidentLanguage(sample), language != dominant { mixed = true }
      return !mixed
    }
    return !mixed
  }
}

public struct MailTranslationResult: Codable, Hashable {
  public let text: String
  public let html: String?
  public init(text: String, html: String?) { self.text = text; self.html = html }
}
