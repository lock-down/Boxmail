import BoxmailCore
import SwiftUI

struct AssistantSourcesView: View {
  let store: MailStore
  let turn: AssistantTurn
  let openMailSource: (String) -> Void
  @ViewState<Bool> private var showingSources = false

  private var drafts: Bool { turn.scope.query?.folder == "drafts" }
  private var countLabel: String { "\(turn.sources.count) \(drafts ? "份草稿" : "封邮件")" }

  var body: some View {
    Button { showingSources.toggle() } label: {
      HStack(spacing: 8) {
        Label("来源", systemImage: "link").foregroundStyle(Palette.ink)
        Text(countLabel).foregroundStyle(Palette.muted).monospacedDigit()
        Spacer(minLength: 0)
        Image(systemName: "chevron.up.chevron.down").font(UIType.small).foregroundStyle(Palette.muted)
          .accessibilityHidden(true)
      }.font(UIType.caption).padding(.horizontal, 8).frame(height: 32)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius))
        .contentShape(Rectangle())
    }.buttonStyle(ControlFeedback()).controlFocus()
      .accessibilityLabel("查看来源，\(countLabel)")
      .popover(isPresented: $showingSources, arrowEdge: .leading) { sourceList }
  }

  private var sourceList: some View {
    let citations = Dictionary(grouping: turn.citations, by: \.messageId)
    let sources = turn.sources.filter { citations[$0.id] != nil } + turn.sources.filter { citations[$0.id] == nil }
    let multipleAccounts = Set(sources.map(\.accountId)).count > 1
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text("回答来源").font(UIType.section).accessibilityAddTraits(.isHeader)
        Spacer()
        Text(countLabel).font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit()
        IconButton(icon: "xmark", help: "关闭来源", size: 24) { showingSources = false }
      }.padding(.horizontal, 12).frame(height: 40)
      Divider().overlay(Palette.softBorder)
      ViewThatFits(in: .vertical) {
        sourceRows(sources, citations: citations, multipleAccounts: multipleAccounts).fixedSize(horizontal: false, vertical: true)
        OverlayScrollView { sourceRows(sources, citations: citations, multipleAccounts: multipleAccounts) }
      }.frame(maxHeight: 320, alignment: .top)
    }.frame(width: 352).background(Palette.paper)
  }

  private func sourceRows(_ sources: [AssistantSource], citations: [String: [AssistantCitation]], multipleAccounts: Bool) -> some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      ForEach(sources) { source in
        sourceRow(source, citedAttachments: Set(citations[source.id, default: []].compactMap(\.attachmentId)),
          showAccount: multipleAccounts)
        if source.id != sources.last?.id { Divider().overlay(Palette.softBorder) }
      }
    }.padding(.horizontal, 8).padding(.vertical, 4)
  }

  private func sourceRow(_ source: AssistantSource, citedAttachments: Set<String>, showAccount: Bool) -> some View {
    let account = showAccount ? store.accounts.first { $0.id == source.accountId }?.email : nil
    let subject = source.subject.isEmpty ? "无主题" : source.subject
    return VStack(alignment: .leading, spacing: 4) {
      Button {
        showingSources = false
        openMailSource(source.id)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: drafts ? "square.and.pencil" : "envelope")
            .frame(width: 16).foregroundStyle(Palette.muted).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
              Text(subject).font(UIType.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
              Text(displayTime(source.date)).font(UIType.small).foregroundStyle(Palette.muted).monospacedDigit().fixedSize()
            }
            if !source.sender.isEmpty || account != nil {
              Text([source.sender, account ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(UIType.small).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
            }
          }
        }.padding(8).contentShape(Rectangle())
      }.buttonStyle(ControlFeedback()).controlFocus().help(subject)

      if !source.coverage.attachments.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(source.coverage.attachments.filter { citedAttachments.contains($0.id) && !drafts }) { file in
            MailSourceButton(sender: file.name, date: "", subject: file.name, icon: "paperclip") {
              showingSources = false
              store.previewSourceAttachment(file.id)
            }
          }
          MailAIContextNotice(context: source.coverage, attachmentCount: source.coverage.attachments.count)
        }.padding(.leading, 32).padding(.bottom, 8)
      }
    }
  }
}
