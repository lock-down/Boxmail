import Darwin
import Foundation

/// Owns a backend and its directory lease until the child has actually exited.
@MainActor public final class LocalBackendProcess {
  private let child: Process
  private let lifetime: Pipe
  private let errors: Pipe
  private let failureClassifier: RuntimeFailureClassifier
  private let diagnosticHandler: (@Sendable (String) -> Void)?
  private var lease: DataDirectoryLease?
  private var shutdown: Task<Void, Never>?
  public var isRunning: Bool { child.isRunning }
  public var processIdentifier: Int32 { child.processIdentifier }

  public init(
    executable: URL, arguments: [String], directory: URL,
    environment: [String: String], lease: DataDirectoryLease,
    onExit: (@Sendable (Int32, Bool) -> Void)? = nil,
    onDiagnostic: (@Sendable (String) -> Void)? = nil
  ) throws {
    let child = Process()
    child.executableURL = executable
    child.arguments = arguments
    child.currentDirectoryURL = directory
    var environment = environment
    environment["BOXMAIL_LIFETIME_PIPE"] = "1"
    child.environment = environment
    let lifetime = Pipe()
    let inherited = try lease.inheritedFileHandle()
    // Foundation retains standardInput after termination. Close our duplicate
    // immediately after spawning so it cannot keep a dead child's lock alive.
    defer { try? inherited.close() }
    child.standardInput = inherited
    child.standardOutput = lifetime
    let errors = Pipe()
    let classifier = RuntimeFailureClassifier()
    child.standardError = errors
    child.terminationHandler = { process in
      onExit?(process.terminationStatus, process.terminationReason == .uncaughtSignal)
    }
    try child.run()
    try? lifetime.fileHandleForWriting.close()
    try? errors.fileHandleForWriting.close()
    lifetime.fileHandleForReading.readabilityHandler = { handle in
      if (try? handle.read(upToCount: 4096))?.isEmpty != false { handle.readabilityHandler = nil }
    }
    errors.fileHandleForReading.readabilityHandler = { handle in
      guard let data = try? handle.read(upToCount: 4096), !data.isEmpty else {
        handle.readabilityHandler = nil
        return
      }
      if let category = classifier.consume(data) { onDiagnostic?(category) }
    }
    self.child = child
    self.lifetime = lifetime
    self.errors = errors
    self.failureClassifier = classifier
    self.diagnosticHandler = onDiagnostic
    self.lease = lease
  }

  public func stop(gracePeriod: TimeInterval = 4) async {
    if let shutdown {
      await shutdown.value
      return
    }
    let child = child
    let task = Task.detached(priority: .utility) {
      if child.isRunning { child.terminate() }
      let deadline = Date().addingTimeInterval(gracePeriod)
      while child.isRunning && Date() < deadline { usleep(25_000) }
      if child.isRunning { Darwin.kill(child.processIdentifier, SIGKILL) }
      child.waitUntilExit()
    }
    shutdown = task
    await task.value
    lifetime.fileHandleForReading.readabilityHandler = nil
    try? lifetime.fileHandleForReading.close()
    errors.fileHandleForReading.readabilityHandler = nil
    if let data = try? errors.fileHandleForReading.readToEnd(),
      let category = failureClassifier.consume(data)
    {
      diagnosticHandler?(category)
    }
    try? errors.fileHandleForReading.close()
    lease = nil
  }

  /// Recover only an orphan of this exact bundled runtime, holding this exact
  /// lock inode on stdin. Live applications and unrelated Node processes stay intact.
  public nonisolated static func recoverOrphan(in directory: URL, executable: URL) async -> Bool {
    await Task.detached(priority: .utility) {
      var lock = stat()
      guard stat(directory.appendingPathComponent(".boxmail.lock").path, &lock) == 0 else {
        return false
      }
      let expected = executable.standardizedFileURL.resolvingSymlinksInPath().path
      func owner(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        guard
          proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
            > 0,
          info.pbi_ppid == 1, info.pbi_uid == getuid()
        else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
          URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().path == expected
        else { return nil }
        var file = vnode_fdinfowithpath()
        guard
          proc_pidfdinfo(
            pid, STDIN_FILENO, PROC_PIDFDVNODEPATHINFO, &file,
            Int32(MemoryLayout.size(ofValue: file))) > 0,
          file.pvip.vip_vi.vi_stat.vst_ino == lock.st_ino,
          file.pvip.vip_vi.vi_stat.vst_dev == UInt32(bitPattern: lock.st_dev)
        else { return nil }
        return info
      }
      let capacity = max(32, Int(proc_listallpids(nil, 0)) + 32)
      var pids = [Int32](repeating: 0, count: capacity)
      let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
      var recovered = false
      for pid in pids.prefix(max(0, min(Int(count), capacity))) where pid > 1 {
        guard let original = owner(pid) else { continue }
        Darwin.kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(3)
        while owner(pid) != nil && Date() < deadline { usleep(50_000) }
        if let current = owner(pid), current.pbi_start_tvsec == original.pbi_start_tvsec,
          current.pbi_start_tvusec == original.pbi_start_tvusec
        {
          Darwin.kill(pid, SIGKILL)
        }
        recovered = true
      }
      return recovered
    }.value
  }
}
