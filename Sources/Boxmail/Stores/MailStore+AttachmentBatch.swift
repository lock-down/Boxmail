import BoxmailCore
import Foundation

extension MailStore {
  func attachmentBatch(for message: MailMessage) -> AgentJob? {
    jobs.first { $0.task == "attachmentBatch" && $0.messageId == message.id }
  }

  func analyzeAttachments(in message: MailMessage, force: Bool = false, retry job: AgentJob? = nil) {
    let control = "attachment-batch-\(message.id)"
    guard !busy.contains(control), attachmentBatch(for: message)?.status != "running" else { return }
    busy.insert(control)
    attachmentBatchErrors[message.id] = nil
    Task {
      defer { busy.remove(control) }
      do {
        let key = try KeychainService.read(settings.ai.credentialAccount)
        let updated: AgentJob = try await self.backend.request(
          job.map { "/jobs/\($0.id)/retry" } ?? "/messages/\(message.id)/attachments/analyze",
          method: "POST", body: ["accountId": message.accountId, "apiKey": key,
            "providerId": settings.ai.providerId, "force": force],
          timeout: 15)
        replaceJob(updated)
        watchAttachmentBatches()
      } catch {
        attachmentBatchErrors[message.id] = error.localizedDescription
        // The request may have reached the service even if its response was interrupted.
        try? await refresh()
      }
    }
  }

  func pauseAttachmentBatch(_ job: AgentJob) {
    guard let messageId = job.messageId else { return }
    let control = "attachment-batch-\(messageId)"
    guard !busy.contains(control) else { return }
    busy.insert(control)
    Task {
      defer { busy.remove(control) }
      do {
        let updated: AgentJob = try await self.backend.request(
          "/jobs/\(job.id)/pause", method: "POST")
        replaceJob(updated)
      } catch { attachmentBatchErrors[messageId] = error.localizedDescription }
    }
  }

  func watchAttachmentBatches() {
    guard attachmentBatchPolling == nil,
      jobs.contains(where: { $0.task == "attachmentBatch" && $0.status == "running" })
    else { return }
    attachmentBatchPolling = Task {
      defer { attachmentBatchPolling = nil }
      var loadedResults = Set<String>()
      while !Task.isCancelled {
        let running = jobs.filter { $0.task == "attachmentBatch" && $0.status == "running" }
        if running.isEmpty { break }
        for job in running {
          do {
            let updated: AgentJob = try await self.backend.request(
              "/jobs/\(job.id)", timeout: 10)
            try Task.checkCancellation()
            replaceJob(updated)
            if let messageId = updated.messageId {
              attachmentBatchErrors[messageId] = nil
              if messageId == selectedMessageId {
                for item in updated.attachmentItems ?? [] where item.isAnalyzed {
                  let key = "\(job.id)-\(item.id)"
                  if !loadedResults.contains(key) {
                    await loadAttachment(item.id)
                    loadedResults.insert(key)
                  }
                }
              }
            }
          } catch is CancellationError { return
          } catch {
            if let messageId = job.messageId {
              attachmentBatchErrors[messageId] = "暂时无法获取进度，正在重新连接。"
            }
          }
        }
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }
}
