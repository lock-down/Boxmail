import BoxmailCore
import SwiftUI

struct AgentActivityCard: View {
  let output: AIStreamOutput?
  let started: Date?
  @Binding var showsThinking: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var stageTitle: String {
    switch output?.stage {
    case "thinking": "正在思考"
    case "checking": "正在核对条件"
    case "writing": "正在回复"
    default: "正在等待模型"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let started {
        HStack(spacing: 8) {
          AgentPixelLoader()
          Text(stageTitle).font(UIType.caption.weight(.medium)).foregroundStyle(Palette.ink)
          Text(started, style: .timer).font(UIType.small).monospacedDigit().foregroundStyle(Palette.muted)
            .accessibilityLabel("等待时间")
        }
      }
      if output?.thought == true {
        Button {
          withAnimation(UIMotion.disclosure(reduceMotion)) { showsThinking.toggle() }
        } label: {
          HStack(spacing: 6) {
            AppicaIcon(.chevronRight, size: 12)
              .rotationEffect(.degrees(showsThinking ? 90 : 0))
              .accessibilityHidden(true)
            Text("思考过程").font(UIType.caption)
          }.foregroundStyle(Palette.muted).padding(.horizontal, 4).frame(minHeight: 25)
        }.buttonStyle(ControlFeedback(corner: UILayout.minimumRadius)).controlFocus(corner: UILayout.minimumRadius)
          .accessibilityValue(showsThinking ? "已展开" : "已收起")
        if showsThinking {
          Text(output?.thinkingSummary ?? "模型未提供可显示的思考摘要。")
            .font(UIType.caption).foregroundStyle(Palette.muted).lineSpacing(3).textSelection(.enabled)
            .padding(.leading, 12).padding(.vertical, 4)
            .overlay(alignment: .leading) { Rectangle().fill(Palette.border).frame(width: 1) }
        }
      }
      if let tools = output?.tools, !tools.isEmpty {
        WrappingFlowLayout(spacing: 6) {
          ForEach(tools) { tool in toolChip(tool) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("工具调用")
      }
    }
  }

  private func toolChip(_ tool: AIToolActivity) -> some View {
    let label = toolTitle(tool.name)
    let status = tool.status == "completed" ? "完成" : tool.status == "failed" ? "失败" : "运行中"
    return HStack(spacing: 5) {
      switch tool.status {
      case "completed":
        AppicaIcon(.check, size: 12).foregroundStyle(Palette.success)
      case "failed":
        AppicaIcon(.infoCircle, size: 12).foregroundStyle(Palette.destructive)
      default:
        CossSpinner(size: 12)
      }
      Text(label).font(UIType.small.weight(.medium))
      if let detail = tool.detail {
        Text(detail).font(UIType.small).foregroundStyle(Palette.muted)
      } else if tool.status == "failed" {
        Text(status).font(UIType.small).foregroundStyle(Palette.destructive)
      }
    }.padding(.horizontal, 8).padding(.vertical, 4)
      .background(Palette.chrome, in: RoundedRectangle(cornerRadius: UILayout.minimumRadius, style: .continuous))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel([label, status, tool.detail].compactMap { $0 }.joined(separator: "，"))
  }

  private func toolTitle(_ name: String) -> String {
    switch name {
    case "list_labels": "读取标签"
    case "preview_rule": "预查匹配"
    case "local_samples": "查找本机样例"
    default: "只读工具"
    }
  }
}

/// Chevron-wave timing adapted from Beautiful UI's Loading State by Shane Levine (MIT).
/// https://www.beautifului.dev/r/loading-state.json
private struct AgentPixelLoader: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState private var start = Date()

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
      let elapsed = context.date.timeIntervalSince(start)
      VStack(spacing: 1) {
        ForEach(0..<3, id: \.self) { row in
          HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { column in
              Rectangle().fill(Palette.accent.opacity(opacity(row: row, column: column, elapsed: elapsed)))
                .frame(width: 3, height: 3)
            }
          }
        }
      }
    }.accessibilityHidden(true)
  }

  private func opacity(row: Int, column: Int, elapsed: TimeInterval) -> Double {
    let delay = Double(column + abs(row - 1)) * 0.09
    guard !reduceMotion, elapsed >= delay else { return 0.24 }
    let phase = (elapsed - delay).truncatingRemainder(dividingBy: 0.65) / 0.65
    let pulse = max(0, min(1, phase / 0.18, (0.62 - phase) / 0.20))
    return 0.24 + 0.76 * (pulse * pulse * (3 - 2 * pulse))
  }
}
