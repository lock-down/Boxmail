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
    #expect(view.selectedRange() == NSRange(location: 0, length: 4))
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
    controller.setFontSize(24)
    controller.setColor("#B42318")
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
    controller.setFontSize(24)
    controller.setColor("#B42318")
    #expect(view.string == before)
    #expect(!controller.applyLink("https://example.test"))
    view.unmarkText()
  }

  @Test func sizeAndColorRespectMixedSelectionsPreserveOtherStylesAndUndoIndependently() throws {
    let (window, view, controller) = editor("")
    defer {
      window.contentView = nil
      window.close()
    }
    let original = RichTextDocument(blocks: [
      .init(runs: [
        .init(text: "重点", bold: true, link: "https://example.test", fontSize: 18, color: "#B42318"),
        .init(text: "普通"),
      ])
    ])
    let manager = try #require(window.undoManager)
    manager.groupsByEvent = false
    view.textStorage?.setAttributedString(RichTextCodec.attributed(original))
    view.setSelectedRange(NSRange(location: 0, length: 4))
    controller.updateSelection()
    #expect(controller.fontSize == nil && controller.hasMixedColor)
    performUndoableCommand(in: view, manager: manager) { controller.setFontSize(24) }
    let resized = RichTextCodec.document(try #require(view.textStorage))
    #expect(resized.blocks[0].runs.allSatisfy { $0.fontSize == 24 })
    #expect(
      resized.blocks[0].runs[0].bold && resized.blocks[0].runs[0].link == "https://example.test")
    #expect(resized.blocks[0].runs[0].color == "#B42318" && resized.blocks[0].runs[1].color == nil)
    #expect(controller.fontSize == 24 && controller.hasMixedColor)
    performUndoableCommand(in: view, manager: manager) { controller.setColor("#3567AF") }
    #expect(controller.color == "#3567AF" && !controller.hasMixedColor)
    #expect(view.selectedRange() == NSRange(location: 0, length: 4))
    window.undoManager?.undo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == resized)
    window.undoManager?.undo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == original)
    window.undoManager?.redo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == resized)
    view.setSelectedRange(NSRange(location: 0, length: 2))
    controller.updateSelection()
    performUndoableCommand(in: view, manager: manager) { controller.setColor(nil) }
    let reset = RichTextCodec.document(try #require(view.textStorage))
    #expect(reset.blocks[0].runs[0].color == nil && reset.blocks[0].runs[0].fontSize == 24)
    #expect(reset.blocks[0].runs[1].fontSize == 24)
  }

  @Test func insertionStylesOnlyAffectNewTextAndSurviveListConversions() throws {
    let (window, view, controller) = editor("原文")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: 2, length: 0))
    controller.setFontSize(20)
    controller.setColor("#6941C6")
    controller.toggleBold()
    view.insertText("新字", replacementRange: view.selectedRange())
    let value = RichTextCodec.document(try #require(view.textStorage))
    #expect(value.blocks[0].runs[0] == .init(text: "原文"))
    #expect(
      value.blocks[0].runs[1] == .init(text: "新字", bold: true, fontSize: 20, color: "#6941C6"))
    controller.updateSelection()
    controller.toggleList("bullet")
    #expect(
      RichTextCodec.document(try #require(view.textStorage)).blocks[0].runs == value.blocks[0].runs)
    controller.setFontSize(1000)
    controller.setColor("url(https://example.test)")
    #expect(
      RichTextCodec.document(try #require(view.textStorage)).blocks[0].runs == value.blocks[0].runs)
  }

  @Test func textKitUndoRestoresInsertedLinksAndListChangesWithTheirInlineStyles() throws {
    let (window, view, controller) = editor("说明")
    defer {
      window.contentView = nil
      window.close()
    }
    let manager = try #require(window.undoManager)
    manager.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 2, length: 0))
    controller.setFontSize(20)
    controller.setColor("#6941C6")
    performUndoableCommand(in: view, manager: manager) {
      #expect(controller.applyLink("https://example.test"))
    }
    let linked = RichTextCodec.document(try #require(view.textStorage))
    #expect(
      linked.blocks[0].runs.last?.fontSize == 20 && linked.blocks[0].runs.last?.color == "#6941C6")
    manager.undo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == .init(text: "说明"))
    manager.redo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == linked)
    controller.updateSelection()
    performUndoableCommand(in: view, manager: manager) { controller.toggleList("numbered") }
    #expect(view.string.hasPrefix("1. "))
    manager.undo()
    #expect(RichTextCodec.document(try #require(view.textStorage)) == linked)
    manager.redo()
    #expect(
      RichTextCodec.document(try #require(view.textStorage)).blocks[0].runs == linked.blocks[0].runs
    )
  }

  @Test(arguments: ["bullet", "numbered"])
  func listMarkerSizesFollowSelectedContentAndUndoWhileNewItemsKeepTheSameSize(kind: String) throws
  {
    let (window, view, controller) = editor("核对合同")
    defer {
      window.contentView = nil
      window.close()
    }
    let manager = try #require(window.undoManager)
    manager.groupsByEvent = false
    performUndoableCommand(in: view, manager: manager) { controller.toggleList(kind) }
    let selection = (view.string as NSString).range(of: "核对合同")
    view.setSelectedRange(selection)
    controller.updateSelection()
    performUndoableCommand(in: view, manager: manager) { controller.setFontSize(28) }
    let storage = try #require(view.textStorage)
    #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 28)
    #expect(view.selectedRange() == selection)
    manager.undo()
    #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 14)
    manager.redo()
    #expect((storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 28)
    view.setSelectedRange(NSRange(location: storage.length, length: 0))
    performUndoableCommand(in: view, manager: manager) { view.insertNewline(nil) }
    let nextMarker = (view.string as NSString).range(of: "\n").location + 1
    #expect(
      (storage.attribute(.font, at: nextMarker, effectiveRange: nil) as? NSFont)?.pointSize == 28)
    performUndoableCommand(in: view, manager: manager) {
      view.insertText("下一项", replacementRange: view.selectedRange())
    }
    let saved = RichTextCodec.document(storage)
    let reopened = RichTextCodec.attributed(saved)
    #expect(saved.blocks.count == 2 && saved.blocks.allSatisfy { $0.kind == kind })
    #expect(
      (reopened.attribute(.font, at: nextMarker, effectiveRange: nil) as? NSFont)?.pointSize == 28)
  }

  @Test func listConversionsPreserveContentSelectionAndSubsequentInsertion() throws {
    let (window, view, controller) = editor("核对合同\n第二段")
    defer {
      window.contentView = nil
      window.close()
    }
    view.setSelectedRange(NSRange(location: 1, length: 0))
    controller.toggleList("bullet")
    #expect(view.selectedRange() == NSRange(location: 3, length: 0))
    view.insertText("新", replacementRange: view.selectedRange())
    #expect(view.string == "• 核新对合同\n第二段")
    controller.updateSelection()
    controller.toggleList("bullet")
    #expect(view.selectedRange() == NSRange(location: 2, length: 0))
    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    controller.updateSelection()
    controller.toggleList("numbered")
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "核新对合同\n2. 第二段")
  }

  @Test func removingANumberedItemRenumbersOnlyMarkersAndPreservesUndo() throws {
    let (window, view, controller) = editor("第一项\n第二项\n第三项")
    defer {
      window.contentView = nil
      window.close()
    }
    let manager = try #require(window.undoManager)
    manager.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
    controller.updateSelection()
    performUndoableCommand(in: view, manager: manager) { controller.toggleList("numbered") }
    let before = view.string
    let removed = (view.string as NSString).range(of: "2. 第二项\n")
    performUndoableCommand(in: view, manager: manager) {
      view.insertText("", replacementRange: removed)
    }
    #expect(view.string == "1. 第一项\n2. 第三项")
    manager.undo()
    #expect(view.string == before)
    manager.redo()
    #expect(view.string == "1. 第一项\n2. 第三项")
  }

  @Test func coordinatorKeepsIncrementalBindingsCurrentAcrossTypingFormattingAndUndo() throws {
    let (window, view, controller) = editor("首段\n第二段\n第三段")
    defer { window.contentView = nil; window.close() }
    var body = view.string
    var document: RichTextDocument? = .init(text: body)
    let bridge = RichTextEditor(text: Binding(get: { body }, set: { body = $0 }),
      document: Binding(get: { document }, set: { document = $0 }), controller: controller,
      placeholder: "", accessibilityLabel: "测试正文", signature: "", onLink: {})
    let coordinator = bridge.makeCoordinator()
    view.delegate = coordinator
    view.textStorage?.delegate = coordinator
    coordinator.resetProjection(try #require(view.textStorage))
    let manager = try #require(window.undoManager)
    manager.groupsByEvent = false
    view.setSelectedRange(NSRange(location: 4, length: 0))
    performUndoableCommand(in: view, manager: manager) { view.insertText("插入𠀀", replacementRange: view.selectedRange()) }
    #expect(document == RichTextCodec.document(try #require(view.textStorage)))
    #expect(body == document?.plainText)
    performUndoableCommand(in: view, manager: manager) { view.insertNewline(nil) }
    #expect(document == RichTextCodec.document(try #require(view.textStorage)))
    view.setSelectedRange(NSRange(location: 0, length: 2))
    controller.updateSelection()
    performUndoableCommand(in: view, manager: manager) { controller.toggleBold() }
    #expect(document == RichTextCodec.document(try #require(view.textStorage)))
    manager.undo()
    #expect(document == RichTextCodec.document(try #require(view.textStorage)))
    manager.undo()
    #expect(document == RichTextCodec.document(try #require(view.textStorage)))
  }

  private func performUndoableCommand(
    in view: NSTextView, manager: UndoManager, _ command: () -> Void
  ) {
    // Each toolbar action normally has its own AppKit event; the fixture groups commands explicitly.
    manager.beginUndoGrouping()
    command()
    view.breakUndoCoalescing()
    manager.endUndoGrouping()
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
