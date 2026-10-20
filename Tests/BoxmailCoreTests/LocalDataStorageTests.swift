import Foundation
import SQLite3
import Testing

@testable import BoxmailCore

private final class StorageFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("BoxmailStorage-\(UUID())")
  let source: URL
  let target: URL
  var db: OpaquePointer?

  init() throws {
    source = root.appendingPathComponent("原始 O'Brien 数据")
    target = root.appendingPathComponent("迁移后的邮件 data")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    guard sqlite3_open(source.appendingPathComponent("boxmail.sqlite").path, &db) == SQLITE_OK else {
      throw LocalDataStorage.failure("Test database could not open")
    }
    try exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; PRAGMA user_version=2; "
      + "CREATE TABLE records(kind TEXT, id TEXT, data TEXT, PRIMARY KEY(kind,id)); "
      + "CREATE TABLE events(id TEXT, time TEXT, type TEXT, detail TEXT); "
      + "INSERT INTO events VALUES('event','2026-10-20','sync','已保存的活动');")
    try put("account", "account", ["id": "account", "name": "本机测试"])
    try put("message", "message", ["id": "message", "body": "合同正文", "summary": ["overview": "已有总结"]])
    try put("draft", "draft", ["id": "draft", "body": "用户已编辑的草稿", "status": "uncertain"])
    try put("job", "job", ["id": "job", "status": "paused", "task": "attachmentBatch"])
    try put("mutation", "mutation", ["id": "mutation", "unread": false])
    try put("settings", "settings", ["id": "settings", "preferences": ["signature": "保留的签名"]])
    try FileManager.default.createDirectory(
      at: source.appendingPathComponent("attachments"), withIntermediateDirectories: true)
    let file = source.appendingPathComponent("attachments/合同.txt")
    try Data("原附件字节\0包含中文".utf8).write(to: file)
    try put("attachment", "attachment", ["id": "attachment", "name": "合同.txt", "path": file.path,
      "analysis": "已经理解的附件", "text": "可搜索的文本"])
    try FileManager.default.createDirectory(at: source.appendingPathComponent("backups"),
      withIntermediateDirectories: true)
    try Data("existing-backup".utf8).write(to: source.appendingPathComponent("backups/before-v2.sqlite"))
  }

  func exec(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
      throw LocalDataStorage.failure("Test SQL failed: \(String(cString: sqlite3_errmsg(db)))")
    }
  }
  func put(_ kind: String, _ id: String, _ value: [String: Any]) throws {
    let json = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    let escape: (String) -> String = { $0.replacingOccurrences(of: "'", with: "''") }
    try exec("INSERT OR REPLACE INTO records VALUES('\(escape(kind))','\(escape(id))','\(escape(json))')")
  }
  func close() { sqlite3_close(db); db = nil }
  deinit { close(); try? FileManager.default.removeItem(at: root) }
}

private func storedJSON(_ directory: URL, kind: String) throws -> [String: Any] {
  var db: OpaquePointer?
  defer { sqlite3_close(db) }
  #expect(sqlite3_open(directory.appendingPathComponent("boxmail.sqlite").path, &db) == SQLITE_OK)
  var statement: OpaquePointer?
  defer { sqlite3_finalize(statement) }
  #expect(sqlite3_prepare_v2(db, "SELECT data FROM records WHERE kind='\(kind)'", -1, &statement, nil) == SQLITE_OK)
  #expect(sqlite3_step(statement) == SQLITE_ROW)
  let text = String(cString: sqlite3_column_text(statement, 0))
  return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Test func dataDirectoryConfigurationHonorsOverrideAndRejectsRelativePaths() throws {
  let original = URL(fileURLWithPath: "/original")
  let config = DataDirectoryConfiguration(directory: "/custom", pendingDirectory: "/pending")
  #expect(try config.resolvedDirectory(defaultDirectory: original).path == "/custom")
  #expect(try config.resolvedDirectory(defaultDirectory: original, override: "/isolated").path == "/isolated")
  #expect(throws: Error.self) { try config.resolvedDirectory(defaultDirectory: original, override: "relative") }
  #expect(try JSONDecoder().decode(DataDirectoryConfiguration.self, from: JSONEncoder().encode(config)) == config)
}

@Test func dataDirectoryLeasePreventsConcurrentUseAndSurvivesInChild() throws {
  let fixture = try StorageFixture()
  var lease: DataDirectoryLease? = try DataDirectoryLease(directory: fixture.source)
  #expect(throws: Error.self) { try DataDirectoryLease(directory: fixture.source) }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/sleep")
  process.arguments = ["30"]
  let inherited = try #require(lease).inheritedFileHandle()
  process.standardInput = inherited
  try process.run()
  defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
  try inherited.close()
  lease = nil
  #expect(throws: Error.self) { try DataDirectoryLease(directory: fixture.source) }
  process.terminate()
  process.waitUntilExit()
  let reopened = try DataDirectoryLease(directory: fixture.source)
  #expect(reopened.directory == fixture.source.resolvingSymlinksInPath())
}

@Test func missingCustomDirectoryIsNotCreated() throws {
  let fixture = try StorageFixture()
  let missing = fixture.root.appendingPathComponent("missing-volume/mail")
  #expect(throws: Error.self) { try DataDirectoryLease(directory: missing) }
  #expect(!FileManager.default.fileExists(atPath: missing.path))
}

@Test func dataMigrationRejectsSameNestedAncestorAndSymlinkAliases() throws {
  let fixture = try StorageFixture()
  let child = fixture.source.appendingPathComponent("nested")
  try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
  let alias = fixture.root.appendingPathComponent("alias")
  try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.source)
  for destination in [fixture.source, child, fixture.root, alias] {
    #expect(throws: Error.self) {
      try LocalDataStorage.validateDestination(from: fixture.source, to: destination)
    }
  }
}

@Test func dataMigrationNeverOverwritesAnOccupiedDestination() throws {
  let fixture = try StorageFixture()
  let existing = fixture.target.appendingPathComponent("boxmail.sqlite")
  let original = Data("another mailbox must survive".utf8)
  try original.write(to: existing)
  let source = try DataDirectoryLease(directory: fixture.source)
  #expect(throws: Error.self) { try LocalDataStorage.migrate(from: source, to: fixture.target) }
  #expect(try Data(contentsOf: existing) == original)
  #expect(try storedJSON(fixture.source, kind: "draft")["status"] as? String == "uncertain")
}

@Test func dataMigrationIncludesWALRebasesAttachmentsAndRetainsAllRecordsAndSource() throws {
  let fixture = try StorageFixture()
  // Keep the source SQLite handle open: committed records are still in its WAL.
  #expect(FileManager.default.fileExists(atPath: fixture.source.appendingPathComponent("boxmail.sqlite-wal").path))
  let source = try DataDirectoryLease(directory: fixture.source)
  let target = try LocalDataStorage.migrate(from: source, to: fixture.target)
  for kind in ["account", "message", "draft", "job", "mutation", "settings"] {
    let old = try storedJSON(fixture.source, kind: kind) as NSDictionary
    let new = try storedJSON(fixture.target, kind: kind) as NSDictionary
    #expect(old == new)
  }
  let attachment = try storedJSON(fixture.target, kind: "attachment")
  let file = try #require(attachment["path"] as? String)
  #expect(file == target.directory.appendingPathComponent("attachments/合同.txt").path)
  #expect(attachment["analysis"] as? String == "已经理解的附件")
  #expect(try Data(contentsOf: URL(fileURLWithPath: file)) == Data(contentsOf: fixture.source.appendingPathComponent("attachments/合同.txt")))
  #expect(try Data(contentsOf: fixture.target.appendingPathComponent("backups/before-v2.sqlite")) == Data("existing-backup".utf8))
  let permissions = try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int
  #expect(permissions == 0o600)
  #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("boxmail.sqlite-wal").path))
  let entries = try FileManager.default.contentsOfDirectory(atPath: fixture.target.path)
  #expect(!entries.contains(where: { $0.hasPrefix(".boxmail-migration-") }))
  #expect(throws: Error.self) { try DataDirectoryLease(directory: fixture.target) }
}

@Test func dataMigrationRejectsMissingAndExternalAttachmentsWithoutPublishingPartialData() throws {
  for external in [false, true] {
    let fixture = try StorageFixture()
    if external {
      let outside = fixture.root.appendingPathComponent("outside.txt")
      try Data("outside".utf8).write(to: outside)
      try fixture.put("attachment", "attachment", ["id": "attachment", "name": "outside.txt", "path": outside.path])
    } else {
      try FileManager.default.removeItem(at: fixture.source.appendingPathComponent("attachments/合同.txt"))
    }
    let source = try DataDirectoryLease(directory: fixture.source)
    #expect(throws: Error.self) { try LocalDataStorage.migrate(from: source, to: fixture.target) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.target.path) == [".boxmail.lock"])
    #expect(try storedJSON(fixture.source, kind: "draft")["body"] as? String == "用户已编辑的草稿")
  }
}

@Test func dataMigrationReadsClosedWALDatabaseWithoutSidecars() throws {
  let fixture = try StorageFixture()
  try fixture.exec("PRAGMA wal_checkpoint(TRUNCATE)")
  fixture.close()
  for suffix in ["-wal", "-shm"] {
    let sidecar = fixture.source.appendingPathComponent("boxmail.sqlite" + suffix)
    if FileManager.default.fileExists(atPath: sidecar.path) {
      try FileManager.default.removeItem(at: sidecar)
    }
    #expect(!FileManager.default.fileExists(atPath: sidecar.path))
  }
  let source = try DataDirectoryLease(directory: fixture.source)
  let target = try LocalDataStorage.migrate(from: source, to: fixture.target)
  #expect(try storedJSON(target.directory, kind: "draft")["body"] as? String == "用户已编辑的草稿")
  #expect(try storedJSON(source.directory, kind: "draft")["body"] as? String == "用户已编辑的草稿")
}

@Test func dataMigrationRejectsCorruptDatabaseAndCleansItsStagingFiles() throws {
  let fixture = try StorageFixture()
  fixture.close()
  let invalid = Data("not a SQLite database".utf8)
  try invalid.write(to: fixture.source.appendingPathComponent("boxmail.sqlite"))
  let source = try DataDirectoryLease(directory: fixture.source)
  #expect(throws: Error.self) { try LocalDataStorage.migrate(from: source, to: fixture.target) }
  #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.target.path) == [".boxmail.lock"])
  #expect(try Data(contentsOf: fixture.source.appendingPathComponent("boxmail.sqlite")) == invalid)
}

@Test func dataMigrationRejectsLinkedFilesAndBusyTargets() throws {
  let fixture = try StorageFixture()
  let source = try DataDirectoryLease(directory: fixture.source)
  do {
    let busy = try DataDirectoryLease(directory: fixture.target)
    #expect(throws: Error.self) { try LocalDataStorage.migrate(from: source, to: busy.directory) }
  }
  try FileManager.default.createSymbolicLink(at: fixture.source.appendingPathComponent("linked-attachment"),
    withDestinationURL: fixture.root)
  #expect(throws: Error.self) { try LocalDataStorage.migrate(from: source, to: fixture.target) }
  #expect(!FileManager.default.fileExists(atPath: fixture.target.appendingPathComponent("boxmail.sqlite").path))
}
