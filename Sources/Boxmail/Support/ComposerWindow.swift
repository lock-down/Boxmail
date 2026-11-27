import AppKit
import BoxmailCore
import SwiftUI

private struct DismissComposerKey: EnvironmentKey {
  static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
  var dismissComposer: () -> Void {
    get { self[DismissComposerKey.self] }
    set { self[DismissComposerKey.self] = newValue }
  }
}

@MainActor final class ComposerWindow {
  private var window: ComposerPanel?
  private weak var sourceWindow: NSWindow?

  var isOpen: Bool { window != nil }

  func bringToFront() { window?.makeKeyAndOrderFront(nil) }

  func closeForTermination() async -> Bool {
    guard let window else { return true }
    bringToFront()
    return await window.saveAndClose()
  }

  func open(_ draft: MailDraft, store: MailStore, from source: NSWindow) {
    guard window == nil, store.composer?.id == draft.id else { return }
    let screen = (source.screen ?? NSScreen.main)?.visibleFrame ?? source.frame
    let size = WorkspaceWindowLayout.composer.size(in: screen.size)
    let panel = ComposerPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
      backing: .buffered, defer: false)
    panel.title = "写邮件"
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.isRestorable = false
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.contentViewController = NSHostingController(rootView:
      ComposerView(store: store, initial: draft, sendPlan: store.composerSendPlan)
        .environment(\.dismissComposer, { [weak self, weak store] in
          store?.composer = nil
          self?.close()
        })
        .environment(\.workspaceViewport, size)
        .preferredColorScheme(.light)
        .foregroundStyle(Palette.ink).tint(Palette.accent)
        .toggleStyle(CossToggleStyle()).disclosureGroupStyle(SettingsDisclosureStyle())
        .frame(width: size.width, height: size.height)
        .background(Palette.paper))
    // Keep the clipping and border on the fixed AppKit backing layer, outside the editor layout.
    if let view = panel.contentView {
      view.wantsLayer = true
      view.layer?.cornerRadius = UILayout.workspaceRadius
      view.layer?.cornerCurve = .continuous
      view.layer?.masksToBounds = true
      view.layer?.borderWidth = 1
      view.layer?.borderColor = NSColor(Palette.border).cgColor
    }
    panel.setFrameOrigin(NSPoint(
      x: max(screen.minX, min(source.frame.midX - size.width / 2, screen.maxX - size.width)),
      y: max(screen.minY, min(source.frame.midY - size.height / 2, screen.maxY - size.height))))
    sourceWindow = source
    window = panel
    panel.makeKeyAndOrderFront(nil)
  }

  private func close() {
    guard let window else { return }
    let wasKey = window.isKeyWindow
    self.window = nil
    window.close()
    window.contentViewController = nil
    if wasKey, sourceWindow?.isVisible == true { sourceWindow?.makeKeyAndOrderFront(nil) }
    sourceWindow = nil
  }
}

/// Locates the originating window for initial placement. The composer has an independent lifetime.
struct ComposerWindowAnchor: NSViewRepresentable {
  let store: MailStore
  let draft: MailDraft?

  func makeNSView(context: Context) -> ComposerAttachmentView { ComposerAttachmentView() }

  func updateNSView(_ view: ComposerAttachmentView, context: Context) {
    let composerWindow = store.composerWindow
    guard let draft, !composerWindow.isOpen else {
      view.attach = nil
      return
    }
    view.attach = { source in composerWindow.open(draft, store: store, from: source) }
    view.scheduleAttachment()
  }

  static func dismantleNSView(_ view: ComposerAttachmentView, coordinator: ()) { view.attach = nil }
}

extension View {
  func composerDragRegion() -> some View {
    overlay { ComposerDragRegion().accessibilityHidden(true) }
  }

  func composerCloseDisabled(_ disabled: Bool, action: @escaping () async -> Bool) -> some View {
    background { ComposerCloseControl(disabled: disabled, action: action) }
  }
}

final class ComposerAttachmentView: NSView {
  var attach: ((NSWindow) -> Void)?
  private var attachmentPending = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    scheduleAttachment()
  }

  func scheduleAttachment() {
    guard window != nil, attach != nil, !attachmentPending else { return }
    attachmentPending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      attachmentPending = false
      if let window { attach?(window) }
    }
  }
}

private final class ComposerPanel: NSWindow {
  var closeDisabled = false
  var requestClose: (() async -> Bool)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func performClose(_ sender: Any?) {
    Task { await saveAndClose() }
  }

  func saveAndClose() async -> Bool {
    guard !closeDisabled, attachedSheet == nil, let requestClose else { return false }
    return await requestClose()
  }

  override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(performClose(_:)) {
      return !closeDisabled && attachedSheet == nil
    }
    return super.validateMenuItem(menuItem)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
    if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
      performClose(nil)
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private struct ComposerDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ view: DragView, context: Context) {}

  final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
    }
  }
}

private struct ComposerCloseControl: NSViewRepresentable {
  let disabled: Bool
  let action: () async -> Bool

  func makeNSView(context: Context) -> ComposerAttachmentView { ComposerAttachmentView() }

  func updateNSView(_ view: ComposerAttachmentView, context: Context) {
    view.attach = { window in
      guard let panel = window as? ComposerPanel else { return }
      panel.closeDisabled = disabled
      panel.requestClose = action
    }
    view.scheduleAttachment()
  }
}
