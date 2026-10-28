import BoxmailCore
import Foundation

extension MailStore {
  var syncProgressText: String {
    if syncCancellationRequested { return "正在停止同步…" }
    let progress =
      syncSnapshot?.folders.filter {
        syncingAccountIds.contains($0.accountId)
          && (syncingFolder == nil || $0.folder == syncingFolder)
      } ?? []
    if syncStatusIssue != nil { return "进度连接中断，正在重试…" }
    let inventories = progress.filter { $0.status == "running" && $0.phase == "inventory" }
    if !inventories.isEmpty {
      let read = inventories.reduce(0) { $0 + max(0, $1.inventory?.metadataCount ?? 0) }
      let expected = inventories.reduce(0) {
        $0 + max(0, $1.inventory?.statusCount ?? $1.inventory?.uidCount ?? 0)
      }
      return expected > 0 ? "正在读取清单 \(read)/\(expected) 封" : "正在读取邮件清单…"
    }
    let total = progress.reduce(0) { $0 + max(0, $1.total ?? 0) }
    guard total > 0 else {
      if !syncingAccountIds.isEmpty { return "正在连接邮箱（\(syncingAccountIds.count) 个）…" }
      return "正在同步…"
    }
    let downloaded = progress.reduce(0) {
      $0 + min(max(0, $1.downloaded ?? 0), max(0, $1.total ?? 0))
    }
    return "正在同步 \(downloaded)/\(total) 封"
  }

  func syncAll(silent: Bool = false, folder: String? = nil) async {
    guard !busy.contains("sync") else { return }
    let real = accounts.filter { !$0.isDemo && (folder == nil || $0.id == accountId) }
    guard !real.isEmpty else {
      if !silent {
        showSettings = true
        settingsTab = "账号"
      }
      return
    }
    busy.insert("sync")
    syncingAccountIds = Set(real.map(\.id))
    syncingFolder = folder
    syncCancellationRequested = false
    syncStatusIssue = nil
    syncContentRefresh?.cancel()
    syncContentRefresh = nil
    defer {
      busy.remove("sync")
      syncingAccountIds = []
      syncingFolder = nil
      syncCancellationRequested = false
      syncStatusIssue = nil
    }
    if backend.hasExited {
      do { try await backend.reconnectAfterExit() } catch {
        if !silent { self.error = error.localizedDescription }
        return
      }
    }
    backend.diagnostics.record("sync.requested", ["count": String(real.count)])
    var failures: [String: String] = [:]
    var started: Set<String> = []
    var startsComplete = false
    // Start acknowledgements and progress polling are independent. A lost
    // acknowledgement for one account cannot hide another account's progress.
    let starters = Task { @MainActor in
      await withTaskGroup(of: (String, String?).self) { group in
        var iterator = real.makeIterator()
        func enqueue(_ account: MailAccount) {
          group.addTask { @MainActor in
            guard !Task.isCancelled, !self.syncCancellationRequested else {
              return (account.id, nil)
            }
            do {
              let password = try self.readMailPassword(account.id)
              self.credentialIssueAccounts.remove(account.id)
              var input: [String: Any] = [
                "accountId": account.id, "password": password, "background": true,
              ]
              if let folder { input["folder"] = folder }
              try await self.backend.perform("/sync", body: input, timeout: 10)
              return (account.id, "")
            } catch {
              if CredentialService.isCredentialError(error) {
                self.credentialIssueAccounts.insert(account.id)
                self.backend.diagnostics.record(
                  "sync.credentials.failed",
                  ["account": RuntimeDiagnostics.accountReference(account.id)])
                return (account.id, silent ? nil : error.localizedDescription)
              }
              if Task.isCancelled { return (account.id, nil) }
              // The server may have accepted the request before its reply was lost.
              if let snapshot: MailSyncSnapshot = try? await self.backend.request(
                "/sync-status", timeout: 5),
                snapshot.runningAccounts.contains(account.id)
              {
                self.syncSnapshot = snapshot
                return (account.id, "")
              }
              return (account.id, error.localizedDescription)
            }
          }
        }
        for _ in 0..<2 { if let account = iterator.next() { enqueue(account) } }
        for await (id, issue) in group {
          if issue == "" {
            started.insert(id)
            if self.syncCancellationRequested { await self.sendSyncCancellation([id]) }
          } else if let issue {
            failures[id] = issue
          }
          if !Task.isCancelled, !self.syncCancellationRequested, let account = iterator.next() {
            enqueue(account)
          }
        }
      }
      startsComplete = true
    }
    defer { starters.cancel() }
    var pollingFailures = 0
    var lastDownloaded = -1
    var lastRefresh = Date()
    var refreshing = false
    do {
      while !Task.isCancelled {
        let startsWereComplete = startsComplete
        let snapshot: MailSyncSnapshot
        do {
          snapshot = try await backend.request("/sync-status", timeout: 8)
          if pollingFailures > 0 { backend.diagnostics.record("sync.poll.recovered") }
          pollingFailures = 0
          syncStatusIssue = nil
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          if backend.hasExited {
            starters.cancel()
            markSyncServiceExited()
            throw backend.failure(backend.disconnectedMessage)
          }
          pollingFailures += 1
          syncStatusIssue = "本机服务进度查询失败（\(pollingFailures)/3）"
          backend.diagnostics.record("sync.poll.failed", ["attempt": String(pollingFailures)])
          if pollingFailures >= 3 {
            starters.cancel()
            await sendSyncCancellation(syncingAccountIds)
            throw backend.failure("无法取得同步进度，已请求停止本次同步。已下载邮件已保留；请导出诊断日志，恢复服务后重试。")
          }
          try await Task.sleep(for: .seconds(2))
          continue
        }
        syncSnapshot = snapshot
        if startsWereComplete
          && !snapshot.runningAccounts.contains(where: { syncingAccountIds.contains($0) })
        {
          for result in snapshot.results
          where started.contains(result.accountId) && result.status == "failed" {
            failures[result.accountId] = result.error ?? "同步未完成"
          }
          break
        }
        let downloaded = snapshot.folders.filter { syncingAccountIds.contains($0.accountId) }
          .reduce(0) { $0 + ($1.downloaded ?? 0) }
        if downloaded != lastDownloaded && !refreshing
          && Date().timeIntervalSince(lastRefresh) >= 12
        {
          lastRefresh = Date()
          lastDownloaded = downloaded
          refreshing = true
          syncContentRefresh = Task { @MainActor in
            defer { refreshing = false }
            try? await self.refresh(reloadContent: false)
          }
        }
        try await Task.sleep(for: syncPollInterval)
      }
      if Task.isCancelled { throw CancellationError() }
      // Refresh the list separately. It must never keep the sync indicator busy
      // after the server has already completed or failed the session.
      syncContentRefresh?.cancel()
      syncContentRefresh = Task { @MainActor in try? await self.refresh(reloadContent: false) }
    } catch is CancellationError {
      starters.cancel()
      await sendSyncCancellation(syncingAccountIds)
      await starters.value
      return
    } catch { failures[""] = error.localizedDescription }
    starters.cancel()
    await starters.value
    if !failures.isEmpty && !silent {
      var details = real.compactMap { account in
        failures[account.id].map { "\(account.email)：\($0)" }
      }
      if let issue = failures[""] { details.append(issue) }
      error = details.joined(separator: "\n")
    }
    let paused =
      syncCancellationRequested
      || syncSnapshot?.results.contains {
        started.contains($0.accountId) && $0.status == "paused"
      } == true
    backend.diagnostics.record(
      "sync.finished",
      [
        "status": !failures.isEmpty ? "failed" : paused ? "paused" : "completed",
        "count": String(started.count),
      ])
  }

  func cancelSync() async {
    guard busy.contains("sync"), !syncCancelInFlight else { return }
    syncCancellationRequested = true
    syncCancelInFlight = true
    defer { syncCancelInFlight = false }
    await sendSyncCancellation(syncingAccountIds)
  }

  func markSyncServiceExited() {
    guard var snapshot = syncSnapshot else { return }
    for index in snapshot.folders.indices
    where ["running", "partial"].contains(snapshot.folders[index].status) {
      snapshot.folders[index].status = "paused"
      snapshot.folders[index].lastError = "本机服务已退出，已完成邮件保留，再次同步可继续。"
    }
    for index in snapshot.results.indices
    where ["running", "queued"].contains(snapshot.results[index].status) {
      snapshot.results[index].status = "failed"
      snapshot.results[index].error = "本机服务意外退出，可重新同步。"
    }
    snapshot.runningAccounts = []
    syncSnapshot = snapshot
    backend.diagnostics.record("sync.service.exited")
  }

  func sendSyncCancellation(_ ids: Set<String>) async {
    // Cleanup must still reach the server when the caller itself was cancelled.
    // An unstructured task gets a fresh cancellation state and keeps the 5s limit.
    let cancellation = Task { @MainActor in
      await withTaskGroup(of: Bool.self) { tasks in
        for id in ids {
          tasks.addTask { @MainActor in
            do {
              try await self.backend.perform("/sync/cancel", body: ["accountId": id], timeout: 5)
              return true
            } catch { return false }
          }
        }
        var failed = false
        for await success in tasks { if !success { failed = true } }
        if failed { syncStatusIssue = "停止请求未送达，可再次点击停止，或导出诊断日志。" }
      }
    }
    await cancellation.value
  }
}
