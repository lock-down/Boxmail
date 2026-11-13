import AppKit
import BoxmailCore
import SwiftUI

struct ArchiveAttachmentView: View {
  @Bindable var store: MailStore
  let attachmentId: String
  @ViewState<ArchiveDocument?> private var document: ArchiveDocument?
  @ViewState<String?> private var selection: String?
  @ViewState<String> private var tab = "文件目录"
  @ViewState<String?> private var error: String?
  @ViewState<Bool> private var loading = false
  private var attachment: MailAttachment? { store.attachments.first { $0.id == attachmentId } }
  private var mail: MailMessage? { store.messages.first { $0.id == attachment?.messageId } }
  private var job: AgentJob? { mail.flatMap { store.attachmentBatch(for: $0) } }
  private var running: Bool { job?.status == "running" }
  private var retryable: Bool {
    job.map {
      ["partial", "failed", "paused"].contains($0.status)
        && ($0.attachmentItems ?? []).contains { $0.id == attachmentId }
    } == true
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        FilterBar(values: ["文件目录", "整体整理"], selection: $tab)
        if let document {
          Text("已理解 \(document.understoodCount)/\(document.totalFiles) 个文件")
            .font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
        }
        Spacer(minLength: 0)
        if running {
          ProgressView().controlSize(.mini)
          ActionButton(title: "暂停", icon: "pause") {
            if let job { store.pauseAttachmentBatch(job) }
          }
        } else {
          ActionButton(
            title: retryable ? "继续未完成文件" : document?.summary == nil ? "理解压缩包" : "重新理解压缩包",
            icon: "sparkles", color: Palette.accent
          ) {
            guard let mail else { return }
            store.analyzeAttachments(
              in: mail, force: !retryable && document?.summary != nil,
              retry: retryable ? job : nil, attachmentIds: [attachmentId])
          }.disabled(
            loading || document == nil || mail == nil || store.busy.contains("agent")
              || mail.map { store.busy.contains("attachment-batch-\($0.id)") } == true)
        }
      }.padding(.horizontal, 20).padding(.vertical, 10).background(Palette.chrome)
      Divider()
      if let error {
        HStack {
          Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
          ActionButton(title: "重试", icon: "arrow.clockwise") { Task { await reload() } }
        }.padding(16)
      }
      if let jobError = job?.error, retryable {
        Text(jobError).font(UIType.caption).foregroundStyle(Palette.amber)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(
            .vertical, 8)
      }
      if let document {
        if document.omitted > 0 || document.entries.contains(where: { $0.status == "unsupported" })
        {
          Text("本次列出 \(document.entries.count)/\(document.totalFiles) 个文件；未处理项会显示原因，整体整理仅依据已理解文件。")
            .font(UIType.small).foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(
              .vertical, 8)
        }
        if tab == "整体整理" {
          OverlayScrollView {
            if let summary = document.summary {
              ArchiveSummaryView(summary: summary, entries: document.entries) { id in
                selection = id
                tab = "文件目录"
              }
              .padding(24).frame(maxWidth: UILayout.document, alignment: .leading)
            } else {
              EmptyState(
                title: running ? "正在理解包内文件" : "还没有整体整理",
                subtitle: "逐文件理解完成后，会整理资料用途、文件分类、关联差异和下一步行动，并附上来源。",
                icon: "doc.text.magnifyingglass"
              ).frame(maxWidth: .infinity).padding(.top, 60)
            }
          }
        } else {
          HSplitView {
            List(selection: $selection) {
              ForEach(document.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 6) {
                    Image(systemName: "doc.text").foregroundStyle(Palette.muted)
                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                      .truncationMode(.middle)
                  }
                  Text(entry.path).font(UIType.small).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
                  HStack {
                    Text(entry.statusTitle).foregroundStyle(
                      entry.status == "completed" ? Palette.blue : Palette.muted)
                    Spacer()
                    Text(fileSize(entry.size)).foregroundStyle(Palette.muted).monospacedDigit()
                  }.font(UIType.small)
                }.padding(.vertical, 6).tag(entry.id).help(entry.path)
              }
            }.listStyle(.plain).scrollContentBackground(.hidden)
              .frame(minWidth: 260, idealWidth: 320, maxWidth: 420).accessibilityLabel("压缩包文件目录")
            if let entry = document.entries.first(where: { $0.id == selection }) {
              ArchiveEntryView(attachmentId: attachmentId, entry: entry)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity).id(entry.id)
            } else {
              EmptyState(title: "选择包内文件", subtitle: "查看原文件、理解状态和单文件结果。", icon: "doc.zipper")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
      } else if loading {
        ProgressView("正在读取压缩包目录…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer()
      }
    }.onChange(of: attachment?.archive) { _, value in if let value { document = value } }
      .task(id: attachmentId) { await reload() }
      .onChange(of: running) { _, active in
        if !active { Task { await reload() } }
      }
  }

  private func reload() async {
    guard !loading else { return }
    loading = true
    defer { loading = false }
    do {
      let value: ArchiveDocument = try await BackendService.shared.request(
        "/attachments/\(attachmentId)/archive")
      try Task.checkCancellation()
      document = value
      error = nil
      if selection == nil { selection = value.entries.first?.id }

    } catch is CancellationError {
    } catch { self.error = error.localizedDescription }
  }
}

private struct ArchiveSummaryView: View {
  let summary: ArchiveSummary
  let entries: [ArchiveEntry]
  let select: (String) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("资料包总览").font(UIType.heading)
      Text(summary.overview).font(UIType.body).lineSpacing(5).textSelection(.enabled)
      if !summary.groups.isEmpty {
        Text("文件归类").font(UIType.section)
        ForEach(Array(summary.groups.enumerated()), id: \.offset) { _, group in
          VStack(alignment: .leading, spacing: 8) {
            Text(group.title).font(UIType.body)
            sources(group.entryIds)
          }
        }
      }
      findings("关联、差异与待确认事项", rows: summary.findings)
      findings("下一步行动", rows: summary.actions)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  @ViewBuilder private func findings(_ title: String, rows: [ArchiveFinding]) -> some View {
    if !rows.isEmpty {
      Text(title).font(UIType.section)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        VStack(alignment: .leading, spacing: 8) {
          Text(row.text).font(UIType.body).lineSpacing(5).textSelection(.enabled)
          sources(row.entryIds)
        }
      }
    }
  }
  private func sources(_ ids: [String]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(ids, id: \.self) { id in
        if let entry = entries.first(where: { $0.id == id }) {
          Button {
            select(id)
          } label: {
            HStack(spacing: 7) {
              Image(systemName: "doc.text").frame(width: 14)
              Text(entry.path).lineLimit(1).truncationMode(.middle)
            }.font(UIType.caption).foregroundStyle(Palette.blue)
              .frame(maxWidth: .infinity, alignment: .leading).frame(height: 32)
              .padding(.horizontal, 8).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback()).controlFocus()
            .help("查看来源：\(entry.path)").accessibilityLabel("查看来源：\(entry.path)")
        }
      }
    }
  }
}
