import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class RuleWorkspaceStore {
  var tab = "规则"
  let scrollPosition = ScrollPositionState()
  private let backend: BackendService
  var rules: [MailRule] = []
  var runs: [RuleRun] = []
  var jobs: [String: AgentJob] = [:]
  var usage: [AIUsage] = []
  var error: String?
  var selectedRunId: String?
  init(backend: BackendService) { self.backend = backend }
  func load() async {
    do {
      let nextRules: [MailRule] = try await backend.request("/mail-rules")
      if rules != nextRules { rules = nextRules }
      let nextRuns: [RuleRun] = try await backend.request("/rule-runs")
      if runs != nextRuns { runs = nextRuns }
      let nextUsage: [AIUsage] = try await backend.request("/ai-usage")
      if usage != nextUsage { usage = nextUsage }
      for id in Set(runs.flatMap { $0.items.flatMap(\.jobIds) }) {
        if jobs[id]?.status != "completed" {
          let job: AgentJob = try await backend.request("/jobs/\(id)")
          if jobs[id]?.status != job.status { jobs[id] = job }
        }
      }
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  func save(_ rule: MailRule) async -> Bool {
    do {
      try await backend.perform("/mail-rules" + (rule.id.isEmpty ? "" : "/\(rule.id)"), body: try jsonObject(rule))
      await load(); return true
    } catch { self.error = error.localizedDescription; return false }
  }
  func preview(_ rule: MailRule) async {
    do {
      let run: RuleRun = try await backend.request("/mail-rules/\(rule.id)/preview", method: "POST", body: [:])
      selectedRunId = run.id; await load()
    } catch { self.error = error.localizedDescription }
  }
  func run(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/run", body: ["approved": true]) }
  func undo(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/undo") }
  func pause(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/pause") }
  func remove(_ rule: MailRule) async {
    do { try await backend.perform("/mail-rules/\(rule.id)", method: "DELETE"); await load() }
    catch { self.error = error.localizedDescription }
  }
  private func perform(_ path: String, body: [String: Any] = [:]) async {
    do { try await backend.perform(path, body: body); await load() }
    catch { self.error = error.localizedDescription }
  }
}
