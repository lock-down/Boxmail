import Darwin
import Foundation
import SQLite3

public struct DataDirectoryConfiguration: Codable, Equatable, Sendable {
  public var directory: String?
  public var pendingDirectory: String?

  public init(directory: String? = nil, pendingDirectory: String? = nil) {
    self.directory = directory
    self.pendingDirectory = pendingDirectory
  }

  public func resolvedDirectory(defaultDirectory: URL, override: String? = nil) throws -> URL {
    let path = override ?? directory
    guard let path else { return defaultDirectory.standardizedFileURL }
    guard path.hasPrefix("/"), !path.contains("\0") else {
      throw LocalDataStorage.failure("数据目录必须是绝对路径，请检查本机数据设置或 BOXMAIL_DATA。")
    }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }
}

/// The descriptor is also inherited by the backend, so an exiting app's service keeps its lease
/// until SQLite and outstanding work have actually closed.
public final class DataDirectoryLease: @unchecked Sendable {
  public let directory: URL
  private let descriptor: Int32

  public init(directory: URL, create: Bool = false) throws {
    let manager = FileManager.default
    if create {
      try manager.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    try LocalDataStorage.requireAvailable(directory)
    self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    let file = self.directory.appendingPathComponent(".boxmail.lock")
    let descriptor = Darwin.open(file.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw LocalDataStorage.failure("无法锁定数据目录，请检查文件夹权限：\(directory.path)")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(descriptor)
      throw NSError(domain: "Boxmail.Storage", code: 2, userInfo: [NSLocalizedDescriptionKey:
        "数据目录正在被另一个 Boxmail 进程使用，请关闭后重试。"])
    }
    self.descriptor = descriptor
  }

  public func inheritedFileHandle() throws -> FileHandle {
    let duplicate = dup(descriptor)
    guard duplicate >= 0 else { throw LocalDataStorage.failure("无法为本机服务保留数据目录锁。") }
    return FileHandle(fileDescriptor: duplicate, closeOnDealloc: true)
  }

  deinit { Darwin.close(descriptor) }
}

public enum LocalDataStorage {
  private static let ignored = Set([".DS_Store", ".boxmail.lock"])
  private static let databaseFiles = Set(["boxmail.sqlite", "boxmail.sqlite-wal", "boxmail.sqlite-shm"])

  public static func failure(_ message: String) -> NSError {
    NSError(domain: "Boxmail.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  public static func requireAvailable(_ directory: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw failure("数据目录不可用：\(directory.path)。请接入原磁盘或恢复文件夹后重试。")
    }
    guard FileManager.default.isReadableFile(atPath: directory.path),
      FileManager.default.isWritableFile(atPath: directory.path)
    else { throw failure("数据目录无法读写，请检查文件夹权限：\(directory.path)") }
    let values = try directory.resourceValues(forKeys: [.volumeIsLocalKey])
    guard values.volumeIsLocal != false else {
      throw failure("请选择本机或已挂载的本地磁盘文件夹，数据目录不支持网络磁盘。")
    }
  }

  public static func validateDestination(from source: URL, to destination: URL) throws -> URL {
    try requireAvailable(destination)
    let source = source.standardizedFileURL.resolvingSymlinksInPath()
    let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
    guard !overlaps(source, destination) else {
      throw failure("请选择独立的空文件夹，不能使用当前数据目录、它的子目录或上级目录。")
    }
    let entries = try FileManager.default.contentsOfDirectory(atPath: destination.path)
    guard entries.allSatisfy({ ignored.contains($0) }) else {
      throw failure("所选文件夹已有内容，请新建一个空文件夹；已有数据不会被覆盖。")
    }
    let probe = destination.appendingPathComponent(".boxmail-write-check-\(UUID().uuidString)")
    do {
      try Data().write(to: probe, options: [.withoutOverwriting])
      try FileManager.default.removeItem(at: probe)
    } catch {
      throw failure("无法写入所选文件夹，请检查磁盘空间和文件夹权限。")
    }
    return destination
  }

  /// Copies a closed store. The caller retains the source lease until the new backend is healthy.
  /// Only files created by this attempt are removed on failure; the source is always retained.
  public static func migrate(from source: DataDirectoryLease, to destination: URL) throws
    -> DataDirectoryLease
  {
    let manager = FileManager.default
    let destination = try validateDestination(from: source.directory, to: destination)
    let targetLease = try DataDirectoryLease(directory: destination)
    let entries = try manager.contentsOfDirectory(
      at: source.directory, includingPropertiesForKeys: nil)
      .filter { !ignored.contains($0.lastPathComponent) }
    guard entries.contains(where: { $0.lastPathComponent == "boxmail.sqlite" }) else {
      throw failure("原数据目录缺少 boxmail.sqlite，已保留原位置，请恢复数据文件后重试。")
    }
    var byteCount: Int64 = 0
    for entry in entries { byteCount += try inspect(entry) }
    if let free = try manager.attributesOfFileSystem(forPath: destination.path)[.systemFreeSize]
      as? NSNumber, free.int64Value < byteCount + 16 * 1024 * 1024
    { throw failure("目标磁盘空间不足，请释放空间或选择其他磁盘。") }

    let staging = destination.appendingPathComponent(".boxmail-migration-\(UUID().uuidString)")
    try manager.createDirectory(at: staging, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? manager.removeItem(at: staging) }
    var published: [URL] = []
    do {
      for entry in entries where !databaseFiles.contains(entry.lastPathComponent) {
        try manager.copyItem(at: entry, to: staging.appendingPathComponent(entry.lastPathComponent))
      }
      try copyDatabase(from: source.directory, staging: staging, destination: destination)
      try makePrivate(staging)
      // Recheck after copying: a user may have added files while migration was preparing.
      let current = try manager.contentsOfDirectory(atPath: destination.path)
      guard current.allSatisfy({ ignored.contains($0) || $0 == staging.lastPathComponent }) else {
        throw failure("目标文件夹在迁移期间新增了内容，已停止迁移，请重新选择空文件夹。")
      }
      let prepared = try manager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
      for entry in prepared {
        let final = destination.appendingPathComponent(entry.lastPathComponent)
        try manager.moveItem(at: entry, to: final)
        published.append(final)
      }
      return targetLease
    } catch {
      for file in published { try? manager.removeItem(at: file) }
      throw error
    }
  }

  private static func overlaps(_ a: URL, _ b: URL) -> Bool {
    func contains(_ ancestor: URL, _ child: URL) -> Bool {
      var current = child
      while true {
        if current.path == ancestor.path { return true }
        if let left = try? FileManager.default.attributesOfItem(atPath: ancestor.path),
          let right = try? FileManager.default.attributesOfItem(atPath: current.path),
          let leftFile = left[.systemFileNumber] as? NSNumber,
          let rightFile = right[.systemFileNumber] as? NSNumber,
          leftFile == rightFile,
          (left[.systemNumber] as? NSNumber) == (right[.systemNumber] as? NSNumber)
        { return true }
        if current.path == "/" || current.path.isEmpty { return false }
        let parent = (current.path as NSString).deletingLastPathComponent
        if parent == current.path || parent.isEmpty { return false }
        current = URL(fileURLWithPath: parent, isDirectory: true)
      }
    }
    return contains(a, b) || contains(b, a)
  }

  private static func inspect(_ url: URL) throws -> Int64 {
    let manager = FileManager.default
    let attributes = try manager.attributesOfItem(atPath: url.path)
    if attributes[.type] as? FileAttributeType == .typeDirectory {
      return try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        .reduce(0) { try $0 + inspect($1) }
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw failure("数据目录包含符号链接或特殊文件，已停止迁移：\(url.lastPathComponent)")
    }
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  private static func makePrivate(_ url: URL) throws {
    let manager = FileManager.default
    let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    try manager.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
    if isDirectory {
      for child in try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
        try makePrivate(child)
      }
    }
  }

  private static func copyDatabase(from source: URL, staging: URL, destination: URL) throws {
    var original: OpaquePointer?
    var copy: OpaquePointer?
    defer { sqlite3_close(original); sqlite3_close(copy) }
    // A closed WAL store may have no -wal/-shm files. SQLite must be allowed to recreate
    // its journal bookkeeping before backup; no source records are edited or created.
    guard sqlite3_open_v2(source.appendingPathComponent("boxmail.sqlite").path, &original,
      SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
      sqlite3_open(staging.appendingPathComponent("boxmail.sqlite").path, &copy) == SQLITE_OK,
      let backup = sqlite3_backup_init(copy, "main", original, "main")
    else { throw failure("无法读取原数据库，已保留原位置，请检查文件权限和数据库内容。") }
    sqlite3_busy_timeout(original, 100)
    sqlite3_busy_timeout(copy, 100)
    var result = sqlite3_backup_step(backup, -1)
    for _ in 0..<30 where result == SQLITE_BUSY || result == SQLITE_LOCKED {
      usleep(100_000)
      result = sqlite3_backup_step(backup, -1)
    }
    let finished = sqlite3_backup_finish(backup)
    guard result == SQLITE_DONE, finished == SQLITE_OK else {
      throw failure("数据库快照未完成，已保留原位置。请检查目录读写权限，并关闭其他 Boxmail 进程后重试。")
    }
    var check: OpaquePointer?
    defer { sqlite3_finalize(check) }
    guard sqlite3_prepare_v2(copy, "PRAGMA quick_check", -1, &check, nil) == SQLITE_OK,
      sqlite3_step(check) == SQLITE_ROW,
      String(cString: sqlite3_column_text(check, 0)) == "ok"
    else { throw failure("数据库完整性检查未通过，已停止迁移并保留原位置。") }
    sqlite3_finalize(check)
    check = nil

    var attachments: OpaquePointer?
    guard sqlite3_prepare_v2(copy, "SELECT id, data FROM records WHERE kind='attachment'", -1,
      &attachments, nil) == SQLITE_OK
    else { throw failure("数据库格式无法识别，已停止迁移并保留原位置。") }
    defer { sqlite3_finalize(attachments) }
    var updates: [(String, String)] = []
    var step = sqlite3_step(attachments)
    while step == SQLITE_ROW {
      let id = String(cString: sqlite3_column_text(attachments, 0))
      let json = String(cString: sqlite3_column_text(attachments, 1))
      guard var value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
        let path = value["path"] as? String, path.hasPrefix("/")
      else { throw failure("附件位置记录不完整，已停止迁移：\(id)") }
      let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      let prefix = source.path + "/"
      guard file.path.hasPrefix(prefix) else {
        throw failure("附件不在当前数据目录内，已停止迁移：\(value["name"] as? String ?? id)")
      }
      let relative = String(file.path.dropFirst(prefix.count))
      let stagedFile = staging.appendingPathComponent(relative)
      let attributes = try? FileManager.default.attributesOfItem(atPath: stagedFile.path)
      guard attributes?[.type] as? FileAttributeType == .typeRegular else {
        throw failure("附件文件缺失，已停止迁移：\(value["name"] as? String ?? id)。请恢复原文件后重试。")
      }
      value["path"] = destination.appendingPathComponent(relative).path
      let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
      updates.append((id, String(decoding: data, as: UTF8.self)))
      step = sqlite3_step(attachments)
    }
    guard step == SQLITE_DONE else { throw failure("附件记录读取失败，已停止迁移并保留原位置。") }
    sqlite3_finalize(attachments)
    attachments = nil
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (id, json) in updates {
      var statement: OpaquePointer?
      defer { sqlite3_finalize(statement) }
      guard sqlite3_prepare_v2(copy, "UPDATE records SET data=? WHERE kind='attachment' AND id=?",
        -1, &statement, nil) == SQLITE_OK,
        sqlite3_bind_text(statement, 1, json, -1, transient) == SQLITE_OK,
        sqlite3_bind_text(statement, 2, id, -1, transient) == SQLITE_OK,
        sqlite3_step(statement) == SQLITE_DONE
      else { throw failure("附件位置更新失败，已停止迁移并保留原位置。") }
    }
    guard sqlite3_exec(copy, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;", nil,
      nil, nil) == SQLITE_OK
    else { throw failure("无法完成数据库快照，已停止迁移并保留原位置。") }
  }
}
