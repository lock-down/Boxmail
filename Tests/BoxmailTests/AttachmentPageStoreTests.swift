import BoxmailCore
import Foundation
import Testing

@testable import Boxmail

@MainActor private func attachmentPageData(offset: Int = 0, total: Int = 105, id: String = "file")
  throws -> Data
{
  try JSONSerialization.data(withJSONObject: [
    "items": [
      [
        "attachment": [
          "id": id, "messageId": "mail", "name": "file.txt",
          "contentType": "text/plain", "size": 10, "text": "",
          "parseError": "", "date": "2026-11-10", "hasExtractedText": true,
        ],
        "source": ["id": "mail", "subject": "Subject", "sender": "Sender", "date": "2026-11-10"],
      ]
    ],
    "total": total, "offset": offset, "limit": 50, "accountTotal": total, "analyzedTotal": 0,
  ])
}

@Test @MainActor func attachmentPagesReplaceRowsAndResetWhenFiltersAccountOrSortChange()
  async throws
{
  let stub = HTTPStub(path: "/attachments", data: try attachmentPageData())
  defer { stub.close() }
  let pages = AttachmentPageStore(backend: BackendService(session: stub.session), accountId: "a")
  await pages.load(revision: 0)
  #expect(pages.items.count == 1 && pages.canNext && !pages.canPrevious)
  pages.next()
  #expect(pages.offset == 50 && pages.items.count == 1 && pages.showsPreviousPage && !pages.canNext)
  let next = HTTPStub(
    path: "/attachments", data: try attachmentPageData(offset: 50, id: "second"), scope: stub)
  defer { next.close() }
  await pages.load(revision: 0)
  #expect(pages.items.map(\.id) == ["second"] && pages.canPrevious)
  let query = URLComponents(
    url: try #require(next.latestRequest?.url), resolvingAgainstBaseURL: false)
  #expect(query?.queryItems?.contains(.init(name: "offset", value: "50")) == true)
  #expect(query?.queryItems?.contains(.init(name: "limit", value: "50")) == true)
  pages.query = "跨页关键字+资料"
  #expect(pages.offset == 0 && pages.items.count == 1)
  #expect(pages.request.path.contains("%2B"))
  pages.query = ""
  let first = HTTPStub(path: "/attachments", data: try attachmentPageData(), scope: stub)
  defer { first.close() }
  await pages.load(revision: 0)
  pages.next()
  #expect(pages.offset == 50)
  pages.type = "ZIP"
  #expect(pages.offset == 0 && pages.request.type == "archive")
  pages.sortOrder = [KeyPathComparator(\AttachmentPageItem.size, order: .reverse)]
  #expect(pages.request.sort == "size" && !pages.request.ascending)
  pages.accountId = "b"
  #expect(pages.items.isEmpty && pages.request.accountId == "b")
}

@Test @MainActor func attachmentPagingDiscardsResponsesFromAnOldAccountOrCancelledQuery()
  async throws
{
  let stub = HTTPStub(path: "/attachments", data: try attachmentPageData(), delayed: true)
  defer { stub.close() }
  let pages = AttachmentPageStore(backend: BackendService(session: stub.session), accountId: "a")
  let loading = Task { await pages.load(revision: 0) }
  try await stub.waitUntilStarted()
  pages.accountId = "b"
  stub.respond()
  await loading.value
  #expect(pages.items.isEmpty && pages.page == nil && !pages.loading)
  let pending = HTTPStub(
    path: "/attachments", data: try attachmentPageData(), delayed: true, scope: stub)
  defer { pending.close() }
  let cancelled = Task { await pages.load(revision: 0) }
  try await pending.waitUntilStarted()
  cancelled.cancel()
  pending.respond()
  await cancelled.value
  #expect(pages.items.isEmpty && pages.error == nil && !pages.loading)
}

@Test @MainActor func attachmentPagingCanRetryFailuresAndAcceptAnAdjustedLastPage() async throws {
  let stub = HTTPStub(path: "/attachments", data: Data(#"{"error":"分页读取失败"}"#.utf8), status: 500)
  defer { stub.close() }
  let pages = AttachmentPageStore(backend: BackendService(session: stub.session), accountId: "a")
  await pages.load(revision: 0)
  #expect(pages.error != nil && pages.items.isEmpty)
  let success = HTTPStub(path: "/attachments", data: try attachmentPageData(), scope: stub)
  defer { success.close() }
  await pages.load(revision: 0, force: true)
  #expect(pages.error == nil && pages.items.count == 1)
  pages.next()
  let clamped = HTTPStub(path: "/attachments", data: try attachmentPageData(total: 1), scope: stub)
  defer { clamped.close() }
  await pages.load(revision: 1)
  #expect(pages.offset == 0 && pages.visiblePage?.total == 1)
  #expect(!pages.canNext && !pages.canPrevious)
}

@Test @MainActor func attachmentPagingRetainsRowsAndRestoresTheLoadedOffsetOnFailure() async throws
{
  let stub = HTTPStub(path: "/attachments", data: try attachmentPageData())
  defer { stub.close() }
  let pages = AttachmentPageStore(backend: BackendService(session: stub.session), accountId: "a")
  await pages.load(revision: 0)
  pages.next()
  let failure = HTTPStub(
    path: "/attachments", data: Data(#"{"error":"分页失败"}"#.utf8), status: 500, scope: stub)
  defer { failure.close() }
  await pages.load(revision: 0)
  #expect(pages.offset == 0 && pages.items.count == 1 && pages.error != nil && pages.canNext)
}

@Test @MainActor func failedFilterChangesCanReturnToTheLoadedPageAndControls() async throws {
  let stub = HTTPStub(path: "/attachments", data: try attachmentPageData())
  defer { stub.close() }
  let pages = AttachmentPageStore(backend: BackendService(session: stub.session), accountId: "a")
  await pages.load(revision: 0)
  pages.next()
  let second = HTTPStub(path: "/attachments", data: try attachmentPageData(offset: 50), scope: stub)
  defer { second.close() }
  await pages.load(revision: 0)
  pages.query = "新条件"
  pages.type = "ZIP"
  pages.sortOrder = [KeyPathComparator(\AttachmentPageItem.size, order: .forward)]
  let failure = HTTPStub(
    path: "/attachments", data: Data(#"{"error":"筛选失败"}"#.utf8), status: 500, scope: stub)
  defer { failure.close() }
  await pages.load(revision: 0)
  #expect(pages.canRestoreLoadedPage && pages.items.count == 1)
  pages.restoreLoadedPage()
  #expect(pages.request == pages.loadedRequest)
  #expect(pages.query.isEmpty && pages.type == "全部" && pages.offset == 50)
  #expect(pages.error == nil && pages.canPrevious && pages.canNext && !pages.showsPreviousPage)
  pages.accountId = "b"
  pages.restoreLoadedPage()
  #expect(pages.items.isEmpty && pages.accountId == "b")
}
