import Darwin
import Foundation
import Testing
@testable import BoxmailCore

private func backendFixture() throws -> URL {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoxmailLifetime-\(UUID())")
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

@Test @MainActor func ownedBackendStopsBeforeReleasingItsDirectoryAndCanRestart() async throws {
  let root = try backendFixture()
  defer { try? FileManager.default.removeItem(at: root) }
  for _ in 0..<3 {
    let child = try LocalBackendProcess(executable: URL(fileURLWithPath: "/bin/sleep"),
      arguments: ["30"], directory: root, environment: [:], lease: DataDirectoryLease(directory: root))
    #expect(throws: Error.self) { try DataDirectoryLease(directory: root) }
    await child.stop()
    #expect(!child.isRunning)
    // Keep the Process wrapper alive: its retained stdin must no longer hold a lock.
    let reopened = try DataDirectoryLease(directory: root)
    #expect(reopened.directory == root.resolvingSymlinksInPath())
  }
}

@Test @MainActor func unresponsiveOwnedBackendHasBoundedShutdown() async throws {
  let root = try backendFixture()
  defer { try? FileManager.default.removeItem(at: root) }
  let marker = root.appendingPathComponent("ready")
  let child = try LocalBackendProcess(executable: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "trap '' TERM; touch \"$1\"; exec /bin/sleep 30", "test", marker.path],
    directory: root, environment: [:], lease: DataDirectoryLease(directory: root))
  for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker.path) {
    try await Task.sleep(for: .milliseconds(10))
  }
  #expect(FileManager.default.fileExists(atPath: marker.path))
  let start = Date()
  await child.stop(gracePeriod: 0.15)
  #expect(Date().timeIntervalSince(start) < 2)
  #expect(!child.isRunning)
  _ = try DataDirectoryLease(directory: root)
}

@Test @MainActor func orphanRecoveryNeverStopsLiveOwners() async throws {
  let root = try backendFixture()
  defer { try? FileManager.default.removeItem(at: root) }
  let runtime = URL(fileURLWithPath: "/bin/sleep").resolvingSymlinksInPath()
  let child = try LocalBackendProcess(executable: runtime, arguments: ["30"], directory: root,
    environment: [:], lease: DataDirectoryLease(directory: root))
  #expect(await LocalBackendProcess.recoverOrphan(in: root, executable: runtime) == false)
  #expect(child.isRunning)
  await child.stop()
}

@Test @MainActor func upgradeRecoversOnlyOrphanHoldingTheSameLockWithTheExpectedRuntime() async throws {
  // Always require recovery of a live orphan, then also exercise replacement.
  for replacingRuntime in [false, true] {
    try await recoverOrphanFixture(replacingRuntime: replacingRuntime)
  }
}

@MainActor private func recoverOrphanFixture(replacingRuntime: Bool) async throws {
  let root = try backendFixture()
  defer { try? FileManager.default.removeItem(at: root) }
  let runtime = root.appendingPathComponent("node")
  try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: runtime)
  let pidFile = root.appendingPathComponent("pid")
  var lease: DataDirectoryLease? = try DataDirectoryLease(directory: root)
  let supervisor = Process()
  supervisor.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  // Foundation launches each backend in its own process group. Detach the
  // fixture too, so its supervisor's group cannot terminate it during cleanup.
  supervisor.arguments = ["node", "--input-type=module", "-e", """
    import { spawn } from 'node:child_process';
    import { writeFileSync } from 'node:fs';
    const child = spawn(process.argv[1], ['30'], { detached: true, stdio: [0, 'ignore', 'ignore'] });
    writeFileSync(process.argv[2], String(child.pid));
    child.unref();
    """, runtime.path, pidFile.path]
  let handle = try #require(lease).inheritedFileHandle()
  supervisor.standardInput = handle
  try supervisor.run()
  try handle.close()
  supervisor.waitUntilExit()
  lease = nil
  let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
  defer { Darwin.kill(pid, SIGKILL) }
  // The supervisor can exit before its asynchronous child has exec'd the runtime.
  var ready = false
  for _ in 0..<100 {
    var info = proc_bsdinfo()
    var path = [CChar](repeating: 0, count: 4096)
    _ = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
    _ = proc_pidpath(pid, &path, UInt32(path.count))
    if info.pbi_ppid == 1, info.pbi_pgid == UInt32(pid),
      URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath() == runtime.resolvingSymlinksInPath() {
      ready = true
      break
    }
    try await Task.sleep(for: .milliseconds(10))
  }
  try #require(ready, "The orphan fixture must finish exec before checking recovery")
  #expect(throws: Error.self) { try DataDirectoryLease(directory: root) }
  // Finder replacement unlinks the old runtime while the orphan can still run.
  if replacingRuntime {
    try FileManager.default.removeItem(at: runtime)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: runtime)
  }
  #expect(await LocalBackendProcess.recoverOrphan(in: root, executable: URL(fileURLWithPath: "/bin/sleep")) == false)
  let other = root.appendingPathComponent("other")
  try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
  do {
    let otherLease = try DataDirectoryLease(directory: other)
    #expect(await LocalBackendProcess.recoverOrphan(in: otherLease.directory, executable: runtime) == false)
  }
  let recovered = await LocalBackendProcess.recoverOrphan(in: root, executable: runtime)
  #expect(recovered)
  for _ in 0..<100 {
    if (try? DataDirectoryLease(directory: root)) != nil { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  Issue.record("Orphan did not release its lock")
}
