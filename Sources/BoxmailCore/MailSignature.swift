import Foundation

public enum MailSignature {
  /// Only a complete signature on its own final lines is a visual bottom anchor.
  public static func trailingRange(in body: String, signature: String) -> NSRange? {
    guard !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      body.hasSuffix(signature) else { return nil }
    let range = NSRange(location: body.utf16.count - signature.utf16.count, length: signature.utf16.count)
    guard range.location == 0 || (body as NSString).substring(
      with: NSRange(location: range.location - 1, length: 1)) == "\n" else { return nil }
    return range
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
