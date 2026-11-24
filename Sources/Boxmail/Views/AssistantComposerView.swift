import BoxmailCore
import SwiftUI

struct AssistantComposerView: View {
  @Bindable var workspace: AssistantWorkspaceStore
  let scope: AssistantScope
  let canSubmit: Bool
  @AppStorage("assistantSubmitShortcut") private var shortcut = TextSubmitShortcut.returnKey
  private var canSend: Bool { canSubmit && workspace.canAsk }

  var body: some View {
    VStack(spacing: 0) {
      PlainTextEditor(text: $workspace.prompt,
        placeholder: scope.kind == "attachments" ? "输入要比较的内容" : "询问邮件或附件",
        fontSize: 13, inset: .init(width: 8, height: 8),
        accessibilityLabel: "邮件助手问题", submitShortcut: canSubmit ? shortcut : nil,
        onSubmit: sendIfReady)
        .frame(height: 76)
      HStack(spacing: 4) {
        Spacer(minLength: 0)
        sendControls
      }.padding(.trailing, 4)
    }.padding(4).framedSurface()
  }

  @ViewBuilder private var sendControls: some View {
      if workspace.askingSessionID != nil {
        ActionButton(title: "停止", icon: .stopFill, size: .compact, help: "停止回答") {
          Task { await workspace.stop() }
        }.disabled(workspace.stopping)
      } else {
        HStack(spacing: 0) {
          Button(action: sendIfReady) {
            HStack(spacing: 6) {
              Text(shortcut.keycap).font(UIType.small)
              RemixIcon(.arrowUpLine, size: 12)
                .accessibilityHidden(true)
            }.foregroundStyle(canSend ? Palette.primaryForeground : Palette.muted)
              .padding(.horizontal, 8).frame(height: 24)
          }.buttonStyle(ControlFeedback(emphasis: canSend ? .primary : .plain)).controlFocus()
            .disabled(!canSend).accessibilityLabel("发送问题")
            .cossTooltip("\(shortcut.title)，\(shortcut.newlineHint)")
          CossMenu(title: "选择发送快捷键", value: shortcut.title, prefersSelection: true) {
            for value in TextSubmitShortcut.allCases {
              CossMenuItem.command(value.title, mark: .choice(value == shortcut)) { shortcut = value }
            }
          } trigger: {
            RemixIcon(.arrowDownSLine, size: 9)
              .foregroundStyle(Palette.muted).frame(width: 22, height: 28)
          }.cossTooltip("\(shortcut.title)，\(shortcut.newlineHint)")
        }
      }
  }

  private func sendIfReady() {
    if canSend { Task { await workspace.ask(scope: scope) } }
  }
}
