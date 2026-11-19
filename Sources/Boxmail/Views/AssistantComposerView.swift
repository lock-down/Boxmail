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
    }.padding(4).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
      .overlay { RoundedRectangle(cornerRadius: UILayout.radius).strokeBorder(Palette.border, lineWidth: 1) }
  }

  @ViewBuilder private var sendControls: some View {
      if workspace.askingSessionID != nil {
        ActionButton(title: "停止", icon: "stop.fill", size: .compact, help: "停止回答") {
          Task { await workspace.stop() }
        }.disabled(workspace.stopping)
      } else {
        HStack(spacing: 0) {
          Button(action: sendIfReady) {
            HStack(spacing: 6) {
              Text(shortcut.keycap).font(UIType.small)
              Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            }.foregroundStyle(canSend ? Color.white : Palette.muted)
              .padding(.horizontal, 8).frame(height: 24)
          }.buttonStyle(ControlFeedback(emphasis: canSend ? .primary : .plain)).controlFocus()
            .disabled(!canSend).accessibilityLabel("发送问题")
            .help("\(shortcut.title)，\(shortcut.newlineHint)")
          Menu {
            ForEach(TextSubmitShortcut.allCases, id: \.self) { value in
              Button { shortcut = value } label: {
                if value == shortcut { Label(value.title, systemImage: "checkmark") }
                else { Text(value.title) }
              }
            }
          } label: {
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
              .foregroundStyle(Palette.muted).frame(width: 22, height: 28)
          }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("\(shortcut.title)，\(shortcut.newlineHint)").accessibilityLabel("选择发送快捷键")
        }
      }
  }

  private func sendIfReady() {
    if canSend { Task { await workspace.ask(scope: scope) } }
  }
}
