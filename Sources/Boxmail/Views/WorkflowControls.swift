import SwiftUI

struct WorkflowPanelHeader: View {
  let title: String
  let subtitle: String
  let closeLabel: String
  let close: () -> Void
  var body: some View {
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(UIType.heading).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
        if !subtitle.isEmpty {
          Text(subtitle).font(UIType.caption).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
      IconButton(icon: .x, help: closeLabel, action: close)
        .keyboardShortcut(.cancelAction)
    }
  }
}

struct WorkflowField<Content: View>: View {
  let title: String
  var detail = ""
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
        Spacer(minLength: 4)
        if !detail.isEmpty { Text(detail).font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit() }
      }
      content()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WorkflowTextInput: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var lines = 1
  var font: Font = UIType.body
  var surface: Color = Palette.paper
  @FocusState private var focused: Bool
  var body: some View {
    TextField("", text: $text, axis: lines > 1 ? .vertical : .horizontal)
      .textFieldStyle(.plain).font(font).foregroundStyle(Palette.ink)
      .lineLimit(1...lines).lineSpacing(lines > 1 ? 4 : 0).focused($focused)
      .padding(.horizontal, 10).padding(.vertical, lines > 1 ? 10 : 0)
      .frame(minHeight: lines > 1 ? 108 : SettingsFormLayout.controlHeight,
        maxHeight: lines > 1 ? nil : SettingsFormLayout.controlHeight,
        alignment: lines > 1 ? .topLeading : .leading)
      .controlFieldSurface(focused: focused, fill: surface)
      .overlay(alignment: lines > 1 ? .topLeading : .leading) {
        if text.isEmpty {
          Text(placeholder).font(font).foregroundStyle(Palette.muted)
            .padding(.horizontal, 10).padding(.vertical, lines > 1 ? 10 : 0)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
      }
      .accessibilityLabel(label)
  }
}

struct WorkflowSelection<Value: Hashable>: View {
  let title: String
  @Binding var selection: Value
  let options: [(Value, String)]
  var style = WorkflowSelectionStyle.field
  var displayTitle: String? = nil

  private var currentTitle: String { options.first { $0.0 == selection }?.1 ?? "请选择" }

  var body: some View {
    CossMenu(title: title, value: currentTitle, width: 160,
      emphasis: style == .field ? .secondary : .plain, prefersSelection: true) {
      for (value, label) in options {
        CossMenuItem.command(label, mark: .choice(value == selection)) { selection = value }
      }
    } trigger: {
      CossMenuLabel(title: displayTitle ?? currentTitle, size: style == .toolbar ? .compact : .form,
        fillsWidth: style == .field, color: style == .toolbar ? Palette.muted : Palette.ink)
        .frame(maxWidth: .infinity).frame(height: style == .toolbar ? UILayout.iconControl : SettingsFormLayout.controlHeight)
    }
    .disabled(options.isEmpty).cossTooltip(currentTitle)
  }
}

enum WorkflowSelectionStyle { case field, inline, toolbar }

struct WorkflowStepper: View {
  let title: String
  @Binding var value: Int
  let range: ClosedRange<Int>
  let unit: String
  var body: some View {
    HStack(spacing: SettingsFormLayout.columnGap) {
      SettingsFormLabel(title: title)
      CossNumberField(title: title, value: $value, range: range).frame(width: 108)
      Text(unit).font(UIType.caption).foregroundStyle(Palette.muted)
      Spacer(minLength: 0)
    }
  }
}

struct WorkflowNotice: View {
  let text: String
  var icon: AppicaGlyph = .infoCircle
  var color: Color = Palette.muted
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      AppicaIcon(icon).frame(width: 14).padding(.top, 1).accessibilityHidden(true)
      Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }.font(UIType.small).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
  }
}
