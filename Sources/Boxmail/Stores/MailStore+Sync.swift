import Foundation

extension MailStore {
  var syncProgressText: String {
    if syncCancellationRequested { return "正在停止同步…" }
    let progress = syncSnapshot?.folders.filter {
      syncingAccountIds.contains($0.accountId) && (syncingFolder == nil || $0.folder == syncingFolder)
    } ?? []
    let total = progress.reduce(0) { $0 + max(0, $1.total ?? 0) }
    guard total > 0 else { return "正在同步…" }
    let downloaded = progress.reduce(0) { $0 + min(max(0, $1.downloaded ?? 0), max(0, $1.total ?? 0)) }
    return "正在同步 \(downloaded)/\(total) 封"
  }

  func cancelSync() async {
    guard busy.contains("sync"), !syncCancelInFlight else { return }
    syncCancellationRequested = true
    syncCancelInFlight = true
    defer { syncCancelInFlight = false }
    var failures: [String] = []
    for id in syncingAccountIds {
      do { try await BackendService.shared.perform("/sync/cancel", body: ["accountId": id]) }
      catch is CancellationError { return }
      catch { failures.append(error.localizedDescription) }
    }
    if !failures.isEmpty { error = "停止同步未完成，可再次点击停止。\n" + failures.joined(separator: "\n") }
  }
}
