import AppKit
import SwiftUI

// SVG names match the vendored Appica Icons release.
enum AppicaGlyph: String, CaseIterable {
  case adjustments = "adjustments"
  case alertTriangle = "alert-triangle"
  case alignLeft = "align-left"
  case archive = "archive"
  case arrowBackUp = "arrow-back-up"
  case arrowBackUpDouble = "arrow-back-up-double"
  case arrowDown = "arrow-down"
  case arrowForwardUp = "arrow-forward-up"
  case arrowRight = "arrow-right"
  case arrowUp = "arrow-up"
  case arrowUpRight = "arrow-up-right"
  case bell = "bell"
  case bold = "bold"
  case bolt = "bolt"
  case bookmark = "bookmark"
  case bookmarkFilled = "bookmark-filled"
  case calendar = "calendar"
  case chartBar = "chart-bar"
  case check = "check"
  case chevronDown = "chevron-down"
  case chevronLeft = "chevron-left"
  case chevronRight = "chevron-right"
  case chevronRightBold = "chevron-right-bold"
  case chevronUp = "chevron-up"
  case chevronsUpDown = "chevrons-up-down"
  case circle = "circle"
  case circleCheck = "circle-check"
  case circleCheckFilled = "circle-check-filled"
  case circleMinus = "circle-minus"
  case circleXFilled = "circle-x-filled"
  case clock = "clock"
  case colorPicker = "color-picker"
  case copy = "copy"
  case cursorText = "cursor-text"
  case database = "database"
  case dots = "dots"
  case download = "download"
  case edit = "edit"
  case externalLink = "external-link"
  case feather = "feather"
  case file = "file"
  case fileExcel = "file-excel"
  case fileImport = "file-import"
  case fileSearch = "file-search"
  case fileText = "file-text"
  case fileTypePdf = "file-type-pdf"
  case fileTypePpt = "file-type-ppt"
  case fileZip = "file-zip"
  case filter2 = "filter-2"
  case folder = "folder"
  case folderCog = "folder-cog"
  case hammer = "hammer"
  case help = "help"
  case history = "history"
  case inbox = "inbox"
  case infoCircle = "info-circle"
  case language = "language"
  case layoutSidebarLeftExpand = "layout-sidebar-left-expand"
  case link = "link"
  case list = "list"
  case listCheck = "list-check"
  case listDetails = "list-details"
  case listNumbers = "list-numbers"
  case loader = "loader"
  case mail = "mail"
  case mailExclamation = "mail-exclamation"
  case mailOpened = "mail-opened"
  case messageAi = "message-ai"
  case messages = "messages"
  case minus = "minus"
  case palette = "palette"
  case paperclip = "paperclip"
  case pencilAi = "pencil-ai"
  case photo = "photo"
  case playerPause = "player-pause"
  case playerStopFilled = "player-stop-filled"
  case plus = "plus"
  case pointer = "pointer"
  case quote = "quote"
  case refresh = "refresh"
  case replace = "replace"
  case search = "search"
  case send = "send"
  case server = "server"
  case settings = "settings"
  case shieldBolt = "shield-bolt"
  case sparkles = "sparkles"
  case square = "square"
  case squareCheckFilled = "square-check-filled"
  case stack2 = "stack-2"
  case star = "star"
  case starFilled = "star-filled"
  case stethoscope = "stethoscope"
  case tag = "tag"
  case textSize = "text-size"
  case trash = "trash"
  case upload = "upload"
  case user = "user"
  case userCircle = "user-circle"
  case wand = "wand"
  case x = "x"
}

struct AppicaIcon: View {
  let glyph: AppicaGlyph
  let size: CGFloat

  init(_ glyph: AppicaGlyph, size: CGFloat = UILayout.iconSize) {
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

  private static let images: [AppicaGlyph: NSImage] = Dictionary(uniqueKeysWithValues:
    AppicaGlyph.allCases.compactMap { glyph in
      guard let url = Bundle.module.url(forResource: glyph.rawValue, withExtension: "svg", subdirectory: "AppicaIcon"),
        let image = NSImage(contentsOf: url) else {
        assertionFailure("Missing Appica Icons resource: \(glyph.rawValue)")
        return nil
      }
      return (glyph, image)
    }
  )
}

extension Label where Title == Text, Icon == AppicaIcon {
  @MainActor init(_ title: String, icon: AppicaGlyph, iconSize: CGFloat = UILayout.iconSize) {
    self.init { Text(title) } icon: { AppicaIcon(icon, size: iconSize) }
  }
}
