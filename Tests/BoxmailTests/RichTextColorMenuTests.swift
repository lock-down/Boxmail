import AppKit
import BoxmailCore
import Testing

@testable import Boxmail

@Suite(.serialized) @MainActor struct RichTextColorMenuTests {
  @Test func everyMenuSwatchRetainsItsActualColorInsteadOfUsingTemplateTint() throws {
    _ = NSApplication.shared
    let button = RichTextColorButton(
      frame: NSRect(x: 0, y: 0, width: 32, height: 32), pullsDown: true)
    for (index, option) in RichTextColorMenu.colors.enumerated() {
      let image = try #require(button.menu?.item(at: index + 1)?.image)
      #expect(!image.isTemplate)
      let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
      let bitmap = NSBitmapImageRep(cgImage: cgImage)
      var pixel = [Int](repeating: 0, count: 4)
      bitmap.getPixel(&pixel, atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
      let expected = RichTextStyle.nsColor(option.hex)
      #expect(bitmap.bitsPerSample == 8)
      #expect(abs(Double(pixel[0]) / 255 - expected.redComponent) < 0.01)
      #expect(abs(Double(pixel[1]) / 255 - expected.greenComponent) < 0.01)
      #expect(abs(Double(pixel[2]) / 255 - expected.blueComponent) < 0.01)
    }
  }

  @Test func menuChecksFollowSelectionAndActionsKeepExactColorsIncludingDefaultAndCustom() throws {
    _ = NSApplication.shared
    let button = RichTextColorButton(frame: .zero, pullsDown: true)
    var choices: [String?] = []
    var customRequests = 0
    button.update(
      color: "#B42318", mixed: false, enabled: true,
      onSelect: { choices.append($0) }, onCustom: { customRequests += 1 })
    let menu = try #require(button.menu)
    let redIndex = try #require(menu.items.firstIndex { $0.title == "红色" })
    let defaultIndex = try #require(menu.items.firstIndex { $0.title == "默认" })
    #expect(menu.items.filter { $0.state == .on }.map(\.title) == ["红色"])
    menu.performActionForItem(at: redIndex)
    menu.performActionForItem(at: defaultIndex)
    menu.performActionForItem(at: menu.items.count - 1)
    #expect(choices == ["#B42318", nil])
    #expect(customRequests == 1)
    button.update(
      color: nil, mixed: true, enabled: false,
      onSelect: { choices.append($0) }, onCustom: { customRequests += 1 })
    #expect(menu.items.allSatisfy { $0.state == .off })
    menu.performActionForItem(at: redIndex)
    menu.performActionForItem(at: menu.items.count - 1)
    #expect(choices.count == 2 && customRequests == 1)
  }
}
