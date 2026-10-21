import BoxmailCore
import SwiftUI

struct OrganizeView: View {
  @Bindable var store: MailStore
  @ViewState<String> private var scope = "unclassified"
  @ViewState<Int> private var limit = 50
  @ViewState<String?> private var category: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ViewState<Bool> private var managingCategories = false
  private var categories: [String] { store.categories.map(\.name) }
  var latest: AgentJob? { store.latestOrganization }
  var inbox: [MailMessage] { store.accountMessages.filter { $0.folder == "inbox" } }
  var running: Bool { latest?.status == "running" }
  var hasReview: Bool {
    guard let latest else { return false }
    return ["needsApproval", "partial", "paused"].contains(latest.status)
      && !(latest.result?.items ?? []).isEmpty
  }
  var body: some View {
    OverlayScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 24) {
          VStack(alignment: .leading, spacing: 10) {
            PageHeading(title: "智能整理", subtitle: "按主题整理收件箱，确认建议后再应用分类")
            Label(store.currentAccount?.email ?? "当前账户", systemImage: "tray")
              .font(UIType.small).foregroundStyle(Palette.muted)
          }
          Spacer(minLength: 0)
          WorkflowAction(title: "管理分类", icon: "tag") { managingCategories = true }
            .disabled(running)
        }
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .bottom, spacing: 16) {
            WorkflowField(title: "整理范围") {
              WorkflowSelection(title: "整理范围", selection: $scope,
                options: [("unclassified", "尚未分类的收件邮件"), ("inbox", "全部收件邮件")])
            }.frame(width: 220)
            WorkflowField(title: "处理数量") {
              WorkflowSelection(title: "邮件数量", selection: $limit,
                options: [10, 50, 100, 200].map { ($0, "最近 \($0) 封") })
            }.frame(width: 136)
            Spacer(minLength: 0)
            WorkflowAction(title: "开始整理", icon: "wand.and.stars", color: Palette.blue) {
              store.organize(scope: scope, limit: limit)
            }.disabled(running || hasReview || store.busy.contains("organize-control") || inbox.isEmpty)
          }
          Text(hasReview ? "先确认已有建议，或继续补齐未完成的邮件。" : "分批在后台分析，整理期间可以继续阅读和回复邮件。")
            .font(UIType.small).foregroundStyle(Palette.muted)
        }.padding(20).background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.radius))
        if let error = store.organizeError {
          Label(error, systemImage: "exclamationmark.circle").font(.system(size: 12))
            .foregroundStyle(Palette.amber)
        }
        if let job = latest { jobStatus(job) }
        if let job = latest, !(job.result?.items ?? []).isEmpty,
          ["running", "needsApproval", "partial", "paused"].contains(job.status)
        {
          SectionCard(title: running ? "已完成的建议" : "确认分类建议", icon: "checklist") {
            HStack {
              Text("\(job.result?.items?.count ?? 0) 封邮件 · 仅修改本机标签").font(.system(size: 11))
                .foregroundStyle(Palette.muted)
              Spacer()
              WorkflowAction(title: "确认应用分类", icon: "checkmark", color: Palette.blue) {
                store.action("approve") {
                  try await BackendService.shared.perform("/jobs/\(job.id)/approve")
                }
              }.disabled(running || store.busy.contains("approve"))
            }
            LazyVStack(spacing: 0) {
              ForEach(job.result?.items ?? []) { item in
                HStack(spacing: 14) {
                  VStack(alignment: .leading, spacing: 5) {
                    Button {
                      if let mail = store.messages.first(where: { $0.id == item.id }) {
                        store.openMail(mail)
                      }
                    } label: {
                      Text(store.messages.first { $0.id == item.id }?.subject ?? "邮件已不在本机")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Text(item.reason).font(.system(size: 11)).foregroundStyle(Palette.muted)
                      .lineLimit(2)
                  }
                  Tag(text: item.category)
                }.padding(.vertical, 11)
                Divider().overlay(Palette.softBorder)
              }
            }
          }
        }
        HStack {
          Text("收件箱分类").font(.system(size: 16, weight: .semibold))
          Spacer()
          if category != nil {
            Button("查看全部") { category = nil }.buttonStyle(.plain).foregroundStyle(Palette.blue)
          }
          Text("\(inbox.count) 封邮件").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128))], spacing: 8) {
          ForEach(categories, id: \.self) { value in
            Button {
              withAnimation(UIMotion.selection(reduceMotion)) { category = category == value ? nil : value }
            } label: {
              HStack {
                Image(systemName: value == "账单票据" ? "doc.text" : "folder").foregroundStyle(
                  category == value ? Palette.accent : Palette.muted).font(.system(size: 13))
                Text(value).font(.system(size: 12, weight: .medium))
                  .lineLimit(1).truncationMode(.middle).help(value)
                Spacer()
                Text("\(inbox.filter { $0.category == value }.count)").font(
                  .system(size: 12, weight: .medium)
                ).monospacedDigit()
              }.padding(.horizontal, 12).frame(height: 42).frame(maxWidth: .infinity).contentShape(
                Rectangle()
              )
              .background(
                category == value ? Palette.accentSoft : .white,
                in: RoundedRectangle(cornerRadius: 8)
              )
            }.buttonStyle(ControlFeedback(selected: category == value))
              .controlFocus()
              .accessibilityAddTraits(category == value ? .isSelected : [])
          }
        }
        LazyVStack(spacing: 0) {
          let filtered = inbox.filter { category == nil || $0.category == category }
          ForEach(filtered) { mail in
            Button {
              store.openMail(mail)
            } label: {
              HStack(spacing: 20) {
                Text(mail.sender).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(
                  width: 130, alignment: .leading)
                Text(mail.subject).font(.system(size: 12)).lineLimit(1).frame(
                  maxWidth: .infinity, alignment: .leading)
                Tag(text: mail.category)
                Text(displayTime(mail.date)).font(.system(size: 10)).foregroundStyle(Palette.muted)
                  .frame(width: 80, alignment: .trailing)
              }.foregroundStyle(Palette.ink).padding(16).contentShape(Rectangle())
            }.buttonStyle(ControlFeedback(corner: 0)).controlFocus(corner: 0)
            Divider().overlay(Palette.softBorder)
          }
          if filtered.isEmpty {
            Text("这个分类暂时没有邮件").font(.system(size: 12)).foregroundStyle(Palette.muted).padding(30)
          }
        }.background(.white, in: RoundedRectangle(cornerRadius: 10))
      }.workspacePage()
    }.background(Palette.canvas)
      .sheet(isPresented: $managingCategories) { CategoryManagerView(store: store).borderlessScrollers() }
      .onChange(of: store.categories) { _, items in
        if let category, !items.contains(where: { $0.name == category }) { self.category = nil }
      }
  }
  private func jobStatus(_ job: AgentJob) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        if running { ProgressView().controlSize(.small) }
        Label(
          statusTitle(job), systemImage: job.status == "applied" ? "checkmark.circle" : "sparkles"
        )
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(
          job.status == "applied" ? Palette.success : Palette.accent)
        Spacer()
        if running {
          WorkflowAction(title: "暂停", icon: "pause") { store.pauseOrganization(job) }
            .disabled(store.busy.contains("organize-control"))
        } else if ["partial", "paused", "failed"].contains(job.status), job.progress != nil {
          WorkflowAction(title: "继续未完成邮件", icon: "arrow.clockwise", color: Palette.blue) {
            store.organize(retry: job)
          }
          .disabled(store.busy.contains("organize-control"))
        } else if job.status == "applied" {
          WorkflowAction(title: "撤销本次整理", icon: "arrow.uturn.backward") {
            store.action("undo") { try await BackendService.shared.perform("/jobs/\(job.id)/undo") }
          }.disabled(store.busy.contains("undo"))
        }
      }
      if let progress = job.progress {
        if !["applied", "undone"].contains(job.status) {
          ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
            .tint(
              Palette.accent)
            .animation(UIMotion.selection(reduceMotion), value: progress.completed)
        }
        HStack {
          Text("已分析 \(progress.completed) / \(progress.total) 封")
            .contentTransition(reduceMotion ? .identity : .numericText())
          Spacer()
          Text(running ? "正在分析第 \(max(1, progress.batch)) 批" : "建议保存在本机")
        }.font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
      }
      if let error = job.error, !error.isEmpty {
        Text(
          job.progress == nil && job.status == "failed"
            ? "上次连接中断或超时，可在上方重新开始分批整理。" : error
        )
        .font(.system(size: 11)).foregroundStyle(Palette.amber).textSelection(.enabled)
      }
      if running {
        Text("完成后在这里确认分类；暂停不会清空已完成的建议。").font(.system(size: 11)).foregroundStyle(Palette.muted)
      }
    }.padding(18).background(
      Palette.accentSoft, in: RoundedRectangle(cornerRadius: 10))
  }
  private func statusTitle(_ job: AgentJob) -> String {
    switch job.status {
    case "running": return "正在整理收件箱"
    case "needsApproval": return "整理完成，等待确认"
    case "partial": return "部分完成，已有建议可先确认"
    case "paused": return "整理已暂停"
    case "applied": return "分类已应用"
    case "undone": return "已撤销本次整理"
    default: return job.progress == nil ? "上次整理未完成" : "本次整理未完成"
    }
  }
}
