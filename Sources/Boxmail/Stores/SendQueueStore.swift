import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class SendQueueStore {
  private let backend: BackendService
  var plans: [SendPlan] = []
  var error: String?
  init(backend: BackendService) { self.backend = backend }
  func load() async {
    do { let next: [SendPlan] = try await backend.request("/send-plans"); if plans != next { plans = next }; error = nil }
    catch { self.error = error.localizedDescription }
  }
  func change(_ plan: SendPlan, date: Date? = nil, cancel: Bool = false) async {
    do {
      var input: [String: Any] = ["cancel": cancel, "timeZone": TimeZone.current.identifier]
      if let date { input["scheduledAt"] = ISO8601DateFormatter().string(from: date) }
      try await backend.perform("/send-plans/\(plan.id)", body: input); await load()
    } catch { self.error = error.localizedDescription }
  }
}
