import AppKit
import BoxmailCore
import SwiftUI
import Testing

@testable import Boxmail

@Suite(.serialized) @MainActor struct RichTextEditorTests {
  @Test func formattingPreservesTheSelectionAndUndoRestoresTheOriginalContent() throws {
    let (window, view, controller) = editor("中文正文\n第二行")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: 0, length: 4))
    controller.updateSelection()
    controller.toggleBold()
    let document = RichTextCodec.document(try #require(view.textStorage))
    #expect(document.blocks[0].runs[0].bold)
    #expect(view.selectedRange() == NSRange(location: 0, length: 4))
    #expect(view.string == "中文正文\n第二行")
    window.undoManager?.undo()
    #expect(!RichTextCodec.document(try #require(view.textStorage)).blocks[0].runs[0].bold)
    #expect(view.string == "中文正文\n第二行")
  }

  @Test func listsContinueOnReturnAndEmptyItemsExitTheListWithoutSavingLayoutSpacers() throws {
    let (window, view, controller) = editor("核对合同")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: 0, length: 0))
    controller.updateSelection()
    controller.toggleList("bullet")
    #expect(view.string == "• 核对合同")
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.insertNewline(nil)
    #expect(view.string == "• 核对合同\n• ")
    view.insertText("确认期限", replacementRange: view.selectedRange())
    let result = RichTextCodec.document(try #require(view.textStorage))
    #expect(result.blocks.map(\.kind) == ["bullet", "bullet"])
    #expect(result.blocks[1].runs.map(\.text).joined() == "确认期限")
    view.insertNewline(nil)
    controller.updateSelection()
    view.insertNewline(nil)
    #expect(!view.string.hasSuffix("• "))
  }

  @Test func linksAreEditableAndDisabledEditorsRejectFormatting() throws {
    let (window, view, controller) = editor("查看说明")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: 0, length: 4))
    #expect(!controller.applyLink("javascript:alert(1)"))
    #expect(controller.applyLink("https://example.test/help"))
    let document = RichTextCodec.document(try #require(view.textStorage))
    #expect(document.blocks[0].runs[0].link == "https://example.test/help")
    view.isEditable = false
    controller.toggleList("numbered")
    controller.toggleBold()
    #expect(!controller.applyLink("https://example.test/changed"))
    #expect(RichTextCodec.document(try #require(view.textStorage)) == document)
  }

  @Test func markedTextIsNotReplacedByFormatting() throws {
    let (window, view, controller) = editor("已有正文")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    view.setMarkedText(
      "zhongwen", selectedRange: NSRange(location: 8, length: 0),
      replacementRange: view.selectedRange())
    #expect(view.hasMarkedText())
    let before = view.string
    controller.toggleBold()
    controller.toggleList("bullet")
    #expect(view.string == before)
    #expect(!controller.applyLink("https://example.test"))
    view.unmarkText()
  }

  private func editor(_ text: String) -> (NSWindow, RichComposerTextView, RichTextController) {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = RichComposerTextView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    view.isRichText = true
    view.isEditable = true
    view.allowsUndo = true
    view.textStorage?.setAttributedString(RichTextCodec.attributed(.init(text: text)))
    let controller = RichTextController()
    controller.textView = view
    view.controller = controller
    window.contentView = view
    window.makeFirstResponder(view)
    return (window, view, controller)
  }
}
