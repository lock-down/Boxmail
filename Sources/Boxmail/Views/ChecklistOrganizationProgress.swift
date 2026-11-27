import SwiftUI

struct ChecklistOrganizationProgress: View {
  @Bindable var store: MailStore
  @ViewState private var selectedBatch: OrganizationBatch?
  @ViewState private var stopping: Set<String> = []
  @ViewState private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(store.visibleOrganizationBatches) { batch in
        let account = store.accounts.first { $0.id == batch.accountId }?.email
        HStack(alignment: .center, spacing: 10) {
          if batch.active {
            CossSpinner(size: 16).accessibilityHidden(true)
          } else {
            AppicaIcon(.listCheck, size: 16).foregroundStyle(Palette.muted).accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(batch.title + (batch.active ? "进行中" : batch.counts["cancelled", default: 0] > 0 ? "已停止" : "已结束"))
              .font(UIType.section)
            if let account { Text(account).font(UIType.small).foregroundStyle(Palette.muted) }
          }
          Spacer(minLength: 4)
          ActionButton(title: batch.active ? "查看进度" : "查看结果", size: .compact) { selectedBatch = batch }
          if batch.active {
            ActionButton(title: batch.stopTitle, icon: .square, emphasis: .secondary, size: .compact) {
              stop(batch)
            }.disabled(stopping.contains(batch.id))
          } else {
            IconButton(icon: .x, help: "隐藏整理进度") { store.hiddenOrganizationBatchID = batch.id }
          }
        }
        if batch.active && batch.total > 0 {
          ProgressView(value: Double(batch.total - batch.remaining), total: Double(batch.total))
            .progressViewStyle(CossProgressStyle())
        }
        Text(batch.progress).font(UIType.caption).monospacedDigit().foregroundStyle(Palette.muted)
      }
      if let error { WorkflowNotice(text: error, color: Palette.destructive) }
    }.padding(12).framedSurface()
      .sheet(item: $selectedBatch) { batch in
        VStack(spacing: 0) {
          WorkflowPanelHeader(title: batch.title, subtitle: displayTime(batch.createdAt), closeLabel: "关闭进度") {
            selectedBatch = nil
          }.padding(20)
          CossSeparator()
          OrganizationBatchView(store: store, initial: batch)
        }.background(Palette.paper).workspaceWindowSize(.categories)
      }
  }

  private func stop(_ batch: OrganizationBatch) {
    stopping.insert(batch.id)
    error = nil
    Task {
      defer { stopping.remove(batch.id) }
      do { _ = try await store.stopOrganizationBatch(batch.id) }
      catch { self.error = error.localizedDescription }
    }
  }
}
