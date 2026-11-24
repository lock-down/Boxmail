import AppKit
import SwiftUI

// SVG names match the vendored Remix Icon release.
enum RemixGlyph: String, CaseIterable {
  case accountCircleLine = "account-circle-line"
  case addLine = "add-line"
  case alertLine = "alert-line"
  case alignLeft = "align-left"
  case archiveLine = "archive-line"
  case archiveStackLine = "archive-stack-line"
  case arrowDownLine = "arrow-down-line"
  case arrowDownSLine = "arrow-down-s-line"
  case arrowGoBackLine = "arrow-go-back-line"
  case arrowLeftSLine = "arrow-left-s-line"
  case arrowRightLine = "arrow-right-line"
  case arrowRightSLine = "arrow-right-s-line"
  case arrowRightUpLine = "arrow-right-up-line"
  case arrowUpLine = "arrow-up-line"
  case arrowUpSLine = "arrow-up-s-line"
  case attachment2 = "attachment-2"
  case barChart2Line = "bar-chart-2-line"
  case bold = "bold"
  case bookmarkFill = "bookmark-fill"
  case bookmarkLine = "bookmark-line"
  case calendarLine = "calendar-line"
  case chatAiLine = "chat-ai-line"
  case checkLine = "check-line"
  case checkboxBlankCircleLine = "checkbox-blank-circle-line"
  case checkboxBlankLine = "checkbox-blank-line"
  case checkboxCircleFill = "checkbox-circle-fill"
  case checkboxCircleLine = "checkbox-circle-line"
  case checkboxFill = "checkbox-fill"
  case closeCircleFill = "close-circle-fill"
  case closeLine = "close-line"
  case cursorLine = "cursor-line"
  case database2Line = "database-2-line"
  case deleteBin6Line = "delete-bin-6-line"
  case discussLine = "discuss-line"
  case doubleQuotesL = "double-quotes-l"
  case downloadLine = "download-line"
  case dropperLine = "dropper-line"
  case editBoxLine = "edit-box-line"
  case equalizer3Line = "equalizer-3-line"
  case errorWarningLine = "error-warning-line"
  case expandUpDownLine = "expand-up-down-line"
  case exportLine = "export-line"
  case externalLinkLine = "external-link-line"
  case fileCopyLine = "file-copy-line"
  case fileExcelLine = "file-excel-line"
  case fileLine = "file-line"
  case fileList3Line = "file-list-3-line"
  case filePdfLine = "file-pdf-line"
  case filePptLine = "file-ppt-line"
  case fileSearchLine = "file-search-line"
  case fileTextLine = "file-text-line"
  case fileZipLine = "file-zip-line"
  case filter3Line = "filter-3-line"
  case findReplaceLine = "find-replace-line"
  case flashlightLine = "flashlight-line"
  case folderLine = "folder-line"
  case folderSettingsLine = "folder-settings-line"
  case fontSize = "font-size"
  case hammerLine = "hammer-line"
  case hardDrive2Line = "hard-drive-2-line"
  case historyLine = "history-line"
  case imageLine = "image-line"
  case importLine = "import-line"
  case inbox2Line = "inbox-2-line"
  case inboxArchiveLine = "inbox-archive-line"
  case inboxLine = "inbox-line"
  case inboxUnarchiveLine = "inbox-unarchive-line"
  case indeterminateCircleLine = "indeterminate-circle-line"
  case informationLine = "information-line"
  case inputCursorMove = "input-cursor-move"
  case link = "link"
  case listCheck3 = "list-check-3"
  case listOrdered = "list-ordered"
  case listUnordered = "list-unordered"
  case loader4Line = "loader-4-line"
  case loopRightLine = "loop-right-line"
  case magicLine = "magic-line"
  case mailLine = "mail-line"
  case mailOpenLine = "mail-open-line"
  case mailUnreadLine = "mail-unread-line"
  case moreLine = "more-line"
  case notification3Line = "notification-3-line"
  case paletteLine = "palette-line"
  case pauseLine = "pause-line"
  case pencilAiLine = "pencil-ai-line"
  case priceTag3Line = "price-tag-3-line"
  case questionLine = "question-line"
  case quillPenLine = "quill-pen-line"
  case refreshLine = "refresh-line"
  case replyAllLine = "reply-all-line"
  case replyLine = "reply-line"
  case searchLine = "search-line"
  case sendPlaneLine = "send-plane-line"
  case settings3Line = "settings-3-line"
  case shareForwardLine = "share-forward-line"
  case shieldFlashLine = "shield-flash-line"
  case sidebarUnfoldLine = "sidebar-unfold-line"
  case sparkling2Line = "sparkling-2-line"
  case starFill = "star-fill"
  case starLine = "star-line"
  case stethoscopeLine = "stethoscope-line"
  case stopFill = "stop-fill"
  case subtractLine = "subtract-line"
  case timeLine = "time-line"
  case translate2 = "translate-2"
  case userLine = "user-line"
}

struct RemixIcon: View {
  let glyph: RemixGlyph
  let size: CGFloat

  init(_ glyph: RemixGlyph, size: CGFloat = UILayout.iconSize) {
    self.glyph = glyph
    self.size = size
  }

  var body: some View {
    Group {
      if let image = Self.images[glyph] {
        Image(nsImage: image).renderingMode(.template).resizable()
      }
    }.frame(width: size, height: size).accessibilityHidden(true)
  }

  private static let images: [RemixGlyph: NSImage] = Dictionary(uniqueKeysWithValues:
    RemixGlyph.allCases.compactMap { glyph in
      guard let url = Bundle.module.url(forResource: glyph.rawValue, withExtension: "svg", subdirectory: "RemixIcon"),
        let image = NSImage(contentsOf: url) else {
        assertionFailure("Missing Remix Icon resource: \(glyph.rawValue)")
        return nil
      }
      return (glyph, image)
    }
  )
}

extension Label where Title == Text, Icon == RemixIcon {
  @MainActor init(_ title: String, icon: RemixGlyph, iconSize: CGFloat = UILayout.iconSize) {
    self.init { Text(title) } icon: { RemixIcon(icon, size: iconSize) }
  }
}
