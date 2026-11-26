import BoxmailCore
import SwiftUI

struct MailTranslationControls: View {
  @Bindable var store: MailStore
  let message: MailMessage

  var body: some View {
    let preference = store.translationPreference(for: message)
    let key = store.translationKey(for: message)
    let showing = store.isShowingTranslation(message)
    let result = store.translationResult(message, language: preference.language)
    let output = store.translationOutput(for: message)
    let running = store.translationRequests.contains(key)
    let error = store.translationErrors[key]
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(showing && result != nil ? "\(preference.language.title)译文" : "邮件原文")
          .font(UIType.small).foregroundStyle(Palette.muted)
        CossSeparator()
        if showing, let result {
          CopyButton(help: "复制\(preference.language.title)译文") { result.text }
        }
        if running {
          CossSpinner(size: 14).accessibilityLabel(output?.stage ?? "正在翻译")
        }
        HStack(spacing: 0) {
          ActionButton(title: showing ? "显示原文" : error != nil ? "重试翻译" : "翻译",
            icon: .language, size: .compact) {
            store.toggleTranslation(message)
          }
          CossSeparator(axis: .vertical).frame(height: 16)
          CossMenu(title: "翻译设置", value: preference.language.title) {
            CossMenuItem.command("自动翻译外语邮件（Auto）", mark: .checkbox(preference.auto)) {
              store.changeTranslationPreference(message, auto: !preference.auto)
            }
            CossMenuItem.note("打开外语邮件时使用当前配置的 AI 服务商")
            CossMenuItem.divider
            CossMenuItem.submenu("译为…", value: preference.language.title, items: MailTranslationLanguage.allCases.map { language in
              .command(language.title, mark: .choice(preference.language == language)) {
                store.changeTranslationPreference(message, language: language)
              }
            })
          } trigger: {
            AppicaIcon(.chevronDown, size: UILayout.compactIconSize).foregroundStyle(Palette.muted).frame(width: 24, height: 28)
          }
        }.fixedSize().framedSurface(radius: UILayout.menuRadius)
      }
      if let error { WorkflowNotice(text: error, color: Palette.amber) }
    }
  }
}
