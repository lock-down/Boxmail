import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class WritingPreferencesStore {
  private let backend: BackendService
  var styles: [WritingStyle] = []
  var selectedId = ""
  var name = ""
  var instruction = ""
  var language = "跟随来信"
  var error: String?
  init(backend: BackendService) { self.backend = backend }
  var selectedInstruction: String { styles.first { $0.id == selectedId }?.instruction ?? "" }
  func load() async {
    do { styles = try await backend.request("/writing-styles") }
    catch { self.error = error.localizedDescription }
  }
  func save() async {
    do {
      let style: WritingStyle = try await backend.request("/writing-styles" + (selectedId.isEmpty ? "" : "/\(selectedId)"), method: "POST",
        body: ["name": name, "instruction": instruction])
      selectedId = style.id; await load(); error = nil
    } catch { self.error = error.localizedDescription }
  }
  func remove() async {
    guard !selectedId.isEmpty else { return }
    do { try await backend.perform("/writing-styles/\(selectedId)", method: "DELETE"); selectedId = ""; await load() }
    catch { self.error = error.localizedDescription }
  }
}
