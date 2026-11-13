import Foundation
import Observation

@Observable @MainActor final class SettingsActionState {
  enum Feedback {
    case success(String)
    case failure(String)
  }

  private(set) var isWorking = false
  private(set) var progress: String?
  private(set) var feedback: Feedback?

  var failure: String? {
    if case .failure(let text) = feedback { return text }
    return nil
  }

  func clearFailure() {
    if failure != nil { feedback = nil }
  }

  @discardableResult func run(_ progress: String? = nil,
    operation: @escaping @MainActor () async throws -> Feedback?) -> Task<Void, Never> {
    isWorking = true; self.progress = progress; feedback = nil
    return Task {
      defer { isWorking = false; self.progress = nil }
      do { feedback = try await operation() }
      catch { feedback = .failure(error.localizedDescription) }
    }
  }
}
