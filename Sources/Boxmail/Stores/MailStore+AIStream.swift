import BoxmailCore
import Foundation

extension MailStore {
  func aiOutput(task: String, messageId: String? = nil, attachmentId: String? = nil) -> AIStreamOutput? {
    aiOutputs.values.filter { $0.task == task && $0.messageId == messageId
      && (attachmentId == nil || $0.attachmentId == attachmentId) }
      .sorted { $0.status == "running" && $1.status != "running" }.first
  }

  func watchAIOutput() {
    guard aiStreamTask == nil else { return }
    aiStreamTask = Task {
      defer { aiStreamTask = nil }
      while !Task.isCancelled {
        do {
          try await self.backend.aiEvents { event in
            if event.type == "snapshot" {
              self.aiOutputs = Dictionary((event.outputs ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            } else if let output = event.output {
              if output.status != "running" && (output.task == "question" || output.task == "compare") {
                // The assistant commits its own session through the ask response.
                self.aiOutputs[output.id] = nil
                return
              }
              self.aiOutputs[output.id] = output
              if output.status != "running" {
                Task {
                  try? await self.refresh()
                  self.aiOutputs[output.id] = nil
                }
              }
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

  func isShowingTranslation(_ message: MailMessage) -> Bool {
    translatedMessageIds.contains(message.id)
  }

  func toggleTranslation(_ message: MailMessage) {
    if translatedMessageIds.contains(message.id) {
      translatedMessageIds.remove(message.id)
      if mailAITab == .translate { mailAITab = nil }
    } else {
      translatedMessageIds.insert(message.id)
      mailAITab = .translate
    }
  }

  func translatedMessage(_ message: MailMessage) -> MailMessage {
    guard isShowingTranslation(message) else { return message }
    var value = message
    if let output = aiOutput(task: "translate", messageId: message.id), !output.text.isEmpty {
      value.body = output.text
      value.html = output.html
    } else if let text = message.translation {
      value.body = text
      value.html = message.translationHTML
    }
    return value
  }
}
