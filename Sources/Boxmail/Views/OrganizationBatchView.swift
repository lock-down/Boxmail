import BoxmailCore
import SwiftUI

struct OrganizationBatch: Decodable, Identifiable, Equatable {
  let id, accountId, createdAt: String
  let labelName: String?
  let applied: Bool?
  let counts: [String: Int]
  let items: [Item]?

  var trial: Bool { labelName != nil }
  var title: String { labelName.map { "试用标签 · \($0)" } ?? "邮件整理" }
  var remaining: Int { counts["pending", default: 0] + counts["running", default: 0] }
  var active: Bool { remaining > 0 }
  var total: Int { counts.values.reduce(0, +) }
  var summary: Self { .init(id: id, accountId: accountId, createdAt: createdAt, labelName: labelName, applied: applied, counts: counts, items: nil) }
  var stopTitle: String { trial ? "停止试用" : "停止整理" }
  var progress: String {
    let stages = [("pending", "等待"), ("running", "处理"), ("completed", "完成"), ("failed", "失败"), ("skipped", "跳过")]
    let main = stages.map { "\($0.1) \(counts[$0.0, default: 0])" }
    let other = [("cancelled", "取消"), ("paused", "暂停")].compactMap { key, title in
      counts[key].map { "\(title) \($0)" }
    }
    return (main + other).joined(separator: " · ")
  }

  struct Item: Decodable, Identifiable, Equatable {
    let id, messageId, status: String
    let subject, error, overview: String?
    let matched: Bool?
    let todos: [MailTodo]?
    let labelNames: [String]?
  }
}

struct OrganizationBatchView: View {
  @Bindable var store: MailStore
  let initial: OrganizationBatch
  var openSource: ((String) -> Void)? = nil
  @ViewState private var current: OrganizationBatch?
  @ViewState private var error: String?
  @ViewState private var working = false
  @ViewState private var operationRevision = 0
  @ViewState private var matchesOnly = false

  private var batch: OrganizationBatch { current ?? initial }
  private var matches: Int { batch.items?.count(where: { $0.matched == true }) ?? 0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label("Boxmail Agent", icon: .sparkles).font(UIType.section)
          Spacer()
          if batch.active { CossSpinner().accessibilityLabel("处理中") }
        }
        Text(batch.progress).font(UIType.caption).monospacedDigit().foregroundStyle(Palette.muted)
        if batch.trial {
          Text(batch.applied == true ? "已应用标签" : "命中 \(matches) 封 · 确认后应用标签")
            .font(UIType.small).foregroundStyle(Palette.muted)
        }
        HStack(spacing: 8) {
          if batch.active {
            ActionButton(title: batch.stopTitle, icon: .square, size: .compact) { change("cancel-batch") }
          }
          if batch.applied != true && batch.counts["failed", default: 0] + batch.counts["paused", default: 0] > 0 {
            ActionButton(title: "重试剩余", icon: .refresh, size: .compact) { change("retry-batch") }
          }
          if batch.trial && !batch.active && batch.applied != true && matches > 0 {
            ActionButton(title: "应用标签", emphasis: .primary, size: .compact) { change("apply") }
          }
          if batch.trial {
            Toggle("只看命中", isOn: $matchesOnly).toggleStyle(CossToggleStyle()).font(UIType.small)
          }
          Spacer(minLength: 0)
        }.disabled(working)
      }.padding(12).framedSurface()
      if let error { WorkflowNotice(text: error, color: Palette.destructive) }
      if matchesOnly && matches == 0 {
        EmptyState(title: "暂无命中邮件", subtitle: "", icon: .tag)
      } else if let items = batch.items {
        WorkspaceList(items: matchesOnly ? items.filter { $0.matched == true } : items,
          header: { EmptyView() }, footer: { EmptyView() }) { item in
          resultRow(item).padding(.horizontal, 12).padding(.vertical, 9)
        }
      } else {
        Spacer(minLength: 0)
      }
    }.padding(20)
      .task(id: batch.active) {
        repeat {
          do {
            if !working {
              let revision = operationRevision
              let next: OrganizationBatch = try await store.backend.request("/mail-organization/batches/\(initial.id)")
              if !Task.isCancelled && revision == operationRevision { current = next }
            }
            if batch.active { try await Task.sleep(for: .seconds(1)) }
          } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
            return
          }
        } while batch.active && !Task.isCancelled
      }
  }

  private func resultRow(_ item: OrganizationBatch.Item) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text((item.subject?.isEmpty == false ? item.subject : nil) ?? "来源邮件")
          .font(UIType.section)
        Spacer()
        if let openSource, item.status != "skipped" {
          ActionButton(title: "原邮件", icon: .mail, size: .compact) { openSource(item.messageId) }
        }
      }
      Text(item.error ?? item.matched.map { $0 ? "符合条件" : "未命中" } ?? WorkspaceStatus.title(item.status))
        .font(UIType.small).foregroundStyle(Palette.muted)
      if let overview = item.overview {
        Text(overview).font(UIType.body).textSelection(.enabled)
      }
      ForEach(item.todos ?? []) { todo in
        Label(todo.due.isEmpty ? todo.title : "\(todo.title) · \(todo.due)", icon: .listCheck)
          .font(UIType.caption).foregroundStyle(Palette.muted)
      }
      if let names = item.labelNames, !names.isEmpty {
        WrappingFlowLayout(spacing: 6) {
          ForEach(names, id: \.self) { name in
            Tag(text: name, tone: store.categoryTone(name))
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func change(_ action: String) {
    operationRevision += 1
    working = true; error = nil
    Task {
      defer { working = false }
      do {
        if action == "apply" {
          try await store.backend.perform("/mail-organization/apply", body: ["id": batch.id, "approved": true])
          current = try await store.backend.request("/mail-organization/batches/\(batch.id)")
          try await store.refresh(reloadContent: false)
        } else {
          let next: OrganizationBatch
          if action == "cancel-batch" {
            next = try await store.stopOrganizationBatch(batch.id)
          } else {
            next = try await store.backend.request("/mail-organization/retry-batch", method: "POST", body: ["id": batch.id])
            store.recordOrganizationBatch(next)
          }
          current = next
        }
      } catch { self.error = error.localizedDescription }
    }
  }
}
