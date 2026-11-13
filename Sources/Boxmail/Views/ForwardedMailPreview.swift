import BoxmailCore
import SwiftUI

struct ForwardedMailPreview: View {
  let html: String?
  let text: String
  let preferences: Preferences
  @ViewState<CGFloat> private var height: CGFloat = 240
  @ViewState<Bool> private var loadImages = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("转发原文").font(UIType.section)
        Spacer()
        Text("保留原邮件排版").font(UIType.small).foregroundStyle(Palette.muted)
      }
      if let html, !html.isEmpty {
        if MailHTMLDocument.hasRemoteImages(html), preferences.blockRemoteImages, !loadImages {
          RemoteImagesBanner(text: "原邮件包含外部图片", buttonTitle: "加载原邮件图片") {
            loadImages = true
          }
        }
        HTMLMailBodyView(html: html, fontSize: preferences.fontSize,
          allowRemoteImages: !preferences.blockRemoteImages || loadImages, height: $height)
          .frame(height: height)
      } else {
        RecipientTextBodyView(text: text, font: UIType.body)
      }
    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
  }
}
