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
  private var segment: RecipientCompletion.Segment { RecipientCompletion.segment(in: text, caret: caret) }
  private var requestKey: String { "\(accountID)\u{1f}\(text)\u{1f}\(caret)\u{1f}\(focused)" }
  private var visible: Bool { focused && showing && suppressed != text && !contacts.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      RecipientTextInput(text: $text, caret: caret, label: title, edit: { position in
        caret = position; showing = true; suppressed = nil
      }, focus: { value, position in
        focused = value; caret = position; showing = value; focusChanged(value)
      }, command: handle)
      .frame(height: 30)
      if visible {
        VStack(alignment: .leading, spacing: 0) {
          Text("联系人建议").font(UIType.small).foregroundStyle(Palette.muted)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
          ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
            Button { choose(contact) } label: {
              HStack(spacing: 10) {
                SenderAvatar(name: contact.name.isEmpty ? contact.email : contact.name, size: 26)
                VStack(alignment: .leading, spacing: 3) {
                  Text(contact.name.isEmpty ? contact.email : contact.name)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                  if !contact.name.isEmpty {
                    Text(contact.email).font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1)
                  }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if index == selected {
                  Image(systemName: "return").font(.system(size: 11)).foregroundStyle(Palette.blue)
                }
              }.foregroundStyle(Palette.ink).padding(.horizontal, 12).frame(height: 46)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .background(index == selected ? Palette.blueSoft : Palette.paper)
            }.buttonStyle(.plain).accessibilityLabel("选择联系人 \(contact.name) \(contact.email)")
              .accessibilityAddTraits(index == selected ? .isSelected : [])
          }
          Text("方向键选择 · Enter 或 Tab 填入 · Esc 关闭")
            .font(UIType.small).foregroundStyle(Palette.muted).padding(.horizontal, 12).padding(.vertical, 10)
        }.background(Palette.chrome, in: RoundedRectangle(cornerRadius: 8))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .padding(.top, 6).padding(.bottom, 8)
      }
    }
      .task(id: requestKey) { await suggest() }
  }
  private func suggest() async {
    guard focused, suppressed != text else { contacts = []; return }
    let key = requestKey
    let current = segment
    do {
      try await Task.sleep(for: .milliseconds(120))
      var query = URLComponents()
      query.queryItems = [URLQueryItem(name: "accountId", value: accountID), URLQueryItem(name: "q", value: current.query), URLQueryItem(name: "limit", value: "12")]
      let result: ContactsResponse = try await BackendService.shared.request("/contacts?" + (query.percentEncodedQuery ?? ""))
      try Task.checkCancellation()
      guard key == requestKey else { return }
      let remaining = (text as NSString).replacingCharacters(in: current.range, with: "")
      let excluded = RecipientCompletion.addresses(in: otherRecipients + [remaining])
      contacts = Array(result.contacts.filter { !excluded.contains($0.email.lowercased()) }.prefix(6))
      selected = 0
    } catch is CancellationError {} catch { contacts = [] }
  }
  private func choose(_ contact: ContactSuggestion) {
    let result = RecipientCompletion.replacing(text, segment: segment, name: contact.name, email: contact.email)
    text = result.text; caret = result.caret; suppressed = result.text
    contacts = []; showing = false
  }
  private func handle(_ command: String) -> Bool {
    if command == "cancelOperation:" { let handled = visible; showing = false; return handled }
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
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField()
    field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
    field.font = .systemFont(ofSize: 13)
    field.placeholderAttributedString = NSAttributedString(string: "姓名或邮箱地址，多个地址用逗号分隔",
      attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(Palette.muted)])
    field.setAccessibilityLabel(label)
    field.delegate = context.coordinator
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }
  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text {
      context.coordinator.updating = true
      defer { context.coordinator.updating = false }
      field.stringValue = text
      if let editor = field.currentEditor() {
        editor.string = text
        editor.selectedRange = NSRange(location: min(caret, (text as NSString).length), length: 0)
      }
    }
  }
  static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) { coordinator.stop() }
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: RecipientTextInput
    var selectionObserver: NSObjectProtocol?
    var updating = false
    init(_ parent: RecipientTextInput) { self.parent = parent }
    func stop() {
      if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
      selectionObserver = nil
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      guard let field = notification.object as? NSTextField, let editor = field.currentEditor() as? NSTextView else { return }
      parent.focus(true, editor.selectedRange().location)
      stop()
      selectionObserver = NotificationCenter.default.addObserver(forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main) { [weak self, weak editor] _ in
        guard let self, let editor, !self.updating else { return }
        self.parent.edit(editor.selectedRange().location)
      }
    }
    func controlTextDidEndEditing(_ notification: Notification) { stop(); parent.focus(false, parent.caret) }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      parent.text = field.stringValue
      parent.edit(field.currentEditor()?.selectedRange.location ?? (field.stringValue as NSString).length)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      parent.command(NSStringFromSelector(selector))
    }
  }
}
