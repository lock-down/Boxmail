import { accountReference } from './diagnostics.js';

const knownFields = new Set([
  "accountId accounts action activeProvider actual addressPlaceholder ai aiKey aiProviderKeys alignments",
  "analysis analysisPreview apiProtocol appVersion attachmentId attachmentIds attachmentItems attachments",
  "baseURL batch batchSize bcc body bodyLoaded bodyVersion cached canAnalyze capability catalogConfigured",
  "catalogScope categories category cc changedCount changes checked compact compat completed conditions",
  "configuration contacts contentType contextWindow contextWindowDraft count counts createdAt",
  "credentialAccount credentialAccounts credentialReferences credentials credentialsIncluded date description",
  "detail directory displayName done downloaded draftId drafts due effort email enabled error events existing",
  "expected failed field fileURL folder folders forceAdaptiveThinking format forwardedHTML forwardedText",
  "frequency groupTotal hasAnalysis hasExtractedText hasMore hasRemoteImages headers headersVersion html icon",
  "id imapHost imapPort imapTLS inReplyTo indexed input inputTypes instruction inventory isAI isAnalyzed",
  "isDemo isFinished isImage isInSummaryOverview isPDF isPresentation isRunning isSpreadsheet items jobs",
  "keyInfo kind label language lastError lastProgressAt lastSync lastUsed latestMessageId level mailPasswords",
  "markRead marker maxTokens maxTokensDraft maxTokensField messageId messages metadataCount model",
  "modelCatalog models name nextOffset nextSteps offeredLevels output outputs overview overviewText",
  "parentJobId parseError partial path payload pending pendingDirectory pendingMutations phase plainText",
  "points preferences preview previousBackup processIdentifier progress prompt prompts providerId providers",
  "query range reason reasoningEfforts reasoningLevels references remaining remotePath replyPreset replyTo",
  "restoreFolder restoreTitle result results revealedMessage revision rows runningAccounts searchIndex",
  "searchSnippet sender senderEmail senderGroups settings sha256 sidebarName signature size smtpHost smtpPort",
  "smtpTLS sourceId sourceMessageId stage starred startedAt status statusCount subject summary summaryHidden",
  "sync syncMinutes table task terms text textPreview time timeout title to todos total totalBytes",
  "translation translationHTML type uid uidCount uidValidity unarchiveFolder unarchiveTitle undo unread",
  "unreadCount updatedAt url username usesBYOK usesWorkbookPreview validationIssue value values version",
].join(' ').split(' '));
const kinds = { messages: 'message', accounts: 'account', attachments: 'attachment', drafts: 'draft',
  jobs: 'job', settings: 'settings', output: 'ai_output', outputs: 'ai_output' };
export function diagnosticPath(parts) {
  const value = '$' + parts.map(part => typeof part === 'number' ? `[${part}]`
    : '.' + (knownFields.has(part) ? part : ':key')).join('');
  return value.length <= 160 ? value : value.slice(0, 96) + '...' + value.slice(-61);
}
export function diagnosticRecord(value, path, parent = {}, kind) {
  const recordID = parent.recordID || (typeof value?.id === 'string' ? value.id : undefined);
  const accountID = parent.accountID || (typeof value?.accountId === 'string' ? value.accountId
    : path[0] === 'accounts' && typeof value?.id === 'string' ? value.id : undefined);
  return { path, recordID, accountID, recordKind: parent.recordKind || kind || kinds[path[0]] };
}

export function diagnosticReferences(context) {
  return { record: context?.recordID ? accountReference(context.recordID) : undefined,
    account: context?.accountID ? accountReference(context.accountID) : undefined };
}
