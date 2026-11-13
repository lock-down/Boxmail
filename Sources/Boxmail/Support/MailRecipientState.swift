import Foundation
import Observation
import WebKit

struct MailRecipientRegion: Decodable, Identifiable {
  let id: Int
  let x, y, width, height: Double
  let fields: [RecipientField]
}

/// WebKit owns source positions; SwiftUI owns the same recipient controls used by mail headers.
@Observable @MainActor final class MailRecipientState {
  var regions: [MailRecipientRegion] = []
  private(set) var generation = UUID()
  @ObservationIgnored weak var webView: MailBodyWebView?

  func reset() { generation = UUID(); regions = [] }

  func setHeight(_ height: CGFloat, for region: MailRecipientRegion, generation: UUID) {
    guard height > 0, abs(region.height - height) > 1 else { return }
    Task { @MainActor [weak self] in
      guard let self, self.generation == generation else { return }
      _ = try? await webView?.callAsyncJavaScript("""
        const slot = document.querySelector('[data-boxmail-recipient-id="' + id + '"]');
        if (slot) slot.style.height = height + 'px';
        """, arguments: ["id": region.id, "height": height], in: nil, contentWorld: .defaultClient)
    }
  }
}
