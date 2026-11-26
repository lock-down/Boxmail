import BoxmailCore
import SwiftUI

struct SummaryTodoRow: View {
  let todo: MailTodo
  let compact: Bool
  let canToggle: Bool
  let toggle: () -> Void
  let collect: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Button(action: toggle) {
        HStack(alignment: .top, spacing: 8) {
          AppicaIcon(todo.done ? .circleCheckFilled : .circle)
            .foregroundStyle(todo.done ? Palette.success : Palette.muted)
            .frame(width: 16).padding(.top, 1).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(AITextStyle.inline(todo.title)).strikethrough(todo.done)
              .foregroundStyle(todo.done ? Palette.muted : Palette.ink).lineLimit(compact ? 2 : nil)
              .fixedSize(horizontal: false, vertical: true)
            if !todo.due.isEmpty {
              Label(todo.due, icon: .calendar, iconSize: UILayout.smallIconSize).font(UIType.small).foregroundStyle(Palette.amber)
                .lineLimit(compact ? 1 : nil).fixedSize(horizontal: false, vertical: true)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(UIType.body).lineSpacing(3).multilineTextAlignment(.leading)
          .controlLabel(size: .compact, verticalInset: 6, fillsWidth: true, alignment: .leading)
      }.buttonStyle(ControlFeedback()).controlFocus().disabled(!canToggle)
        .accessibilityLabel(todo.due.isEmpty ? todo.title : "\(todo.title)，\(todo.due)")
        .accessibilityValue(todo.done ? "已完成" : "待处理")
        .contextMenu { Button("收录为独立跟进", action: collect) }
      ActionButton(title: "收录跟进", icon: .plus, color: Palette.accent, emphasis: .tinted, size: .compact,
        help: "收录跟进：\(todo.title)", action: collect)
        .fixedSize().padding(.trailing, 4).padding(.top, 2)
    }.padding(.vertical, 2).background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius, style: .continuous))
  }
}
