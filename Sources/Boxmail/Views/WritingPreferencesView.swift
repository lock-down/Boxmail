import BoxmailCore
import SwiftUI

struct WritingPreferencesView: View {
  let writing: WritingPreferencesStore
  let automaticLanguage: String
  let customize: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        label("风格")
        CossMenu(title: "写作风格", value: "\(writing.styleName)，\(writing.style.summary)", width: 232,
          emphasis: .secondary, prefersSelection: true) {
          CossMenuItem.heading("内置风格")
          for preset in WritingPreferencesStore.builtInPresets {
            CossMenuItem.command(preset.name, subtitle: preset.style.summary, mark: selected(preset.id)) {
              writing.select(preset.id)
            }
          }
          if !writing.styles.isEmpty {
            CossMenuItem.divider
            CossMenuItem.heading("我的风格")
            for preset in writing.styles {
              CossMenuItem.command(preset.name, mark: selected(preset.id)) { writing.select(preset.id) }
            }
          }
        } trigger: {
          CossMenuLabel(title: writing.styleName, detail: writing.style.summary, fillsWidth: true)
        }
        ActionButton(title: writing.selectedStyle == nil ? "自定义…" : "编辑…", emphasis: .secondary,
          action: customize)
      }.disabled(writing.isLoading)
      HStack(spacing: 8) {
        label("输出语言")
        CossMenu(title: "输出语言", value: writing.language?.title ?? automaticLanguage,
          emphasis: .secondary, prefersSelection: true) {
          CossMenuItem.command(automaticLanguage, mark: .choice(writing.language == nil)) {
            writing.language = nil
          }
          CossMenuItem.divider
          for language in MailTranslationLanguage.allCases {
            CossMenuItem.command(language.title, mark: .choice(writing.language == language)) {
              writing.language = language
            }
          }
        } trigger: {
          CossMenuLabel(title: writing.language?.title ?? automaticLanguage, fillsWidth: true)
        }
      }
      if let error = writing.error { WorkflowNotice(text: error, color: Palette.amber) }
    }
  }

  private func label(_ title: String) -> some View {
    Text(title).font(UIType.caption).foregroundStyle(Palette.muted)
      .frame(width: 52, alignment: .leading).accessibilityHidden(true)
  }

  private func selected(_ id: String) -> CossMenuItem.Mark {
    .choice(!writing.isAdjusted && writing.selectedId == id)
  }
}

struct WritingStyleEditor: View {
  let writing: WritingPreferencesStore
  let done: () -> Void
  @ViewState private var style: WritingPreferencesStore.Style
  @ViewState private var name: String
  @ViewState private var saving = false

  init(writing: WritingPreferencesStore, done: @escaping () -> Void) {
    self.writing = writing
    self.done = done
    _style = ViewState(initialValue: writing.style)
    _name = ViewState(initialValue: writing.selectedStyle?.name ?? "")
  }

  private var editingSavedStyle: Bool { writing.selectedStyle != nil }
  private var validName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 8) {
        WorkflowField(title: "语气") {
          WorkflowSelection(title: "语气", selection: $style.tone,
            options: values(["正式", "亲切", "简洁", "专业"], keeping: style.tone))
        }
        WorkflowField(title: "篇幅") {
          WorkflowSelection(title: "篇幅", selection: $style.length,
            options: values(["简短", "适中", "详细"], keeping: style.length))
        }
      }
      WorkflowField(title: "行文要求") {
        PlainTextEditor(text: $style.instruction,
          placeholder: "行文要求",
          inset: .init(width: 10, height: 8), accessibilityLabel: "行文要求", showsVerticalScroller: false)
          .frame(height: 60).controlFieldSurface(focused: false)
      }
      WorkflowField(title: "预设名称", detail: "保存必填") {
        WorkflowTextInput(label: "预设名称", placeholder: "项目进展", text: $name)
      }
      if let error = writing.error { WorkflowNotice(text: error, color: Palette.amber) }
      CossSeparator()
      HStack(spacing: 6) {
        if editingSavedStyle {
          CossMenu(title: "风格预设操作") {
            CossMenuItem.command("另存预设", enabled: validName) { save(asNew: true) }
            CossMenuItem.divider
            CossMenuItem.command("删除预设", destructive: true) { remove() }
          } trigger: {
            CossMenuLabel(title: "更多", size: .compact)
          }
        }
        Spacer(minLength: 0)
        ActionButton(title: "仅本次", size: .compact) {
          writing.useOnce(style)
          done()
        }
        ActionButton(title: editingSavedStyle ? "更新预设" : "保存预设", emphasis: .primary, size: .compact) {
          save(asNew: !editingSavedStyle)
        }.disabled(!validName)
      }
    }.disabled(saving)
  }

  private func values(_ list: [String], keeping current: String) -> [(String, String)] {
    (list.contains(current) ? list : list + [current]).map { ($0, $0) }
  }

  private func save(asNew: Bool) {
    Task {
      saving = true
      defer { saving = false }
      if await writing.save(name: name, style: style, asNew: asNew) { done() }
    }
  }

  private func remove() {
    Task {
      saving = true
      defer { saving = false }
      if await writing.remove() { done() }
    }
  }
}
