import BoxmailCore
import SwiftUI

struct WritingPreferencesView: View {
  @Bindable var store: MailStore
  @Bindable var writing: WritingPreferencesStore
  let accountId: String
  @ViewState private var managingStyle = false
  @ViewState private var signature = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      WorkflowField(title: "输出语言") {
        WorkflowTextInput(
          label: "本次输出语言", placeholder: "跟随原邮件", text: $writing.language, font: UIType.caption)
      }
      WorkflowField(title: "写作风格") {
        HStack(spacing: 8) {
          WorkflowSelection(
            title: "写作风格", selection: $writing.selectedId,
            options: [("", "默认")] + writing.styles.map { ($0.id, $0.name) })
          IconButton(icon: .equalizer3Line, help: "管理写作风格") {
            let selected = writing.styles.first { $0.id == writing.selectedId }
            writing.name = selected?.name ?? ""
            writing.instruction = selected?.instruction ?? ""
            managingStyle = true
          }.cossPopover(isPresented: $managingStyle) { styleEditor }
        }
      }
      DisclosureGroup("此账户签名") {
        VStack(alignment: .leading, spacing: 12) {
          PlainTextEditor(text: $signature, placeholder: "账户专用签名", accessibilityLabel: "账户签名")
            .frame(height: 90)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: UILayout.controlRadius))
            .overlay {
              RoundedRectangle(cornerRadius: UILayout.controlRadius).strokeBorder(
                Palette.softBorder)
            }
          ActionButton(title: "保存签名", color: Palette.accent) {
            Task {
              var preferences = store.settings.preferences
              var signatures = preferences.accountSignatures ?? [:]
              signatures[accountId] = signature
              preferences.accountSignatures = signatures
              do {
                _ = try await store.saveSettings(ai: store.settings.ai, preferences: preferences)
              } catch { store.error = error.localizedDescription }
            }
          }
          Text("留空时沿用全局签名。保存后用于新邮件与回复，当前正文保留。")
            .font(UIType.small).foregroundStyle(Palette.muted)
        }.padding(.top, 8)
      }.disclosureGroupStyle(SettingsDisclosureStyle())
    }.font(UIType.caption).task {
      await writing.load()
      signature = store.settings.preferences.accountSignatures?[accountId] ?? ""
    }
    .onChange(of: accountId) { _, value in signature = store.settings.preferences.accountSignatures?[value] ?? "" }
  }
  private var styleEditor: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("写作风格").font(UIType.section)
      WorkflowField(title: "名称") {
        WorkflowTextInput(
          label: "风格名称", placeholder: "风格名称", text: $writing.name, font: UIType.caption)
      }
      WorkflowField(title: "要求") {
        PlainTextEditor(
          text: $writing.instruction, placeholder: "行文风格、结构与措辞偏好", accessibilityLabel: "写作风格要求"
        )
        .frame(height: 120).background(
          Palette.canvas, in: RoundedRectangle(cornerRadius: UILayout.controlRadius)
        )
        .overlay {
          RoundedRectangle(cornerRadius: UILayout.controlRadius).strokeBorder(Palette.softBorder)
        }
      }
      HStack(spacing: 8) {
        if !writing.selectedId.isEmpty {
          ActionButton(title: "移除") {
            Task {
              await writing.remove()
              managingStyle = false
            }
          }
          ActionButton(title: "另存为新风格") { writing.selectedId = "" }
        }
        Spacer(minLength: 0)
        ActionButton(title: "保存", emphasis: .primary) {
          Task {
            await writing.save()
            if writing.error == nil { managingStyle = false }
          }
        }.disabled(writing.name.isEmpty || writing.instruction.isEmpty)
      }
      if let error = writing.error { WorkflowNotice(text: error, color: Palette.amber) }
    }.padding(24).frame(width: 440).background(Palette.paper)
  }
}
