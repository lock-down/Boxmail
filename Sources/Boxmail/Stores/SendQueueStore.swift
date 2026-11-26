import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class SendQueueStore {
  private let backend: BackendService
  var plans: [SendPlan] = []
  var error: String?
  private var loadGeneration = 0
  init(backend: BackendService) { self.backend = backend }
  func load() async {
    loadGeneration += 1
    let generation = loadGeneration
    do {
      let next: [SendPlan] = try await backend.request("/send-plans")
      guard generation == loadGeneration else { return }
      if plans != next { plans = next }
      error = nil
    } catch {
      if generation == loadGeneration, !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
  var currentPlans: [String: SendPlan] {
    var current: [String: SendPlan] = [:]
    let active = ["waiting", "paused", "submitting", "uncertain"]
    for plan in plans {
      if let previous = current[plan.draftId] {
        if active.contains(plan.status) && !active.contains(previous.status) { current[plan.draftId] = plan }
      } else {
        current[plan.draftId] = plan
      }
    }
    return current.filter { $0.value.status != "sent" && $0.value.status != "cancelled" }
  }
  func change(_ plan: SendPlan, date: Date? = nil, cancel: Bool = false, pause: Bool = false) async throws {
    var input: [String: Any] = ["cancel": cancel, "pause": pause, "timeZone": TimeZone.current.identifier]
    if let date { input["scheduledAt"] = ISO8601DateFormatter().string(from: date) }
    let updated: SendPlan = try await backend.request("/send-plans/\(plan.id)", method: "POST", body: input)
    record(updated)
  }
  func record(_ plan: SendPlan) {
    loadGeneration += 1
    if let index = plans.firstIndex(where: { $0.id == plan.id }) { plans[index] = plan }
    else { plans.insert(plan, at: 0) }
  }
}
