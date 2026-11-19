import AppKit

enum TextSubmitShortcut: String, CaseIterable {
  case returnKey = "return"
  case commandReturn = "commandReturn"

  var keycap: String { self == .returnKey ? "Return" : "⌘ Return" }
  var title: String { self == .returnKey ? "Return 发送" : "Command + Return 发送" }
  var newlineHint: String { self == .returnKey ? "Shift + Return 换行" : "Return 换行" }

  func matches(_ modifiers: NSEvent.ModifierFlags) -> Bool {
    let keys = modifiers.intersection([.command, .shift, .option, .control])
    return self == .returnKey ? keys.isEmpty : keys == .command
  }
}
