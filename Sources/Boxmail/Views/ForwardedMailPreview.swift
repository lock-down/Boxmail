import BoxmailCore
import SwiftUI

struct ForwardedMailPreview: View {
  let html: String?
  let text: String
  let preferences: Preferences
  @ViewState<CGFloat> private var height: CGFloat = 240
  @ViewState<Bool> private var loadImages = false
  private var hasRemoteImages: Bool {
    html?.range(of: #"(?i)<img\b[^>]*\bsrc="https?://"#, options: .regularExpression) != nil
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("转发原文").font(UIType.section)
        Spacer()
        Text("保留原邮件排版").font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let html, !html.isEmpty {
        if hasRemoteImages && preferences.blockRemoteImages && !loadImages {
          HStack(spacing: 10) {
            Text("原邮件包含外部图片").font(UIType.small).foregroundStyle(Palette.muted)
            ActionButton(title: "加载原邮件图片") { loadImages = true }
          }
        }
        HTMLMailBodyView(html: html, fontSize: preferences.fontSize,
          allowRemoteImages: !preferences.blockRemoteImages || loadImages, height: $height)
          .frame(height: height)
      } else {
        Text(text).font(UIType.body).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
  }
}
