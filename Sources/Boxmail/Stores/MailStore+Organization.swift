import BoxmailCore
import Foundation

struct MailOrganizationPolicy: Decodable {
  let id, mode: String
  let labelRules: [String: String]
  let point: InboxPoint?
  let classification: Classification?

  struct Classification: Decodable {
    let mode: String
    let labelIds: [String]
  }

  static let disableNotice = "尚未开始的自动整理任务会暂停，新邮件将停止入队。已提交给服务商的请求仍会继续，结果可能写入清单。"

  var statusTitle: String {
    switch mode {
    case "automatic": point == nil ? "自动整理已开启，等待连接邮箱" : "自动整理已开启"
    case "manual": "仅手动整理"
    default: "自动整理尚未设置"
    }
  }

  struct InboxPoint: Decodable {
    let path, validity: String
    let uidNext: Int
  }
}

extension MailStore {
  var visibleOrganizationBatches: [OrganizationBatch] {
    let active = organizationBatchProgress.filter(\.active)
    if !active.isEmpty { return active }
    return organizationBatchProgress.first.flatMap { $0.id == hiddenOrganizationBatchID ? nil : [$0] } ?? []
  }

  func recordOrganizationBatch(_ batch: OrganizationBatch) {
    organizationProgressRevision += 1
    if batch.active && hiddenOrganizationBatchID == batch.id { hiddenOrganizationBatchID = nil }
    organizationBatchProgress.removeAll { $0.id == batch.id }
    organizationBatchProgress.append(batch.summary)
    organizationBatchProgress.sort {
      $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
    }
  }

  func stopOrganizationBatch(_ id: String) async throws -> OrganizationBatch {
    let batch: OrganizationBatch = try await backend.request("/mail-organization/cancel-batch", method: "POST",
      body: ["id": id, "includeRunning": true])
    recordOrganizationBatch(batch)
    return batch
  }

  func organizationPolicy(for accountID: String) async throws -> MailOrganizationPolicy {
    var url = URLComponents()
    url.path = "/mail-organization/policy"
    url.queryItems = [URLQueryItem(name: "accountId", value: accountID)]
    return try await backend.request(url.string ?? url.path)
  }

  func saveOrganizationPolicy(_ input: [String: Any]) async throws -> MailOrganizationPolicy {
    try await backend.request("/mail-organization/policy", method: "POST", body: input)
  }
}
