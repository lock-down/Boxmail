import Foundation

public enum MailHTMLDocument {
  public static func make(html: String, fontSize: Int, allowRemoteImages: Bool) -> String {
    let images = allowRemoteImages ? "data: https: http:" : "data:"
    let size = min(24, max(12, fontSize))
    return """
      <!doctype html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(images); style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'">
      <meta name="referrer" content="no-referrer">
      <style>
      html, body { margin: 0; padding: 0; background: white; color: #20242b; }
      body { font: \(size)px -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.6; overflow-wrap: anywhere; }
      #mail-content { display: flow-root; width: 100%; }
      #mail-content img { max-width: 100% !important; height: auto !important; }
      #mail-content table { max-width: 100% !important; }
      #mail-content pre { white-space: pre-wrap; }
      #mail-content a { color: #246de3; }
      </style></head><body><div id="mail-content">\(html)</div></body></html>
      """
  }

  public static func externalLink(_ url: URL) -> Bool {
    ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
      && url.user == nil && url.password == nil
  }
}
