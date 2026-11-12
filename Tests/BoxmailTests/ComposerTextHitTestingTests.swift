import AppKit
import BoxmailCore
import Testing

@testable import Boxmail

@Suite(.serialized) @MainActor struct ComposerTextHitTestingTests {
  private let signature = "测试签名\n示例公司\ncontact@example.test"

  @Test(arguments: ["\n\n", "中文正文\n\n", String(repeating: "自动折行的正文内容", count: 12) + "\n\n"])
  func signatureSpacingBelongsToBodyHitTestingBeforeAndAfterResize(prefix: String) throws {
    let (window, scroll, view) = editor(prefix + signature)
    defer { window.contentView = nil; window.close() }
    let original = RichTextCodec.document(try #require(view.textStorage))
    let start = prefix.utf16.count
    for size in [NSSize(width: 680, height: 480), NSSize(width: 360, height: 620)] {
      scroll.setFrameSize(size)
      scroll.layoutSubtreeIfNeeded()
      view.updateBottomAnchor()
      let line = try characterRect(start, in: view)
      let bodyEnd = try characterRect(start - 1, in: view)
      #expect(line.minY - bodyEnd.maxY > 40)
      for y in [(bodyEnd.maxY + line.minY) / 2, line.minY - 8] {
        let point = NSPoint(x: view.textContainerOrigin.x + 100, y: y)
        #expect(view.characterIndexForInsertion(at: point) < start)
      }
      // A click on the actual signature must still put the caret inside the signature.
      let onSignature = NSPoint(x: line.midX, y: line.midY)
      #expect(view.characterIndexForInsertion(at: onSignature) >= start)
    }
    #expect(view.string == prefix + signature)
    #expect(RichTextCodec.document(try #require(view.textStorage)) == original)
  }

  @Test func typingInTheGapPreservesTheSignatureAndUndoAndDraftRoundTrip() throws {
    let prefix = "\n\n"
    let (window, _, view) = editor(prefix + signature)
    defer { window.contentView = nil; window.close() }
    let start = prefix.utf16.count
    let rect = try characterRect(start, in: view)
    let index = view.characterIndexForInsertion(at: NSPoint(x: rect.minX + 80, y: rect.minY - 20))
    #expect(index < start)
    view.setSelectedRange(NSRange(location: index, length: 0))
    view.insertText("新增正文", replacementRange: view.selectedRange())
    let saved = RichTextCodec.document(try #require(view.textStorage))
    #expect(saved.plainText.hasSuffix("\n" + signature))
    #expect(saved.plainText.components(separatedBy: signature).count == 2)
    #expect(RichTextCodec.attributed(saved).string == view.string)
    window.undoManager?.undo()
    #expect(view.string == prefix + signature)
  }

  @Test func editingAndUndoingTheSignatureRestoresBodyHitTesting() throws {
    let prefix = "\n\n"
    let (window, _, view) = editor(prefix + signature)
    defer { window.contentView = nil; window.close() }
    view.setSelectedRange(NSRange(location: prefix.utf16.count + 2, length: 0))
    view.insertText("修改", replacementRange: view.selectedRange())
    window.undoManager?.undo()
    #expect(view.string == prefix + signature)
    let rect = try characterRect(prefix.utf16.count, in: view)
    let point = NSPoint(x: rect.minX + 80, y: rect.minY - 20)
    #expect(view.characterIndexForInsertion(at: point) < prefix.utf16.count)
  }

  private func characterRect(_ index: Int, in view: NSTextView) throws -> NSRect {
    let manager = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    manager.ensureLayout(for: container)
    let glyph = manager.glyphIndexForCharacter(at: index)
    return manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
      .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
  }

  private func editor(_ text: String) -> (NSWindow, EditorScrollView, RichComposerTextView) {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scroll = EditorScrollView(frame: window.contentView!.bounds)
    scroll.hasVerticalScroller = true
    let view = RichComposerTextView(frame: scroll.contentView.bounds)
    view.isRichText = true
    view.isEditable = true
    view.allowsUndo = true
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.autoresizingMask = [.width]
    view.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = true
    view.textContainer?.heightTracksTextView = false
    view.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
    view.textContainer?.lineFragmentPadding = 0
    view.font = .systemFont(ofSize: 14)
    view.textContainerInset = NSSize(width: 24, height: 18)
    view.textStorage?.setAttributedString(RichTextCodec.attributed(.init(text: text)))
    view.bottomAnchoredText = signature
    scroll.documentView = view
    window.contentView = scroll
    scroll.layoutSubtreeIfNeeded()
    view.updateBottomAnchor()
    window.makeFirstResponder(view)
    return (window, scroll, view)
  }
}
