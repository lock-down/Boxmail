import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

private func organizationData(offset: Int = 0, total: Int = 105, id: String = "mail") throws -> Data
{
  try JSONSerialization.data(withJSONObject: [
    "items": [
      [
        "id": id, "accountId": "a", "folder": "inbox", "sender": "Sender",
        "senderEmail": "sender@example.test",
        "to": "", "cc": "", "subject": id, "body": "", "preview": "", "date": "2026-11-11",
        "category": "工作项目",
        "unread": false, "starred": false, "attachmentIds": [], "bodyLoaded": false,
      ]
    ],
    "offset": offset, "total": total, "limit": 50, "accountTotal": 105,
    "categoryCounts": [["name": "工作项目", "count": 105]],
  ])
}

@Test @MainActor func organizationPagesReplaceRowsAndFilterBeforePaging() async throws {
  let first = HTTPStub(path: "/organization/messages", data: try organizationData())
  defer { first.close() }
  let pages = OrganizationPageStore(backend: BackendService(session: first.session), accountId: "a")
  await pages.load(revision: 0)
  #expect(pages.visiblePage?.items.map(\.id) == ["mail"] && pages.canNext)
  pages.next()
  let second = HTTPStub(
    path: "/organization/messages", data: try organizationData(offset: 50, id: "second"),
    scope: first)
  defer { second.close() }
  await pages.load(revision: 0)
  #expect(pages.visiblePage?.items.map(\.id) == ["second"] && pages.canPrevious)
  #expect(second.latestRequest?.url?.query?.contains("offset=50") == true)
  pages.category = "工作+资料"
  #expect(pages.offset == 0 && pages.request.path.contains("%2B"))
  pages.accountId = "b"
  #expect(pages.visiblePage == nil && pages.offset == 0)
}

@Test @MainActor func organizationPagesIgnoreLateAccountCategoryAndCancelledResponses() async throws
{
  let stub = HTTPStub(path: "/organization/messages", data: try organizationData(), delayed: true)
  defer { stub.close() }
  let pages = OrganizationPageStore(backend: BackendService(session: stub.session), accountId: "a")
  let task = Task { await pages.load(revision: 0) }
  try await stub.waitUntilStarted()
  pages.category = "未分类"
  stub.respond()
  await task.value
  #expect(pages.page == nil && pages.error == nil && !pages.loading)
  let pending = HTTPStub(
    path: "/organization/messages", data: try organizationData(), delayed: true, scope: stub)
  defer { pending.close() }
  let cancelled = Task { await pages.load(revision: 0) }
  try await pending.waitUntilStarted()
  cancelled.cancel()
  pending.respond()
  await cancelled.value
  #expect(pages.page == nil && pages.error == nil && !pages.loading)
}

@Test @MainActor func organizationPagingFailuresRestoreTheLoadedFilterAndClampADeletedLastPage()
  async throws
{
  let stub = HTTPStub(path: "/organization/messages", data: try organizationData(offset: 0))
  defer { stub.close() }
  let pages = OrganizationPageStore(backend: BackendService(session: stub.session), accountId: "a")
  await pages.load(revision: 0)
  pages.next()
  let second = HTTPStub(
    path: "/organization/messages", data: try organizationData(offset: 50), scope: stub)
  defer { second.close() }
  await pages.load(revision: 0)
  pages.category = "未分类"
  let failure = HTTPStub(
    path: "/organization/messages", data: Data(#"{"error":"分类加载失败"}"#.utf8), status: 500,
    scope: stub)
  defer { failure.close() }
  await pages.load(revision: 0)
  #expect(pages.canRestoreLoadedPage && pages.showsPreviousPage)
  pages.restoreLoadedPage()
  #expect(pages.category.isEmpty && pages.offset == 50 && pages.error == nil && pages.canPrevious)
  #expect(pages.request == pages.loadedRequest)
  let clamped = HTTPStub(
    path: "/organization/messages", data: try organizationData(total: 1), scope: stub)
  defer { clamped.close() }
  await pages.load(revision: 1)
  #expect(pages.offset == 0 && !pages.canNext && !pages.canPrevious)
}
