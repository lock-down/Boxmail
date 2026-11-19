import BoxmailCore
import Foundation
import Observation

@Observable @MainActor final class AssistantWorkspaceStore {
  let scrollPosition = ScrollPositionState()
  private let backend: BackendService
  var isPresented = false
  var session: AssistantSession?
  var sessions: [AssistantSession] = []
  var prompt = ""
  var error: String?
  var busy = false
  private(set) var stopping = false
  private(set) var askingSessionID: String?
  private(set) var pendingPrompt = ""
  var attachmentIds: Set<String> = []
  private(set) var pendingScope: AssistantScope?
  init(backend: BackendService) { self.backend = backend }
  var canAsk: Bool {
    !busy && !stopping && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  func beginAttachmentComparison() {
    begin(scope: .init(kind: "attachments", attachmentIds: attachmentIds.sorted()))
  }
  func begin(scope: AssistantScope? = nil) {
    isPresented = true
    guard !busy else { return }
    session = nil
    pendingScope = scope
    scrollPosition.origin = .zero
    error = nil
  }
  func select(_ previous: AssistantSession) {
    guard !busy else { return }
    begin()
    session = previous
  }
  func load() async {
    do { sessions = try await backend.request("/assistant-sessions") }
    catch { if !Task.isCancelled { self.error = error.localizedDescription } }
  }
  func ask(scope: AssistantScope? = nil) async {
    guard canAsk, session != nil || scope != nil else { return }
    let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    busy = true; pendingPrompt = question; prompt = ""; error = nil
    defer { busy = false; askingSessionID = nil; pendingPrompt = "" }
    do {
      if session == nil, var scope {
        if scope.kind == "attachments", scope.relationship == nil { scope.relationship = question }
        session = try await backend.request("/assistant-sessions", method: "POST", body: ["scope": try jsonObject(scope)])
        pendingScope = nil
      }
      guard let id = session?.id else { return }
      askingSessionID = id
      let answered: AssistantSession = try await backend.request("/assistant-sessions/\(id)/ask", method: "POST", body: ["prompt": question])
      updateSession(answered)
    } catch {
      self.error = error.localizedDescription
      if prompt.isEmpty { prompt = question }
    }
  }
  func stop() async {
    guard let id = askingSessionID, !stopping else { return }
    stopping = true
    defer { stopping = false }
    do {
      try await backend.perform("/assistant-sessions/\(id)/stop", method: "POST")
    } catch { self.error = error.localizedDescription }
  }
  func apply(_ action: AssistantAction, turn: AssistantTurn) async {
    guard !busy, let id = session?.id else { return }
    busy = true
    defer { busy = false }
    do {
      let updated: AssistantSession = try await backend.request("/assistant-sessions/\(id)/apply",
        method: "POST", body: ["turnId": turn.id, "actionId": action.id, "approved": true])
      updateSession(updated)
      error = nil
    } catch { self.error = error.localizedDescription }
  }
  private func updateSession(_ value: AssistantSession) {
    session = value
    if let index = sessions.firstIndex(where: { $0.id == value.id }) {
      sessions[index] = value
    } else {
      sessions.append(value)
    }
  }
}
