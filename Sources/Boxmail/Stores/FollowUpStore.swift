import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class FollowUpStore {
  let scrollPosition = ScrollPositionState()
  private let backend: BackendService
  var items: [FollowUp] = []
  var error: String?
  var editorRequest: String?
  var suggestSnooze = false
  var selectedId: String?
  var filter = "待我处理"
  init(backend: BackendService) { self.backend = backend }
  func load() async {
    do { let next: [FollowUp] = try await backend.request("/follow-ups"); if items != next { items = next }; error = nil }
    catch { self.error = error.localizedDescription }
  }
  @discardableResult func save(_ input: [String: Any], id: String? = nil) async -> FollowUp? {
    do {
      let item: FollowUp = try await backend.request("/follow-ups" + (id.map { "/\($0)" } ?? ""), method: "POST", body: input)
      selectedId = item.id; await load(); return item
    } catch { self.error = error.localizedDescription; return nil }
  }
  func remove(_ item: FollowUp) async {
    do { try await backend.perform("/follow-ups/\(item.id)", method: "DELETE"); await load() }
    catch { self.error = error.localizedDescription }
  }
}
