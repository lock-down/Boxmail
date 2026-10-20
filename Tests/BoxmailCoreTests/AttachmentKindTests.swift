import Foundation
import Testing

@testable import BoxmailCore

@Test func attachmentTypesGroupOfficeFormatsAndRecognizeMIMEFallback() {
  #expect(AttachmentKind(name: "报告.PDF", contentType: "application/octet-stream") == .pdf)
  #expect(AttachmentKind(name: "合同.doc", contentType: "") == .word)
  #expect(AttachmentKind(name: "合同.docx", contentType: "") == .word)
  #expect(AttachmentKind(name: "账目.xls", contentType: "") == .spreadsheet)
  #expect(AttachmentKind(name: "账目.xlsx", contentType: "") == .spreadsheet)
  #expect(AttachmentKind(name: "账目.csv", contentType: "") == .spreadsheet)
  #expect(AttachmentKind(name: "演示.PPT", contentType: "") == .presentation)
  #expect(AttachmentKind(name: "演示.pptx", contentType: "") == .presentation)
  #expect(AttachmentKind(name: "幻灯片.ppsx", contentType: "") == .presentation)
  #expect(AttachmentKind(name: "未命名", contentType: "APPLICATION/VND.MS-POWERPOINT; name=slides") == .presentation)
  #expect(AttachmentKind(name: "数据", contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") == .spreadsheet)
  #expect(AttachmentKind(name: "报告.pdf", contentType: "application/msword") == .pdf)
  #expect(AttachmentKind(name: "图片.png", contentType: "") == .image)
  #expect(AttachmentKind(name: "说明.txt", contentType: "") == .text)
  #expect(AttachmentKind(name: "备份.zip", contentType: "application/zip") == .other)
}

@Test func emptyPresentationHeadersAllowAIWithoutMistakingLegacySheetsForXLSXPreview() throws {
  let raw = #"{"id":"ppt","messageId":"m1","name":"演示.PPTX","contentType":"application/octet-stream","path":"","text":"","parseError":"","date":"","size":1024,"hasExtractedText":false}"#
  var file = try JSONDecoder().decode(MailAttachment.self, from: Data(raw.utf8))
  #expect(file.isPresentation)
  #expect(file.canAnalyze)
  file.name = "旧格式.xls"
  #expect(file.isSpreadsheet)
  #expect(!file.usesWorkbookPreview)
  file.name = "新格式.xlsx"
  #expect(file.usesWorkbookPreview)
  file.name = "备份.zip"
  #expect(!file.canAnalyze)
}
