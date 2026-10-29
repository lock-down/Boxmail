import AppKit
import BoxmailCore
import SwiftUI

struct MailAttachmentSection: View {
  @Bindable var store: MailStore
  let message: MailMessage
  @ViewState<Bool> private var showResults = false
  @ViewState<Bool> private var confirmBatch = false
  @ViewState<Bool> private var forceBatch = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var files: [MailAttachment] {
    message.attachmentIds.compactMap { id in
      store.attachments.first { $0.id == id && $0.messageId == message.id }
    }
  }
  private var job: AgentJob? { store.attachmentBatch(for: message) }
  private var items: [AttachmentBatchItem] { job?.attachmentItems ?? [] }
  private var running: Bool { job?.status == "running" }
  private var controlling: Bool { store.busy.contains("attachment-batch-\(message.id)") }
  private var analyzed: [MailAttachment] { files.filter { $0.analysis?.isEmpty == false } }
  private var unfinished: Int { files.filter { !$0.isAnalyzed && $0.canAnalyze }.count }
  private var retryable: Bool { job.map { ["failed", "partial", "paused"].contains($0.status) } == true }
  private var batchSelection: [String] {
    Array(files.filter { $0.canAnalyze && (forceBatch || !$0.isAnalyzed) }.prefix(100).map(\.id))
  }
  private var buttonTitle: String {
    if running { return "正在批量理解…" }
    if job?.status == "paused" { return "继续未完成的附件" }
    if retryable { return "重试失败附件" }
    if message.attachmentIds.count > 100 {
      return unfinished > 0 ? "理解下一批附件（最多 100 个）" : "重新理解一批附件（最多 100 个）"
    }
    if !files.isEmpty && unfinished == 0 && files.contains(where: \.isAnalyzed) { return "重新理解全部附件" }
    return "理解本封邮件附件"
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("\(message.attachmentIds.count) 个附件", systemImage: "paperclip")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        ActionButton(title: buttonTitle, icon: "sparkles", kind: .ai) {
          startAnalysis(force: unfinished == 0, retry: retryable ? job : nil)
        }.disabled(running || controlling || store.busy.contains("agent"))
      }
      if let job {
        progress(job)
      } else {
        Text(message.attachmentIds.count > 100 ? "每批最多 100 个附件，确认后开始；已有结果会保留。" : "一键理解本封邮件全部附件，已有结果会保留。")
          .font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let error = store.attachmentBatchErrors[message.id] {
        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
          .foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 9)], spacing: 9) {
        ForEach(files) { file in
          AttachmentCard(attachment: file, batchItem: items.first { $0.id == file.id }) {
            store.previewAttachment = file
          }
        }
      }
      ForEach(Array(store.aiOutputs.values.filter { $0.task == "attachment" && $0.messageId == message.id })) { output in
        VStack(alignment: .leading, spacing: 10) {
          if let file = files.first(where: { $0.id == output.attachmentId }) {
            Text(file.name).font(UIType.section)
          }
          AIStreamingView(output: output)
        }
      }
      if !analyzed.isEmpty {
        AIResultDisclosure(title: "查看附件理解结果（\(analyzed.count)）", isExpanded: $showResults,
          copyHelp: "复制全部附件理解结果", copy: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(analyzed.map { "\($0.name)\n\($0.analysis ?? "")" }.joined(separator: "\n\n"), forType: .string)
          }
        ) {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(analyzed) { file in AttachmentAnalysisRow(file: file) }
          }
        }
      }
    }.padding(.top, 8)
      .confirmationDialog("分批理解附件", isPresented: $confirmBatch, titleVisibility: .visible) {
        Button("理解本批 \(batchSelection.count) 个附件") {
          store.analyzeAttachments(in: message, force: forceBatch, attachmentIds: batchSelection)
        }.disabled(batchSelection.isEmpty)
        Button("取消", role: .cancel) {}
      } message: {
        Text("本次最多发起 \(batchSelection.count) 次模型请求，费用由当前 AI 服务商计收。其余附件可在本批结束后继续。")
      }
      .animation(UIMotion.disclosure(reduceMotion), value: showResults)
      .onChange(of: store.attachmentResultsMessageId, initial: true) { _, id in
        if id == message.id { showResults = true }
      }
  }
  private func startAnalysis(force: Bool, retry: AgentJob? = nil) {
    if message.attachmentIds.count > 100 && (retry?.attachmentItems?.count ?? 101) > 100 {
      forceBatch = force
      confirmBatch = true
    } else {
      store.analyzeAttachments(in: message, force: force, retry: retry)
    }
  }
  private func progress(_ job: AgentJob) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        if running { ProgressView().controlSize(.mini) }
        Text(statusTitle(job)).font(.system(size: 11, weight: .medium))
          .contentTransition(reduceMotion ? .identity : .numericText())
        Spacer()
        if running {
          Button("暂停") { store.pauseAttachmentBatch(job) }.disabled(controlling)
        } else if retryable || unfinished > 0 {
          Button(message.attachmentIds.count > 100 ? "重新理解一批附件" : "重新理解全部") { startAnalysis(force: true) }
            .disabled(controlling || store.busy.contains("agent"))
        }
      }.buttonStyle(.plain).foregroundStyle(Palette.accent)
      if running {
        ProgressView(value: Double(items.filter(\.isFinished).count), total: Double(max(1, items.count)))
        if let item = items.first(where: { $0.status == "running" }) {
          Text("正在理解：\(item.name)").lineLimit(1).truncationMode(.middle)
        }
        Text("逐个保存结果，可继续阅读其他邮件。")
      }
      if let error = job.error {
        Text(error).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
      }
      let unsupported = items.filter { $0.status == "unsupported" }.count
      if unsupported > 0 { Text("\(unsupported) 个附件暂不支持 AI 理解，可预览或下载原文件。") }
    }.font(UIType.small).foregroundStyle(Palette.muted)
      .padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
      .animation(UIMotion.selection(reduceMotion), value: items.filter(\.isFinished).count)
  }
  private func statusTitle(_ job: AgentJob) -> String {
    let completed = items.filter(\.isAnalyzed).count
    let failed = items.filter { $0.status == "failed" }.count
    let prefix = running ? "批量理解中" : job.status == "paused" ? "批量理解已暂停"
      : failed > 0 ? "批量理解部分未完成" : "批量理解完成"
    return "\(prefix) · 已理解 \(completed)/\(items.count)" + (failed > 0 ? " · 失败 \(failed)" : "")
  }
}

private struct AttachmentAnalysisRow: View {
  let file: MailAttachment
  @ViewState<Bool> private var isExpanded = false
  var body: some View {
    AIResultDisclosure(title: file.name, isExpanded: $isExpanded, copy: {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(file.analysis ?? "", forType: .string)
    }) {
      if let text = file.analysis { AnalysisDocumentView(text: text) }
    }
  }
}
