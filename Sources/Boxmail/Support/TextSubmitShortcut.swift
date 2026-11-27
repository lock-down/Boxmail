import AppKit

enum TextSubmitShortcut: String, CaseIterable {
  case returnKey = "return"
  case commandReturn = "commandReturn"

  var title: String { self == .returnKey ? "Return 发送" : "Command + Return 发送" }

  func matches(_ modifiers: NSEvent.ModifierFlags) -> Bool {
    let keys = modifiers.intersection([.command, .shift, .option, .control])
    return self == .returnKey ? keys.isEmpty : keys == .command
  }
}
