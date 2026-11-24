import BoxmailCore

extension MailAITab {
  var icon: RemixGlyph {
    switch self {
    case .summary: .alignLeft
    case .translate: .translate2
    case .attachment: .fileSearchLine
    case .reply: .replyLine
    case .conversation: .discussLine
    }
  }
}

extension MailDestination {
  var icon: RemixGlyph {
    switch self {
    case .inbox: .inboxLine
    case .starred: .starLine
    case .drafts: .editBoxLine
    case .sent: .sendPlaneLine
    case .attachments: .attachment2
    case .trash: .deleteBin6Line
    case .summary: .alignLeft
    case .replies: .replyAllLine
    case .organize: .inboxArchiveLine
    case .analysis: .fileSearchLine
    case .archive: .archiveLine
    case .followUps: .listCheck3
    case .rules: .equalizer3Line
    case .outbox: .inboxUnarchiveLine
    case .spam: .shieldFlashLine
    }
  }
}
