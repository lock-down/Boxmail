import AppKit
import BoxmailCore
import SwiftUI

/// A nonactivating child window keeps suggestions out of the form's layout and
/// above sibling AppKit fields, while the original field editor owns the keyboard.
@MainActor final class RecipientSuggestionsPanel {
  private var panel: SuggestionsWindow?
  private weak var anchor: NSTextField?
  private var observers: [NSObjectProtocol] = []
  private var mouseMonitor: Any?
  private var dismissAction: (() -> Void)?

  func update(anchor: NSTextField, contacts: [ContactSuggestion], selected: Int,
    choose: @escaping (ContactSuggestion) -> Void, select: @escaping (Int) -> Void,
    dismiss: @escaping () -> Void) {
    guard !contacts.isEmpty, let parent = anchor.window,
      let editor = anchor.currentEditor(), editor === parent.firstResponder else { hide(); return }
    self.anchor = anchor
    dismissAction = dismiss
    let content = RecipientSuggestionList(contacts: contacts, selected: selected, choose: choose, select: select)
    if let panel, let host = panel.contentView as? NSHostingView<RecipientSuggestionList> {
      host.rootView = content
    } else {
      let window = SuggestionsWindow(contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
      window.isReleasedWhenClosed = false
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = true
      window.hidesOnDeactivate = true
      window.animationBehavior = .none
      window.collectionBehavior = [.transient, .ignoresCycle]
      window.title = "联系人建议"
      window.setAccessibilityLabel("联系人建议")
      window.contentView = NSHostingView(rootView: content)
      panel = window
      parent.addChildWindow(window, ordered: .above)
      observe(parent)
    }
    let width = min(520, max(320, anchor.bounds.width))
    panel?.setContentSize(NSSize(width: width, height: CGFloat(min(contacts.count, 5)) * 36 + 8))
    position()
    panel?.orderFront(nil)
  }

  func hide() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    mouseMonitor = nil
    dismissAction = nil
    if let panel {
      panel.parent?.removeChildWindow(panel)
      panel.close()
    }
    panel = nil
    anchor = nil
  }

  private func dismiss() {
    let action = dismissAction
    hide()
    action?()
  }

  private func observe(_ parent: NSWindow) {
    for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: parent,
        queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.position() } })
    }
    for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: parent,
        queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } })
    }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
      guard let self, event.window !== self.panel else { return event }
      if let anchor = self.anchor, event.window === anchor.window {
        let point = anchor.convert(event.locationInWindow, from: nil)
        if anchor.bounds.contains(point) { return event }
      }
      self.dismiss()
      return event
    }
  }

  private func position() {
    guard let panel, let anchor, let parent = anchor.window else { hide(); return }
    let field = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    let screen = parent.screen?.visibleFrame ?? field.insetBy(dx: -1000, dy: -1000)
    let size = panel.frame.size
    let x = min(max(field.minX, screen.minX + 8), screen.maxX - size.width - 8)
    let below = field.minY - size.height - 12
    let y = below >= screen.minY + 8 ? below : min(field.maxY + 12, screen.maxY - size.height - 8)
    let frame = NSRect(x: floor(x), y: floor(y), width: size.width, height: size.height)
    if panel.frame != frame { panel.setFrame(frame, display: true) }
  }
}

private final class SuggestionsWindow: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private struct RecipientSuggestionList: View {
  let contacts: [ContactSuggestion]
  let selected: Int
  let choose: (ContactSuggestion) -> Void
  let select: (Int) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      OverlayScrollView {
        VStack(spacing: 0) {
          ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
            Button { choose(contact) } label: {
              HStack(spacing: 16) {
                if !contact.name.isEmpty {
                  Text(contact.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(contact.email).font(.system(size: 12))
                  .foregroundStyle(contact.name.isEmpty ? Palette.ink : Palette.muted)
                  .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                  .frame(maxWidth: contact.name.isEmpty ? .infinity : nil, alignment: .leading)
              }.foregroundStyle(Palette.ink).padding(.horizontal, 10).frame(height: 36)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .background(index == selected ? Palette.blueSoft : .clear, in: RoundedRectangle(cornerRadius: 4))
            }.buttonStyle(.plain).focusable(false)
              .onHover { inside in if inside { select(index) } }
              .accessibilityLabel("选择联系人 \(contact.name) \(contact.email)")
              .accessibilityAddTraits(index == selected ? .isSelected : [])
              .id(contact.id)
          }
        }.padding(.horizontal, 4)
      }.padding(.vertical, 4)
        .onChange(of: selected) { _, index in
          if contacts.indices.contains(index) { proxy.scrollTo(contacts[index].id, anchor: .center) }
        }
        .onChange(of: contacts.map(\.id)) { _, ids in
          if let first = ids.first { proxy.scrollTo(first, anchor: .top) }
        }
    }.background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .accessibilityElement(children: .contain).accessibilityLabel("联系人建议")
  }
}
