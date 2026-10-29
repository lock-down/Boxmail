import Foundation

public enum MailSignature {
  /// Only a complete signature on its own final lines is a visual bottom anchor.
  public static func trailingRange(in body: String, signature: String) -> NSRange? {
    guard !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let range = body.range(of: signature, options: [.anchored, .backwards]),
      range.lowerBound == body.startIndex || body[body.index(before: range.lowerBound)].isNewline
    else { return nil }
    return NSRange(range, in: body)
  }

  public static func replacingContent(with content: String, in body: String, signature: String) -> String {
    let hasTrailingSignature = trailingRange(in: body, signature: signature) != nil
    let hasForwardSignature = !signature.isEmpty
      && body.hasPrefix("\n\n" + signature + "\n\n---------- 转发邮件 ----------")
    guard hasTrailingSignature || hasForwardSignature else { return content }
    if trailingRange(in: content, signature: signature) != nil { return content }
    return content.trimmingCharacters(in: .newlines) + "\n\n" + signature
  }
}
