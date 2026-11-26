import BoxmailCore
import Foundation

extension MailStore {
  func watchAIOutput() {
    guard aiStreamTask == nil else { return }
    aiStreamTask = Task {
      defer { aiStreamTask = nil }
      while !Task.isCancelled {
        do {
          try await self.backend.aiEvents { event in
            if event.type == "snapshot" {
              self.aiOutputs = Dictionary((event.outputs ?? []).filter {
                $0.task == "translate" && $0.targetLanguage != nil
              }.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            } else if let output = event.output, output.task == "translate", output.targetLanguage != nil {
              self.aiOutputs[output.id] = output.status == "running" ? output : nil
            }
          }
        } catch is CancellationError { return
        } catch {
          // Reconnect receives the current snapshot, including jobs started while disconnected.
        }
        if !Task.isCancelled { try? await Task.sleep(for: .seconds(1)) }
      }
    }
  }

}
