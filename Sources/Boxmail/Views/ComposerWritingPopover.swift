import BoxmailCore
import Observation
import SwiftUI

enum ComposerWritingScope: String {
  case selection, body, source, thread, new
  var action: String {
    switch self {
    case .selection: "替换选区"
    case .body: "替换正文"
    case .source, .thread: "填入正文"
    case .new: "填入草稿"
    }
  }
  var disclosure: String {
    switch self {
    case .selection: "提交选中的文字和本次写作要求。"
    case .body: "提交可编辑正文和本次写作要求。"
    case .source: "提交原邮件主题、正文和本次写作要求。"
    case .thread: "提交本机已缓存的同账户会话主题、正文和本次写作要求。"
    case .new: "提交本次写作要求、已有主题和写作偏好。"
    }
  }

  var automaticLanguage: String {
    switch self {
    case .selection: "跟随选区"
    case .body: "跟随正文"
    case .source, .thread: "跟随来信"
    case .new: "跟随要求"
    }
  }
}

@Observable @MainActor final class ComposerWritingSession {
  var prompt = ""
  var optionsExpanded = false
  var referenceThread = false
  var candidate: ComposerWritingCandidate?
  var error: String?
  var lastRequest: (text: String, language: MailTranslationLanguage?)?
  var adopting = false
}

struct ComposerWritingCandidate {
  let job: AgentJob
  let scope: ComposerWritingScope
  let draftId, accountId, body, signature: String
  let sourceMessageId: String?
  let document: RichTextDocument?
  let selection: RichTextController.RewriteSelection?
}

struct ComposerWritingPopover: View {
  let session: ComposerWritingSession
  let writing: WritingPreferencesStore
  let store: MailStore
  let scope: () -> ComposerWritingScope
  let allowsThreadReference: Bool
  let subject: String
  let matches: (ComposerWritingCandidate) -> Bool
  let generate: (String, MailTranslationLanguage?) -> Void
  let adopt: (ComposerWritingCandidate, String) -> Void
  let close: () -> Void
  @ViewState private var editingStyle = false

  var body: some View {
    let result = session.candidate?.job.result
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        if editingStyle {
          IconButton(icon: .chevronLeft, help: "返回写作") { finishEditingStyle() }
          Text(writing.selectedStyle == nil ? "自定义风格" : "编辑风格预设")
            .font(UIType.section).accessibilityAddTraits(.isHeader)
        } else {
          Text(result?.body == nil ? "帮我写" : "写作候选")
            .font(UIType.section).accessibilityAddTraits(.isHeader)
        }
        Spacer(minLength: 0)
        IconButton(icon: .x, help: "关闭帮我写", action: close)
      }
      if editingStyle {
        WritingStyleEditor(writing: writing, done: finishEditingStyle)
      } else if let candidate = session.candidate, let text = result?.body {
        ComposerWritingPreview(
          text: text,
          subject: candidate.scope == .new && subject.isEmpty ? result?.subject : nil,
          error: session.error, matches: matches(candidate), action: candidate.scope.action,
          adopting: session.adopting,
          edit: { session.candidate = nil; session.error = nil },
          adopt: { adopt(candidate, text) })
      } else {
        let generating = store.busy.contains("compose-ai")
        ComposerWritingForm(session: session, writing: writing, scope: scope(),
          allowsThreadReference: allowsThreadReference,
          unavailable: writing.isLoading || store.busy.contains("agent") || generating,
          generating: generating, generate: generate, customize: {
            writing.error = nil
            editingStyle = true
          })
      }
    }.padding(16).frame(width: 410)
  }

  private func finishEditingStyle() {
    writing.error = nil
    editingStyle = false
  }
}

private struct ComposerWritingForm: View {
  @Bindable var session: ComposerWritingSession
  let writing: WritingPreferencesStore
  let scope: ComposerWritingScope
  let allowsThreadReference: Bool
  let unavailable: Bool
  let generating: Bool
  let generate: (String, MailTranslationLanguage?) -> Void
  let customize: () -> Void

  private var retry: (text: String, language: MailTranslationLanguage?)? { session.error == nil ? nil : session.lastRequest }
  private var hasPrompt: Bool { !session.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var canSubmit: Bool { !unavailable && (hasPrompt || retry != nil) }
  private var isReply: Bool { allowsThreadReference && (scope == .source || scope == .thread) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      WorkflowField(title: "写作要求") {
        PlainTextEditor(text: $session.prompt, placeholder: "写作要求",
          fontSize: 13, lineSpacing: 3, inset: .init(width: 10, height: 8),
          accessibilityLabel: "写作要求", showsVerticalScroller: false,
          submitShortcut: .commandReturn, onSubmit: submit)
          .frame(height: 62).controlFieldSurface(focused: false)
      }
      if scope == .selection || isReply {
        HStack(spacing: 6) {
          if scope == .selection {
            ActionButton(title: "缩短", emphasis: .secondary, size: .compact, fillsWidth: true) {
              generate("缩短选区，保留原意。", nil)
            }
            ActionButton(title: "润色", emphasis: .secondary, size: .compact, fillsWidth: true) {
              generate("润色选区，保留原意。", nil)
            }
            CossMenu(title: "译为…", emphasis: .secondary) {
              for language in MailTranslationLanguage.allCases {
                CossMenuItem.command(language.title) { generate("翻译选区。", language) }
              }
            } trigger: { CossMenuLabel(title: "译为…", size: .compact, fillsWidth: true) }
          } else {
            ActionButton(title: "确认收到", emphasis: .secondary, size: .compact, fillsWidth: true) {
              generate("礼貌确认已收到。", nil)
            }
            ActionButton(title: "婉拒", emphasis: .secondary, size: .compact, fillsWidth: true) {
              generate("礼貌婉拒来信中的邀请或请求。", nil)
            }
          }
        }.disabled(unavailable)
      }
      DisclosureGroup(isExpanded: $session.optionsExpanded) {
        WritingPreferencesView(writing: writing, automaticLanguage: scope.automaticLanguage, customize: customize)
          .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
      } label: {
        HStack(spacing: 8) {
          Text("写作选项")
          if !session.optionsExpanded {
            Spacer(minLength: 0)
            Text("\(writing.styleName) · \(writing.language?.title ?? scope.automaticLanguage)")
              .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1)
          }
        }.padding(.leading, 4)
      }
      .disclosureGroupStyle(SettingsDisclosureStyle())
      .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.fieldRadius, style: .continuous))
      if isReply { Toggle("参考会话", isOn: $session.referenceThread).toggleStyle(CossToggleStyle()) }
      if let error = session.error { WorkflowNotice(text: error, color: Palette.amber) }
      CossSeparator()
      HStack(spacing: 12) {
        Text(scope.disclosure).font(UIType.small).foregroundStyle(Palette.muted)
          .frame(maxWidth: .infinity, alignment: .leading)
        if generating { CossSpinner().accessibilityLabel("正在生成候选") }
        ActionButton(title: retry == nil ? "生成候选" : "重新生成", emphasis: .primary, size: .compact,
          action: submit)
          .fixedSize().disabled(!canSubmit)
      }
    }
  }

  private func submit() {
    guard canSubmit else { return }
    if hasPrompt { generate(session.prompt, nil) }
    else if let retry { generate(retry.text, retry.language) }
  }
}

private struct ComposerWritingPreview: View {
  let text: String
  let subject: String?
  let error: String?
  let matches: Bool
  let action: String
  let adopting: Bool
  let edit: () -> Void
  let adopt: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let subject, !subject.isEmpty { Text(subject).font(UIType.body).bold() }
      ViewThatFits(in: .vertical) {
        preview.fixedSize(horizontal: false, vertical: true)
        ScrollView(showsIndicators: false) { preview }
      }.frame(maxHeight: 248, alignment: .topLeading)
      if !matches {
        WorkflowNotice(text: "正文、格式或发件账户已变化，请重新生成。")
      }
      if let error { WorkflowNotice(text: error, color: Palette.amber) }
      CossSeparator()
      HStack(spacing: 8) {
        ActionButton(title: "修改要求", size: .compact, action: edit)
        Spacer(minLength: 0)
        ActionButton(title: action, emphasis: .primary, size: .compact, action: adopt).disabled(adopting || !matches)
      }
    }
  }

  private var preview: some View {
    AnalysisDocumentView(text: text).frame(maxWidth: .infinity, alignment: .leading)
  }
}
