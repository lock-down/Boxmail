import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class RuleWorkspaceStore {
  private let backend: BackendService
  var rules: [MailRule] = []
  var runs: [RuleRun] = []
  var jobs: [String: AgentJob] = [:]
  var usage: [AIUsage] = []
  var error: String?

  init(backend: BackendService) { self.backend = backend }

  func loadRules() async {
    do {
      rules = try await backend.request("/mail-rules")
      error = nil
    } catch { self.error = error.localizedDescription }
  }

  func loadActivity() async {
    do {
      async let nextRuns: [RuleRun] = backend.request("/rule-runs")
      async let nextUsage: [AIUsage] = backend.request("/ai-usage")
      let (records, usageRecords) = try await (nextRuns, nextUsage)
      if runs != records { runs = records }
      if usage != usageRecords { usage = usageRecords }
      error = nil
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }

  func loadJobs(for run: RuleRun) async {
    for id in Set(run.items.flatMap(\.jobIds)) where jobs[id]?.status != "completed" {
      guard !Task.isCancelled else { return }
      if let job: AgentJob = try? await backend.request("/jobs/\(id)") { jobs[id] = job }
    }
  }

  func save(_ rule: MailRule) async -> Bool {
    do {
      try await backend.perform("/mail-rules" + (rule.id.isEmpty ? "" : "/\(rule.id)"), body: try jsonObject(rule))
      await loadRules()
      return true
    } catch { self.error = error.localizedDescription; return false }
  }

  func confirmAgentDraft(_ rule: MailRule) async -> Bool {
    do {
      try await backend.perform("/mail-rules/agent-confirm", body: ["rule": try jsonObject(rule), "approved": true])
      await loadRules()
      return true
    } catch { self.error = error.localizedDescription; return false }
  }

  func preview(_ rule: MailRule) async -> RuleRun? {
    do {
      let run: RuleRun = try await backend.request("/mail-rules/\(rule.id)/preview", method: "POST", body: [:])
      runs.insert(run, at: 0)
      error = nil
      return run
    } catch { self.error = error.localizedDescription; return nil }
  }

  func run(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/run", body: ["approved": true]) }
  func undo(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/undo") }
  func pause(_ record: RuleRun) async { await perform("/rule-runs/\(record.id)/pause") }

  func remove(_ rule: MailRule) async {
    do { try await backend.perform("/mail-rules/\(rule.id)", method: "DELETE"); await loadRules() }
    catch { self.error = error.localizedDescription }
  }

  private func perform(_ path: String, body: [String: Any] = [:]) async {
    do { try await backend.perform(path, body: body); await loadActivity() }
    catch { self.error = error.localizedDescription }
  }
}
