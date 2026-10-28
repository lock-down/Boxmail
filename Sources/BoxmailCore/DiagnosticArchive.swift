import Foundation

public enum DiagnosticArchive {
  public static func manifest(
    version: String, build: String, connected: Bool, syncing: Bool,
    snapshot: MailSyncSnapshot?
  ) throws -> Data {
    let phases: Set<String> = [
      "queued", "connect", "inventory", "download", "parse", "attachment", "running",
      "partial", "paused", "failed", "completed",
    ]
    func phase(_ value: String?) -> String {
      value.flatMap { phases.contains($0) ? $0 : nil } ?? "unknown"
    }
    let os = ProcessInfo.processInfo.operatingSystemVersion
    #if arch(arm64)
      let architecture = "arm64"
    #else
      let architecture = "x86_64"
    #endif
    let folders: [[String: Any]] = (snapshot?.folders ?? []).map { item in
      let knownFolders: Set<String> = ["inbox", "sent", "drafts", "archive", "trash", "spam"]
      var value: [String: Any] = [
        "account": RuntimeDiagnostics.accountReference(item.accountId),
        "folder": knownFolders.contains(item.folder) ? item.folder : "unknown",
        "status": phase(item.status), "phase": phase(item.phase), "hasError": item.lastError != nil,
      ]
      if let count = item.total { value["total"] = count }
      if let count = item.downloaded { value["downloaded"] = count }
      if let count = item.remaining { value["remaining"] = count }
      if let count = item.inventory?.metadataCount { value["metadataCount"] = count }
      return value
    }
    let results: [[String: Any]] = (snapshot?.results ?? []).map { item in
      [
        "account": RuntimeDiagnostics.accountReference(item.accountId),
        "status": phase(item.status),
        "phase": phase(item.phase), "hasError": item.error != nil,
      ]
    }
    return try JSONSerialization.data(
      withJSONObject: [
        "formatVersion": 1,
        "createdAt": ISO8601DateFormatter().string(from: Date()), "appVersion": version,
        "appBuild": build,
        "macOS": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
        "architecture": architecture,
        "connected": connected, "syncing": syncing, "folders": folders, "results": results,
        "runningAccounts": (snapshot?.runningAccounts ?? []).map(
          RuntimeDiagnostics.accountReference),
      ],
      options: [.prettyPrinted, .sortedKeys])
  }
  /// Uses only an explicit log allowlist. Export works while the backend is down,
  /// and never traverses the mail database, .env, attachment or backup folders.
  public static func export(from directory: URL, to destination: URL, manifest: Data) throws {
    let fm = FileManager.default
    let temporary = fm.temporaryDirectory.appendingPathComponent(
      "Boxmail-diagnostics-\(UUID().uuidString)", isDirectory: true)
    let content = temporary.appendingPathComponent("Boxmail-Diagnostics", isDirectory: true)
    try fm.createDirectory(
      at: content, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: temporary) }
    try manifest.write(to: content.appendingPathComponent("manifest.json"), options: .atomic)
    let logs = directory.appendingPathComponent("logs", isDirectory: true)
    if fm.fileExists(atPath: logs.path) {
      guard try logs.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
        throw failure()
      }
      for base in ["app.jsonl", "backend.jsonl"] {
        for suffix in ["", ".1", ".2"] {
          let source = logs.appendingPathComponent(base + suffix)
          guard fm.fileExists(atPath: source.path) else { continue }
          let values = try source.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
          ])
          guard values.isRegularFile == true, values.isSymbolicLink != true,
            (values.fileSize ?? Int.max) <= 1_100_000
          else { throw failure() }
          try fm.copyItem(at: source, to: content.appendingPathComponent(base + suffix))
        }
      }
    }
    let readme =
      "Boxmail 运行诊断\n包含应用与本机服务的近期轮转日志，以及导出时的版本和同步状态。\n账户仅用匿名标识关联。不含授权码、API Key、请求正文、邮件正文、主题或附件。\n日志从安装支持诊断的版本后开始记录；未发生的历史错误无法补录。\n"
    try Data(readme.utf8).write(to: content.appendingPathComponent("README.txt"))
    let archive = temporary.appendingPathComponent("diagnostics.zip")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = [
      "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", content.path, archive.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw failure() }
    try Data(contentsOf: archive).write(to: destination, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
  }
  private static func failure() -> NSError {
    NSError(
      domain: "Boxmail.Diagnostics", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "诊断日志无法安全读取或打包，请检查日志目录及保存位置。"])
  }
}
