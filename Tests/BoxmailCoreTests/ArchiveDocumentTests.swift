import Foundation
import Testing

@testable import BoxmailCore

@Test func archiveChildrenAndSourceReferencesRoundTripWithoutExpandingAttachmentHeaders() throws {
  let raw = """
    {"id":"a","messageId":"m","name":"项目.ZIP","contentType":"application/zip","path":"/synthetic/a.zip",
    "text":"","parseError":"","date":"2026-11-10T00:00:00Z","size":1024,"analysis":"资料包总结",
    "archive":{"hash":"hash","status":"completed","totalFiles":2,"omitted":0,
      "entries":[{"id":"0","path":"合同/采购.txt","name":"采购.txt","size":12,"contentType":"text/plain","status":"completed","analysis":"金额100元"},
      {"id":"1","path":"历史.zip","name":"历史.zip","size":20,"contentType":"application/zip","status":"unsupported","error":"嵌套压缩包"}],
      "summary":{"overview":"采购资料","groups":[{"title":"合同","entryIds":["0"]}],"findings":[{"text":"核对金额","entryIds":["0"]}],"actions":[]}}}
    """
  let file = try JSONDecoder().decode(MailAttachment.self, from: Data(raw.utf8))
  #expect(file.isArchive && file.canAnalyze && file.isAnalyzed)
  #expect(file.archive?.understoodCount == 1)
  #expect(file.isPartiallyAnalyzed && file.analysisStatusTitle == "部分理解")
  #expect(file.archive?.entries[0].canPreview == true)
  #expect(file.archive?.entries[1].canPreview == false)
  #expect(file.archive?.summary?.findings[0].entryIds == ["0"])
  #expect(try JSONDecoder().decode(MailAttachment.self, from: JSONEncoder().encode(file)) == file)
  #expect(file.compact.isPartiallyAnalyzed)
  #expect(file.compact.archive == nil && file.compact.isAnalyzed && file.compact.canAnalyze)
  #expect(AttachmentKind(name: "无扩展名", contentType: "APPLICATION/X-ZIP-COMPRESSED") == .archive)
}
