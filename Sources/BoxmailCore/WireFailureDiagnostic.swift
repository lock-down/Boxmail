import CoreFoundation
import Foundation

/// Structural evidence only. Values and arbitrary dictionary keys never enter logs.
enum WireFailureDiagnostic {
  private static let knownFields = Set(
    """
    accountId accounts action activeProvider actual addressPlaceholder ai aiKey aiProviderKeys alignments
    analysis analysisPreview apiProtocol appVersion attachmentId attachmentIds attachmentItems attachments
    baseURL batch batchSize bcc body bodyLoaded bodyVersion cached canAnalyze capability catalogConfigured
    catalogScope categories category cc changedCount changes checked compact compat completed conditions
    configuration contacts contentType contextWindow contextWindowDraft count counts createdAt
    credentialAccount credentialAccounts credentialReferences credentials credentialsIncluded credentialsRequired date
    description detail directory displayName done downloaded draftId drafts due effort email enabled error
    events existing expected failed field fileURL folder folders forceAdaptiveThinking format forwardedHTML
    forwardedText frequency groupTotal hasAnalysis hasExtractedText hasMore hasRemoteImages headers
    headersVersion html icon id imapHost imapPort imapTLS inReplyTo indexed input inputTypes instruction
    inventory isAI isAnalyzed isDemo isFinished isImage isInSummaryOverview isPDF isPresentation isRunning
    isSpreadsheet items jobs keyInfo kind label language lastError lastProgressAt lastSync lastUsed
    latestMessageId level mailPasswords markRead marker maxTokens maxTokensDraft maxTokensField messageId
    messages metadataCount model modelCatalog models name nextOffset nextSteps offeredLevels output outputs
    overview overviewText parentJobId parseError partial path payload pending pendingDirectory
    pendingMutations phase plainText points preferences preview previousBackup processIdentifier progress
    prompt prompts providerId providers query range reason reasoningEfforts reasoningLevels references
    remaining remotePath replyPreset replyTo restoreFolder restoreTitle result results revealedMessage
    revision rows runningAccounts searchIndex searchSnippet sender senderEmail senderGroups settings sha256
    sidebarName signature size smtpHost smtpPort smtpTLS sourceId sourceMessageId stage starred startedAt
    status statusCount subject summary summaryHidden sync syncMinutes table task terms text textPreview time
    timeout title to todos total totalBytes translation translationHTML type uid uidCount uidValidity
    unarchiveFolder unarchiveTitle undo unread unreadCount updatedAt url username usesBYOK
    usesWorkbookPreview validationIssue value values version
    """.split(whereSeparator: \.isWhitespace).map(String.init))

  static func fields(_ error: Error, data: Data?) -> [String: String] {
    let context: DecodingError.Context
    var missingKey: CodingKey?
    var fields: [String: String] = ["phase": "decode"]
    switch error {
    case DecodingError.typeMismatch(let type, let detail):
      context = detail
      fields["reason"] = "type_mismatch"
      fields["expectedType"] = expectedType(type)
    case DecodingError.valueNotFound(let type, let detail):
      context = detail
      fields["reason"] = "value_missing"
      fields["expectedType"] = expectedType(type)
    case DecodingError.keyNotFound(let key, let detail):
      context = detail
      missingKey = key
      fields["reason"] = "key_missing"
      fields["expectedType"] = "present"
    case DecodingError.dataCorrupted(let detail):
      context = detail
      fields["reason"] = "invalid_value"
      fields["expectedType"] = "valid_value"
    default: return [:]
    }
    var keys = context.codingPath
    if let missingKey { keys.append(missingKey) }
    let path =
      "$"
      + keys.map { key in
        key.intValue.map { "[\($0)]" } ?? "."
          + (knownFields.contains(key.stringValue) ? key.stringValue : ":key")
      }.joined()
    fields["field"] =
      path.count <= 160 ? path : String(path.prefix(96)) + "..." + String(path.suffix(61))
    let kinds = [
      "messages": "message", "accounts": "account", "attachments": "attachment", "drafts": "draft",
      "jobs": "job", "settings": "settings",
    ]
    fields["recordKind"] = keys.first.flatMap { kinds[$0.stringValue] } ?? "object"
    guard let data else {
      fields["actualType"] = "unavailable"
      return fields
    }
    fields["responseBytes"] = String(data.count)
    guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      fields["actualType"] = "invalid_json"
      return fields
    }
    func remember(_ value: Any?) {
      guard let object = value as? [String: Any] else { return }
      if fields["record"] == nil, let id = object["id"] as? String {
        fields["record"] = RuntimeDiagnostics.accountReference(id)
        if fields["recordKind"] == "account" {
          fields["account"] = RuntimeDiagnostics.accountReference(id)
        }
      }
      if fields["account"] == nil, let id = object["accountId"] as? String {
        fields["account"] = RuntimeDiagnostics.accountReference(id)
      }
    }
    var value: Any? = root
    remember(value)
    for key in keys {
      if let index = key.intValue, let array = value as? [Any] {
        value = array.indices.contains(index) ? array[index] : nil
      } else {
        value = (value as? [String: Any])?[key.stringValue]
      }
      remember(value)
    }
    fields["actualType"] = actualType(value)
    return fields
  }

  private static func expectedType(_ type: Any.Type) -> String {
    if type == String.self { return "string" }
    if type == Bool.self { return "boolean" }
    if type == Int.self || type == Int64.self || type == UInt.self || type == UInt64.self {
      return "integer"
    }
    if type == Double.self || type == Float.self { return "number" }
    if String(describing: type).hasPrefix("Array<") { return "array" }
    return "object"
  }
  private static func actualType(_ value: Any?) -> String {
    guard let value else { return "missing" }
    if value is NSNull { return "null" }
    if value is String { return "string" }
    if let number = value as? NSNumber {
      return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
    }
    if value is [Any] { return "array" }
    return "object"
  }
}
