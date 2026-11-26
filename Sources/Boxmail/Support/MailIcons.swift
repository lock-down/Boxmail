import BoxmailCore

extension MailAITab {
  var icon: AppicaGlyph {
    switch self {
    case .summary: .alignLeft
    case .translate: .language
    case .attachment: .fileSearch
    case .reply: .arrowBackUp
    case .conversation: .messages
    }
  }
}

extension MailDestination {
  var icon: AppicaGlyph {
    switch self {
    case .inbox: .inbox
    case .starred: .star
    case .drafts: .edit
    case .sent: .send
    case .attachments: .paperclip
    case .trash: .trash
    case .summary: .alignLeft
    case .replies: .arrowBackUpDouble
    case .organize: .archive
    case .analysis: .fileSearch
    case .archive: .archive
    case .followUps: .listCheck
    case .rules: .adjustments
    case .outbox: .upload
    case .spam: .shieldBolt
    }
  }
}
