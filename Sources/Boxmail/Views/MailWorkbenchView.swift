import SwiftUI

struct MailWorkbenchView: View {
  @Bindable var store: MailStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 16) {
        Text("邮件工作台").font(UIType.title).tracking(-0.4).accessibilityAddTraits(.isHeader)
        HStack(spacing: 4) {
          SelectionButton(title: "跟进", icon: .listCheck3, selected: store.destination == .followUps,
            size: .compact, appearance: .segmented) { store.navigate(.followUps) }
          SelectionButton(title: "摘要", icon: .alignLeft, selected: store.destination == .summary,
            size: .compact, appearance: .segmented) { store.navigate(.summary) }
        }.segmentedSurface()
      }.frame(maxWidth: .infinity, alignment: .leading)
      CossSeparator()
      if store.destination == .summary {
        SummaryOverviewView(store: store)
      } else {
        FollowUpsView(store: store, workspace: store.followUps)
      }
    }.workspacePage().background(Palette.paper)
  }
}
