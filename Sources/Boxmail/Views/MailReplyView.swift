import AppKit
import BoxmailCore
import SwiftUI

struct MailReplyView: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @ViewState<ReplyPreset?> private var selectedPreset: ReplyPreset?
  @ViewState<String> private var request = ""
  @ViewState<Set<String>> private var hiddenPreviews = []
  @FocusState private var requestFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var preview: AgentJob? {
    guard
      let latest = store.jobs.first(where: {
        $0.task == "reply" && $0.messageId == message.id && $0.preview == true
          && $0.status == "completed" && $0.replyPreset == selectedPreset?.rawValue
      }), !hiddenPreviews.contains(latest.id)
    else { return nil }
    return latest
  }
  var relatedDrafts: [MailDraft] {
    let ids = Set(
      store.jobs.filter { $0.task == "reply" && $0.messageId == message.id }
        .compactMap { $0.result?.draftId })
    return store.drafts.filter { $0.sourceMessageId == message.id && ids.contains($0.id) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("选择回复态度，一键生成预览").font(.system(size: 12, weight: .medium))
      HStack(spacing: 7) {
        ForEach(ReplyPreset.allCases) { preset in
          Button {
            selectedPreset = preset
            generate()
          } label: {
            Text(preset.title).font(.system(size: 11, weight: .medium))
              .foregroundStyle(selectedPreset == preset ? Palette.accent : Palette.ink)
              .frame(maxWidth: .infinity).frame(height: 34).contentShape(Rectangle())
              .background(
                selectedPreset == preset ? Palette.accentSoft : .white,
                in: RoundedRectangle(cornerRadius: 7)
              )
          }.buttonStyle(ControlFeedback(selected: selectedPreset == preset)).help(preset.detail)
            .controlFocus()
            .animation(UIMotion.selection(reduceMotion), value: selectedPreset == preset)
            .accessibilityAddTraits(selectedPreset == preset ? .isSelected : [])
            .disabled(store.busy.contains("agent"))
        }
      }
      HStack {
        Text(selectedPreset?.detail ?? "也可以直接填写回复要求").font(.system(size: 11)).foregroundStyle(
          Palette.muted)
        Spacer()
        if selectedPreset != nil {
          Button { selectedPreset = nil } label: {
            Text("改为自定义").font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Palette.accent)
              .padding(.horizontal, 6).padding(.vertical, 3)
              .contentShape(RoundedRectangle(cornerRadius: 5))
          }.buttonStyle(ControlFeedback(corner: 5)).controlFocus(corner: 5)
            .disabled(store.busy.contains("agent"))
        }
      }
      TextField(
        selectedPreset == nil ? "例如：确认收到，询问下一步安排" : "补充要求（可选），例如：语气简洁，控制在 100 字内", text: $request,
        axis: .vertical
      )
      .textFieldStyle(.plain).lineLimit(2...4).font(.system(size: 12)).foregroundStyle(Palette.ink)
      .padding(.horizontal, 11).padding(.vertical, 10)
      .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8).strokeBorder(
          requestFocused ? Palette.accent : Palette.accent.opacity(0.45),
          lineWidth: requestFocused ? 1.6 : 1.2)
      }
      .focused($requestFocused)
      .animation(UIMotion.feedback(reduceMotion), value: requestFocused)
      HStack {
        ActionButton(title: "生成回复预览", icon: "sparkles", kind: .ai) { generate() }
          .disabled(
            store.busy.contains("agent")
              || (selectedPreset == nil
                && request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
        Text("先预览，再使用").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
      if let output = store.aiOutput(task: "reply", messageId: message.id) {
        AIStreamingView(output: output)
      } else if let preview, let result = preview.result {
        VStack(alignment: .leading, spacing: 13) {
          HStack {
            Text(
              (preview.replyPreset.flatMap(ReplyPreset.init(rawValue:))?.title ?? "自定义回复") + " · 预览"
            )
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
            Spacer()
            CopyButton(help: "复制回复预览") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(result.body ?? "", forType: .string)
            }
            IconButton(icon: "xmark", help: "关闭回复预览") { hiddenPreviews.insert(preview.id) }
          }
          Divider()
          Text(result.subject ?? "").font(.system(size: 12, weight: .medium)).textSelection(
            .enabled)
          Text(result.body ?? "").font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack {
            ActionButton(title: "使用内容", icon: "square.and.pencil", kind: .ai) {
              store.useReply(preview)
            }
            .disabled(store.busy.contains("agent") || store.busy.contains("use-reply"))
            ActionButton(title: "重新生成", icon: "arrow.clockwise") { generate() }
              .disabled(store.busy.contains("agent"))
            Spacer(minLength: 0)
          }
          Text("使用后可在草稿中继续编辑，发送前仍需确认。").font(UIType.small).foregroundStyle(Palette.muted)
        }.padding(.top, 16)
          .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
          .transition(UIMotion.reveal(reduceMotion))
      }
      if !relatedDrafts.isEmpty {
        Text("本封邮件的 AI 回复草稿").font(.system(size: 11, weight: .medium)).foregroundStyle(
          Palette.muted)
        ForEach(relatedDrafts) { draft in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(draft.subject).font(.system(size: 12, weight: .medium)).lineLimit(1)
              Text(draft.body).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            }
            Spacer()
            ActionButton(title: "审核草稿") { store.composer = draft }
          }.padding(10).background(.white, in: RoundedRectangle(cornerRadius: 6))
        }
      }
    }.animation(UIMotion.disclosure(reduceMotion), value: preview?.id)
      .onAppear {
      if store.summaryReplyRequest?.messageId != message.id, let latest = store.jobs.first(where: {
        $0.task == "reply" && $0.preview == true && $0.messageId == message.id
          && $0.status == "completed"
      }) {
        selectedPreset = latest.replyPreset.flatMap(ReplyPreset.init(rawValue:))
      }
    }.onChange(of: store.summaryReplyRequest?.id, initial: true) { _, _ in
      if let request = store.summaryReplyRequest, request.messageId == message.id {
        self.request = request.prompt
        selectedPreset = nil
      }
    }.onDisappear {
      if store.summaryReplyRequest?.messageId == message.id { store.summaryReplyRequest = nil }
    }
  }
  private func generate() {
    store.generate(
      task: "reply", message: message, prompt: request, replyPreset: selectedPreset, preview: true)
  }
}
