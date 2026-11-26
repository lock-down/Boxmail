import SwiftUI

/// Date selection stays consistent in the composer and drafts.
struct SendScheduleForm: View {
  @Binding var date: Date

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      DateTimeSelection(title: "发送时间", date: $date)
      WorkflowNotice(text: "请保持 Boxmail 运行。退出或睡眠期间的计划，会在恢复运行后处理。")
    }
  }
}
