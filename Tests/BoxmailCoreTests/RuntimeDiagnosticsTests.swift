import Foundation
import Testing

@testable import BoxmailCore

@Test func decodingDiagnosticsKeepSchemaPathsWithoutValuesOrPrivateDictionaryKeys() throws {
  struct Container: Decodable { let messages: [String: [String]] }
  let data = Data(#"{"messages":{"private@example.test":[42]}}"#.utf8)
  do {
    _ = try JSONDecoder().decode(Container.self, from: data)
    Issue.record("A mismatched synthetic value must fail decoding")
  } catch {
    let fields = RuntimeDiagnostics.errorFields(error, responseData: data)
    #expect(fields["phase"] == "decode")
    #expect(fields["reason"] == "type_mismatch")
    #expect(fields["field"] == "$.messages.:key[0]")
    #expect(fields["expectedType"] == "string")
    #expect(fields["actualType"] == "number")
    #expect(!fields.description.contains("private@example.test"))
  }
}

@Test func decodingDiagnosticsIdentifyTheRecordAndMissingFieldWithoutExposingValues() throws {
  struct Envelope: Decodable {
    struct Message: Decodable { let uid: Int }
    let messages: [Message]
  }
  for raw in [
    #"{"messages":[{"id":"synthetic-mail","accountId":"synthetic-account","uid":"PRIVATE VALUE"}]}"#,
    #"{"messages":[{"id":"synthetic-mail","accountId":"synthetic-account"}]}"#,
  ] {
    let data = Data(raw.utf8)
    do {
      _ = try JSONDecoder().decode(Envelope.self, from: data)
      Issue.record("Synthetic invalid UID must fail decoding")
    } catch {
      let fields = RuntimeDiagnostics.errorFields(error, responseData: data)
      #expect(fields["field"] == "$.messages[0].uid")
      #expect(fields["record"] == RuntimeDiagnostics.accountReference("synthetic-mail"))
      #expect(fields["account"] == RuntimeDiagnostics.accountReference("synthetic-account"))
      #expect(fields["recordKind"] == "message")
      #expect(fields["actualType"] == (raw.contains("PRIVATE VALUE") ? "string" : "missing"))
      #expect(
        !fields.description.contains("PRIVATE VALUE")
          && !fields.description.contains("synthetic-mail"))
    }
  }
}

@Test func diagnosticLogsRotateAndRedactRequestData() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "BoxmailLogs-\(UUID())")
  defer { try? FileManager.default.removeItem(at: directory) }
  let logs = RuntimeDiagnostics(directory: directory, maxBytes: 600)
  for index in 0..<30 {
    logs.record(
      "api.failed",
      [
        "route": RuntimeDiagnostics.route("/messages/private@example.test?key=SECRET"),
        "account": RuntimeDiagnostics.accountReference("private@example.test"),
        "code": String(index),
        "body": "SECRET email body", "password": "SECRET", "apiKey": "SECRET",
      ])
  }
  await logs.flush()
  let files = try FileManager.default.contentsOfDirectory(
    at: directory.appendingPathComponent("logs"), includingPropertiesForKeys: nil)
  #expect(files.count == 3)
  for file in files {
    let data = try Data(contentsOf: file)
    #expect(data.count <= 600)
    let text = String(decoding: data, as: UTF8.self)
    #expect(!text.contains("SECRET") && !text.contains("private@example.test"))
    #expect(text.contains("/messages/:id"))
    let mode =
      try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
  }
  #expect(RuntimeDiagnostics.route("") == "/")
}

@Test func diagnosticArchiveExcludesCredentialsAndMailAndWorksWithoutBackend() async throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("BoxmailLogExport-\(UUID())")
  defer { try? fm.removeItem(at: root) }
  let logs = RuntimeDiagnostics(directory: root)
  logs.record("api.failed", ["code": "-1001", "route": "/sync-status"])
  await logs.flush()
  try Data("SECRET".utf8).write(to: root.appendingPathComponent(".env"))
  try Data("PRIVATE MAIL".utf8).write(to: root.appendingPathComponent("boxmail.sqlite"))
  let destination = root.appendingPathComponent("export.zip")
  let manifest = try DiagnosticArchive.manifest(
    version: "test", build: "35", connected: false, syncing: true, snapshot: nil)
  try DiagnosticArchive.export(from: root, to: destination, manifest: manifest)
  let listing = Process()
  let namesPipe = Pipe()
  listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
  listing.arguments = ["-Z", "-1", destination.path]
  listing.standardOutput = namesPipe
  try listing.run()
  let members = String(
    decoding: namesPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
  listing.waitUntilExit()
  #expect(!members.contains("._") && !members.contains("__MACOSX"))
  let output = root.appendingPathComponent("unpacked")
  let unzip = Process()
  unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
  unzip.arguments = ["-x", "-k", destination.path, output.path]
  try unzip.run()
  unzip.waitUntilExit()
  #expect(unzip.terminationStatus == 0)
  let folder = output.appendingPathComponent("Boxmail-Diagnostics")
  let names = try fm.contentsOfDirectory(atPath: folder.path)
  #expect(Set(names) == ["manifest.json", "README.txt", "app.jsonl"])
  let value = try #require(
    JSONSerialization.jsonObject(
      with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as? [String: Any])
  #expect(value["connected"] as? Bool == false)
  #expect(try fm.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int == 0o600)
}

@Test func diagnosticManifestKeepsCountersAndAnonymousCorrelationWithoutRawErrors() throws {
  let snapshot = try JSONDecoder().decode(
    MailSyncSnapshot.self,
    from: Data(
      #"{"runningAccounts":["private@example.test"],"folders":[{"id":"secret-path","accountId":"private@example.test","folder":"inbox","status":"failed","phase":"parse","total":1000,"downloaded":50,"lastError":"SECRET server response","remotePath":"SECRET folder"}],"results":[{"accountId":"private@example.test","status":"failed","error":"SECRET"}]}"#
        .utf8))
  let data = try DiagnosticArchive.manifest(
    version: "test", build: "35", connected: true, syncing: false, snapshot: snapshot)
  let text = String(decoding: data, as: UTF8.self)
  #expect(
    !text.contains("SECRET") && !text.contains("private@example.test")
      && !text.contains("secret-path"))
  #expect(
    text.contains("1000") && text.contains("50")
      && text.contains(RuntimeDiagnostics.accountReference("private@example.test")))
}

@Test func diagnosticExportRejectsLogSymlinks() async throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent("BoxmailLogLink-\(UUID())")
  defer { try? fm.removeItem(at: root) }
  try fm.createDirectory(at: root.appendingPathComponent("logs"), withIntermediateDirectories: true)
  let env = root.appendingPathComponent(".env")
  try Data("SECRET".utf8).write(to: env)
  try fm.createSymbolicLink(
    at: root.appendingPathComponent("logs/backend.jsonl"), withDestinationURL: env)
  #expect(throws: Error.self) {
    try DiagnosticArchive.export(
      from: root, to: root.appendingPathComponent("export.zip"), manifest: Data("{}".utf8))
  }
}
