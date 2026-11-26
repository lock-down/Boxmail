import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class WritingPreferencesStore {
  struct Style: Equatable {
    var tone = "正式"
    var length = "适中"
    var instruction = ""

    var summary: String { "\(tone) · \(length)" }
  }

  struct Preset: Identifiable {
    let id: String
    let name: String
    let style: Style
  }

  static let builtInPresets: [Preset] = [
    Preset(id: "", name: "标准商务", style: Style()),
    Preset(id: "builtin:acknowledgement", name: "简短确认", style: Style(tone: "专业", length: "简短",
      instruction: "直接确认或回答关键问题，只保留必要信息和下一步。")),
    Preset(id: "builtin:friendly", name: "友好沟通", style: Style(tone: "亲切",
      instruction: "用自然、礼貌的措辞，先简短回应对方，再说明需要协商或推进的事项。")),
    Preset(id: "builtin:status", name: "条理汇报", style: Style(tone: "专业", length: "详细",
      instruction: "先给结论，再分点说明已有进展、影响和下一步。")),
  ]

  private static let preferenceKey = "BoxmailDefaultWritingStyle"
  private let backend: BackendService
  private(set) var styles: [WritingStyle] = []
  private(set) var selectedId: String
  private(set) var isLoading = true
  private(set) var style: Style
  var language: MailTranslationLanguage?
  var error: String?

  init(backend: BackendService) {
    self.backend = backend
    let id = UserDefaults.standard.string(forKey: Self.preferenceKey) ?? ""
    selectedId = id
    style = Self.builtInPresets.first { $0.id == id }?.style ?? Style()
  }

  var selectedStyle: WritingStyle? { styles.first { $0.id == selectedId } }
  private var selectedPreset: Preset {
    if let saved = selectedStyle {
      return Preset(id: saved.id, name: saved.name, style: Style(
        tone: saved.tone ?? "正式", length: saved.length ?? "适中", instruction: saved.instruction))
    }
    return Self.builtInPresets.first { $0.id == selectedId } ?? Self.builtInPresets[0]
  }

  var isAdjusted: Bool { style != selectedPreset.style }
  var styleName: String { isAdjusted ? "本次调整" : selectedPreset.name }

  func load() async {
    defer { isLoading = false }
    do {
      styles = try await backend.request("/writing-styles")
      select(selectedPreset.id)
    } catch is CancellationError {
    } catch { self.error = error.localizedDescription }
  }

  func select(_ id: String) {
    selectedId = id
    UserDefaults.standard.set(id, forKey: Self.preferenceKey)
    style = selectedPreset.style
    error = nil
  }

  func useOnce(_ style: Style) {
    self.style = style
    error = nil
  }

  func save(name: String, style: Style, asNew: Bool) async -> Bool {
    let path = !asNew && selectedStyle != nil ? "/writing-styles/\(selectedId)" : "/writing-styles"
    do {
      let saved: WritingStyle = try await backend.request(path, method: "POST", body: [
        "name": name, "tone": style.tone, "length": style.length, "instruction": style.instruction,
      ])
      if let index = styles.firstIndex(where: { $0.id == saved.id }) { styles[index] = saved }
      else { styles.append(saved) }
      select(saved.id)
      return true
    } catch { self.error = error.localizedDescription; return false }
  }

  func remove() async -> Bool {
    guard let selectedStyle else { return false }
    do {
      try await backend.perform("/writing-styles/\(selectedStyle.id)", method: "DELETE")
      styles.removeAll { $0.id == selectedStyle.id }
      select("")
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
}
