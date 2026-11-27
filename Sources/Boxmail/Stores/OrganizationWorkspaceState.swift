import Foundation
import Observation

/// Browsing state belongs to the account workspace, not its temporary SwiftUI view.
@Observable @MainActor final class OrganizationWorkspaceState {
  let pages: OrganizationPageStore
  var scope = "unclassified"
  var limit = 50
  let scrollPosition = ScrollPositionState()
  var selectedMessageId: String?

  init(backend: BackendService, accountId: String) {
    pages = OrganizationPageStore(backend: backend, accountId: accountId)
  }
}
