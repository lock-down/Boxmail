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
  var body: some View {
    VStack(spacing: 0) {
      if document?.summary != nil || attachment?.analysis?.isEmpty == false {
        HStack {
          FilterBar(values: ["文件目录", "历史分析"], selection: $tab)
          Spacer()
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Palette.chrome)
        CossSeparator()
      }
      if let error {
        HStack {
          Text(error).font(UIType.caption).foregroundStyle(Palette.amber)
          ActionButton(title: "重试", icon: .refresh) { Task { await reload() } }
        }.padding(16)
      }
      if let document {
        if document.omitted > 0 {
          Text("已列出 \(document.entries.count)/\(document.totalFiles) 个文件。可下载压缩包查看完整目录。")
            .font(UIType.small).foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(
              .vertical, 8)
        }
        if tab == "历史分析" {
          OverlayScrollView {
            if let summary = document.summary {
              ArchiveSummaryView(summary: summary, entries: document.entries) { id in
                selection = id
                tab = "文件目录"
              }
              .padding(24).frame(maxWidth: UILayout.document, alignment: .leading)
            } else if let text = attachment?.analysis {
              AnalysisDocumentView(text: text).padding(24)
                .frame(maxWidth: UILayout.document, alignment: .leading)
            }
          }
        } else {
          HSplitView {
            List(selection: $selection) {
              ForEach(document.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                  HStack(spacing: 6) {
                    AppicaIcon(.fileText).foregroundStyle(Palette.muted)
                    Text(entry.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                      .truncationMode(.middle)
                  }
                  Text(entry.path).font(UIType.small).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle)
                  HStack {
                    Text(fileSize(entry.size)).foregroundStyle(Palette.muted).monospacedDigit()
                  }.font(UIType.small)
                }.padding(.horizontal, 12).padding(.vertical, 8)
                  .cossListRow(selected: selection == entry.id).tag(entry.id).cossTooltip(entry.path)
              }
            }.cossListStyle()
              .frame(minWidth: 260, idealWidth: 320, maxWidth: 420).accessibilityLabel("压缩包文件目录")
            if let entry = document.entries.first(where: { $0.id == selection }) {
              ArchiveEntryView(attachmentId: attachmentId, entry: entry)
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity).id(entry.id)
            } else {
              EmptyState(title: "选择包内文件", subtitle: "选择目录项可查看原文件。", icon: .fileZip)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
      } else if loading {
        CossSpinner(label: "正在读取压缩包目录…").frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Spacer()
      }
    }.onChange(of: attachment?.archive) { _, value in if let value { document = value } }
      .task(id: attachmentId) { await reload() }
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
      AnalysisDocumentView(text: summary.overview)
      if !summary.groups.isEmpty {
        Text("文件归类").font(UIType.section)
        ForEach(Array(summary.groups.enumerated()), id: \.offset) { _, group in
          VStack(alignment: .leading, spacing: 8) {
            Text(AITextStyle.inline(group.title)).font(UIType.body)
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
          AnalysisDocumentView(text: row.text)
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
              AppicaIcon(.fileText).frame(width: 14)
              Text(entry.path).lineLimit(1).truncationMode(.middle)
            }.font(UIType.caption).foregroundStyle(Palette.accent)
              .frame(maxWidth: .infinity, alignment: .leading).frame(height: 32)
              .padding(.horizontal, 8).contentShape(Rectangle())
          }.buttonStyle(ControlFeedback()).controlFocus()
            .cossTooltip("查看来源：\(entry.path)").accessibilityLabel("查看来源：\(entry.path)")
        }
      }
    }
  }
}
