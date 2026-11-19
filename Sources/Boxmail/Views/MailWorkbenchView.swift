import SwiftUI

struct MailWorkbenchView: View {
  @Bindable var store: MailStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 16) {
        Text("邮件工作台").font(UIType.heading).accessibilityAddTraits(.isHeader)
        Divider().frame(height: 18)
        SelectionButton(title: "跟进", icon: "checklist", selected: store.destination == .followUps, size: .compact) {
          store.navigate(.followUps)
        }
        SelectionButton(title: "摘要", icon: "text.alignleft", selected: store.destination == .summary, size: .compact) {
          store.navigate(.summary)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      Divider().overlay(Palette.softBorder)
      if store.destination == .summary {
        SummaryOverviewView(store: store)
      } else {
        FollowUpsView(store: store, workspace: store.followUps)
      }
    }.workspacePage().background(Palette.paper)
  }
}
