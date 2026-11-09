import AppKit
import SwiftUI
import Testing
@testable import Boxmail

@Suite(.serialized) @MainActor struct RecipientEntryTests {
  @Test func emptyRecipientFocusChangesDoNotRetriggerNativeAutoFill() async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: fields(enabled: true))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 160),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    defer { window.contentView = nil; window.close() }

    let inputs = textFields(in: host)
    #expect(inputs.count == 3)
    var enabledChanges: [Bool] = []
    let observations = inputs.map { field in
      field.observe(\.isEnabled, options: [.new]) { _, change in
        MainActor.assumeIsolated {
          if let value = change.newValue { enabledChanges.append(value) }
        }
      }
    }
    defer { observations.forEach { $0.invalidate() } }

    // Exercise the real field editor and SwiftUI focus callbacks with empty input.
    for _ in 0..<2 {
      for input in inputs {
        #expect(window.makeFirstResponder(input))
        window.update()
        try await Task.sleep(for: .milliseconds(30))
        #expect(input.currentEditor() != nil)
        #expect(input.stringValue.isEmpty)
      }
    }
    #expect(enabledChanges.isEmpty)
    #expect(window.childWindows?.isEmpty != false)

    // Actual enable/disable transitions must still reach every native input.
    host.rootView = fields(enabled: false)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    #expect(inputs.allSatisfy { !$0.isEnabled })
    #expect(enabledChanges == [false, false, false])
    enabledChanges.removeAll()
    host.rootView = fields(enabled: true)
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(30))
    #expect(inputs.allSatisfy { $0.isEnabled })
    #expect(enabledChanges == [true, true, true])
  }

  private func fields(enabled: Bool) -> some View {
    VStack {
      ForEach(["收件人", "抄送", "密送"], id: \.self) { title in
        RecipientEntryView(title: title, accountID: "test", text: .constant(""),
          otherRecipients: ["", ""], focusChanged: { _ in })
      }
    }.disabled(!enabled)
  }

  private func textFields(in view: NSView) -> [NSTextField] {
    if let field = view as? NSTextField { return [field] }
    return view.subviews.flatMap { textFields(in: $0) }
  }
}
