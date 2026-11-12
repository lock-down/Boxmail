import AppKit
import Foundation
import Testing

@testable import BoxmailCore

@Test @MainActor func incrementalDocumentsMatchFullProjectionAcrossUnicodeNewlinesAndUndoShapes() {
  let storage = NSMutableAttributedString(
    attributedString: RichTextCodec.attributed(.init(text: "首段𠀀\n第二段\n\n尾段\n")))
  let projection = RichTextDocumentProjection()
  projection.reset(storage)
  func replace(_ range: NSRange, _ value: String) {
    storage.replaceCharacters(in: range, with: value)
    let updated = projection.update(
      storage, editedRange: NSRange(location: range.location, length: value.utf16.count),
      changeInLength: value.utf16.count - range.length)
    #expect(updated == RichTextCodec.document(storage))
  }
  replace(NSRange(location: 2, length: 2), "𠀁新增")
  replace(NSRange(location: 1, length: 0), "分段\n\n新段")
  let newline = (storage.string as NSString).range(of: "\n")
  replace(newline, "")
  replace(NSRange(location: storage.length, length: 0), "末尾\n")
  replace(NSRange(location: 0, length: storage.length), "")
  replace(NSRange(location: 0, length: 0), "重写\n内容")
  storage.addAttribute(
    .font, value: NSFont.boldSystemFont(ofSize: 24),
    range: NSRange(location: 0, length: storage.length))
  #expect(projection.update(storage, editedRange: nil) == RichTextCodec.document(storage))
}

@Test @MainActor func incrementalProjectionPreservesUnchangedListNumbersAndInlineStyles() {
  let document = RichTextDocument(blocks: [
    .init(kind: "numbered", runs: [.init(text: "第一项", bold: true)]),
    .init(kind: "numbered", runs: [.init(text: "第二项", color: "#B42318")]),
    .init(kind: "numbered", runs: [.init(text: "第三项", link: "https://example.test")]),
  ])
  let storage = NSMutableAttributedString(attributedString: RichTextCodec.attributed(document))
  let projection = RichTextDocumentProjection()
  projection.reset(storage)
  let range = (storage.string as NSString).range(of: "第二项")
  storage.replaceCharacters(in: range, with: "编辑第二项")
  #expect(
    projection.update(
      storage, editedRange: NSRange(location: range.location, length: 5), changeInLength: 2)
      == RichTextCodec.document(storage))
}

@Test(arguments: ["A\nB\n", "A\nB\n\n", "A\n", "\n", "\n\n", "A\nB\nC\n"])
@MainActor func incrementalEditsPreserveTerminalEmptyParagraphs(text: String) {
  for position in 0...text.utf16.count {
    let storage = NSMutableAttributedString(string: text)
    let projection = RichTextDocumentProjection()
    projection.reset(storage)
    for iteration in 0..<12 {
      let location = min(position + iteration, storage.length)
      let inserted = iteration % 4 == 0 ? "x\n" : "y"
      storage.replaceCharacters(in: NSRange(location: location, length: 0), with: inserted)
      let updated = projection.update(
        storage,
        editedRange: NSRange(location: location, length: inserted.utf16.count),
        changeInLength: inserted.utf16.count)
      #expect(updated == RichTextCodec.document(storage))
      #expect(updated.plainText == storage.string)
    }
  }
}
