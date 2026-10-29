import Foundation
import Testing
@testable import BoxmailCore

@Test func draftPreviewsDecodeWithoutChangingTheEditableBodyAndAllowLegacyRecords() throws {
  let draft = MailDraft(accountId: "a1", body: "\n\n-- \n张三\n示例公司")
  let bytes = try JSONEncoder().encode(draft)
  let legacy = try JSONDecoder().decode(MailDraft.self, from: bytes)
  #expect(legacy.preview == nil)
  #expect(legacy.body == draft.body)
  var wire = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
  for preview in ["", "草稿正文 On Tuesday, someone wrote: > 历史正文"] {
    wire["preview"] = preview
    let decoded = try JSONDecoder().decode(MailDraft.self, from: JSONSerialization.data(withJSONObject: wire))
    #expect(decoded.preview == preview)
    #expect(decoded.body == draft.body)
    #expect(decoded.status == "draft")
  }
}

@Test func signatureAnchorRequiresCompleteFinalLines() {
  let signature = "张三\n示例公司\nzhang@example.test"
  let body = "正文\n\n" + signature
  let range = MailSignature.trailingRange(in: body, signature: signature)
  #expect(range.map { (body as NSString).substring(with: $0) } == signature)
  #expect(MailSignature.trailingRange(in: signature, signature: signature)?.location == 0)
  #expect(MailSignature.trailingRange(in: "正文" + signature, signature: signature) == nil)
  #expect(MailSignature.trailingRange(in: signature + "\n后续正文", signature: signature) == nil)
  #expect(MailSignature.trailingRange(in: "正文\n\n", signature: "\n") == nil)
}

@Test(arguments: [("é", "e\u{301}"), ("e\u{301}", "é"), ("한", "\u{1112}\u{1161}\u{11ab}"), ("\u{20000}", "\u{20000}")])
func signatureRangeUsesTheActualBodyUnicodeRepresentation(pair: (String, String)) throws {
  for prefix in ["", "正文\n", "正文\r\n"] {
    let body = prefix + pair.0
    let range = try #require(MailSignature.trailingRange(in: body, signature: pair.1))
    #expect((body as NSString).substring(with: range) == pair.0)
    #expect(range.location == prefix.utf16.count)
    #expect(range.length == pair.0.utf16.count)
  }
  #expect(MailSignature.trailingRange(in: "正文" + pair.0, signature: pair.1) == nil)
}

@Test func generatedContentKeepsSignatureOnceWithoutRestoringRemovedSignatures() {
  let signature = "张三\n示例公司"
  let old = "旧正文\n\n" + signature
  #expect(MailSignature.replacingContent(with: "新正文\n", in: old, signature: signature) == "新正文\n\n" + signature)
  #expect(MailSignature.replacingContent(with: "新正文\n\n" + signature, in: old, signature: signature) == "新正文\n\n" + signature)
  #expect(MailSignature.replacingContent(with: "新正文", in: "用户已移除签名", signature: signature) == "新正文")
  #expect(MailSignature.replacingContent(with: "新正文", in: "", signature: "") == "新正文")
}

@Test func generatedForwardKeepsOwnSignatureAndDoesNotCopyQuotedSignature() {
  let signature = "张三\n示例公司"
  let forward = "\n\n" + signature + "\n\n---------- 转发邮件 ----------\n原邮件正文"
  #expect(MailSignature.replacingContent(with: "新的转发说明", in: forward, signature: signature) == "新的转发说明\n\n" + signature)
  let quoted = "\n\n---------- 转发邮件 ----------\n" + signature + "\n原邮件正文"
  #expect(MailSignature.replacingContent(with: "新正文", in: quoted, signature: signature) == "新正文")
}
