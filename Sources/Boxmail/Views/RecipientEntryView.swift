import AppKit
import BoxmailCore
import SwiftUI

struct RecipientEntryView: View {
  let title, accountID: String
  @Binding var text: String
  let otherRecipients: [String]
  let focusChanged: (Bool) -> Void
  @ViewState<Int> private var caret = 0
  @ViewState<Bool> private var focused = false
  @ViewState<Bool> private var showing = false
  @ViewState<[ContactSuggestion]> private var contacts = []
  @ViewState<Int> private var selected = 0
  @ViewState<String?> private var suppressed = nil
  @ViewState<String> private var matchedRequest = ""
  private var segment: RecipientCompletion.Segment { RecipientCompletion.segment(in: text, caret: caret) }
  private var requestKey: String {
    "\(accountID)\u{1f}\(text)\u{1f}\(caret)\u{1f}\(focused)\u{1f}\(otherRecipients.joined(separator: "\u{1f}"))"
  }
  private var visible: Bool {
    focused && showing && suppressed != text && matchedRequest == requestKey
      && !segment.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !contacts.isEmpty
  }

  var body: some View {
    RecipientTextInput(text: $text, caret: caret, label: title, edit: { position in
        caret = position; showing = true; suppressed = nil
      }, focus: { value, position in
        focused = value; caret = position; showing = value; focusChanged(value)
        if !value { dismissSuggestions() }
      }, command: handle, contacts: visible ? contacts : [], selected: selected,
      choose: choose, select: { selected = $0 }, dismissSuggestions: dismissSuggestions)
      .frame(height: 30)
      .task(id: requestKey) { await suggest() }
  }
  private func dismissSuggestions() {
    showing = false; contacts = []; matchedRequest = ""
  }
  private func suggest() async {
    contacts = []; matchedRequest = ""
    guard focused, showing, suppressed != text,
      !segment.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let key = requestKey
    let current = segment
    do {
      try await Task.sleep(for: .milliseconds(120))
      var query = URLComponents()
      query.queryItems = [URLQueryItem(name: "accountId", value: accountID), URLQueryItem(name: "q", value: current.query), URLQueryItem(name: "limit", value: "12")]
      let result: ContactsResponse = try await BackendService.shared.request("/contacts?" + (query.percentEncodedQuery ?? ""))
      try Task.checkCancellation()
      guard key == requestKey, focused, showing, suppressed != text else { return }
      let remaining = (text as NSString).replacingCharacters(in: current.range, with: "")
      let excluded = RecipientCompletion.addresses(in: otherRecipients + [remaining])
      contacts = Array(result.contacts.filter { !excluded.contains($0.email.lowercased()) }.prefix(6))
      selected = 0
      matchedRequest = key
    } catch is CancellationError {} catch { if key == requestKey { contacts = []; matchedRequest = "" } }
  }
  private func choose(_ contact: ContactSuggestion) {
    let result = RecipientCompletion.replacing(text, segment: segment, name: contact.name, email: contact.email)
    text = result.text; caret = result.caret; suppressed = result.text
    dismissSuggestions()
  }
  private func handle(_ command: String) -> Bool {
    if command == "cancelOperation:" { let handled = visible; dismissSuggestions(); return handled }
    guard visible else { return false }
    switch command {
    case "moveDown:": selected = (selected + 1) % contacts.count; return true
    case "moveUp:": selected = (selected + contacts.count - 1) % contacts.count; return true
    case "insertNewline:", "insertTab:": choose(contacts[selected]); return true
    default: return false
    }
  }
}

private struct RecipientTextInput: NSViewRepresentable {
  @Binding var text: String
  let caret: Int
  let label: String
  let edit: (Int) -> Void
  let focus: (Bool, Int) -> Void
  let command: (String) -> Bool
  let contacts: [ContactSuggestion]
  let selected: Int
  let choose: (ContactSuggestion) -> Void
  let select: (Int) -> Void
  let dismissSuggestions: () -> Void
  @Environment(\.isEnabled) private var enabled
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> RecipientTextField {
    let field = RecipientTextField()
    field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.textColor = NSColor(Palette.ink)
    field.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.placeholderAttributedString = NSAttributedString(string: "姓名或邮箱地址，多个地址用逗号分隔",
      attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(Palette.muted)])
    field.setAccessibilityLabel(label)
    field.delegate = context.coordinator
    field.focusChanged = { [weak coordinator = context.coordinator] field, focused in
      coordinator?.focusChanged(field, focused: focused)
    }
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }
  func updateNSView(_ field: RecipientTextField, context: Context) {
    context.coordinator.parent = self
    field.isEnabled = enabled
    if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
      context.coordinator.updating = true
      defer { context.coordinator.updating = false }
      field.stringValue = text
      if let editor = field.currentEditor() {
        editor.string = text
        editor.selectedRange = NSRange(location: min(caret, (text as NSString).length), length: 0)
      }
    }
    context.coordinator.updateSuggestions(for: field)
  }
  static func dismantleNSView(_ field: RecipientTextField, coordinator: Coordinator) {
    field.stopObserving()
    coordinator.dismantle()
  }
  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: RecipientTextInput
    var selectionObserver: NSObjectProtocol?
    var activityObservers: [NSObjectProtocol] = []
    var updating = false
    let suggestions = RecipientSuggestionsPanel()
    private var suggestionUpdatePending = false
    private var dismantled = false
    init(_ parent: RecipientTextInput) { self.parent = parent }
    func stop() {
      if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
      selectionObserver = nil
      for observer in activityObservers { NotificationCenter.default.removeObserver(observer) }
      activityObservers.removeAll()
    }
    func dismantle() {
      dismantled = true
      stop()
      suggestions.hide()
    }
    func updateSuggestions(for field: NSTextField) {
      guard !dismantled, !suggestionUpdatePending else { return }
      suggestionUpdatePending = true
      DispatchQueue.main.async { [weak self, weak field] in
        guard let self else { return }
        self.suggestionUpdatePending = false
        guard !self.dismantled else { return }
        guard let field, field.window != nil, field.isEnabled else { self.suggestions.hide(); return }
        self.suggestions.update(anchor: field, contacts: self.parent.contacts, selected: self.parent.selected,
          choose: { [weak self] contact in
            self?.suggestions.hide()
            self?.parent.choose(contact)
          }, select: { [weak self] index in self?.parent.select(index) },
          dismiss: { [weak self] in self?.parent.dismissSuggestions() })
      }
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      focusChanged(field, focused: true)
    }
    func focusChanged(_ field: NSTextField, focused: Bool) {
      stop()
      guard focused, let editor = field.currentEditor() as? NSTextView else {
        suggestions.hide()
        parent.focus(false, parent.caret)
        return
      }
      parent.focus(true, editor.selectedRange().location)
      for (name, object) in [(NSWindow.didResignKeyNotification, field.window as AnyObject?),
        (NSApplication.didResignActiveNotification, NSApp as AnyObject?)] {
        activityObservers.append(NotificationCenter.default.addObserver(forName: name, object: object,
          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
              self?.suggestions.hide()
              self?.parent.dismissSuggestions()
            }
          })
      }
      selectionObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main) { [weak self, weak editor] _ in
        MainActor.assumeIsolated {
          guard let self, let editor, !self.updating, !editor.hasMarkedText() else { return }
          self.parent.edit(editor.selectedRange().location)
        }
      }
    }
    func controlTextDidEndEditing(_ notification: Notification) { stop(); parent.focus(false, parent.caret) }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else {
        suggestions.hide(); parent.dismissSuggestions(); return
      }
      parent.text = field.stringValue
      parent.edit(field.currentEditor()?.selectedRange.location ?? (field.stringValue as NSString).length)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      guard !textView.hasMarkedText() else { return false }
      return parent.command(NSStringFromSelector(selector))
    }
  }
}

/// NSTextField's editing delegate starts on the first text change. Report native
/// first-responder changes as well, so clicking or tabbing into an empty field has focus feedback.
private final class RecipientTextField: NSTextField {
  var focusChanged: ((NSTextField, Bool) -> Void)?
  private var windowObserver: NSObjectProtocol?
  private var reportedFocus = false
  private var refreshPending = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    stopObserving()
    guard let window else { return }
    windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification,
      object: window, queue: .main) { [weak self] _ in self?.scheduleFocusUpdate() }
    scheduleFocusUpdate()
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    scheduleFocusUpdate()
    return result
  }
  private func scheduleFocusUpdate() {
    guard !refreshPending else { return }
    refreshPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.refreshPending = false
      let editor = self.currentEditor()
      let focused = editor != nil && self.window?.firstResponder === editor
      guard focused != self.reportedFocus else { return }
      self.reportedFocus = focused
      self.focusChanged?(self, focused)
    }
  }
  func stopObserving() {
    if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    windowObserver = nil
  }
}
