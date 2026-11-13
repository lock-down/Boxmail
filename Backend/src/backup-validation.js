import { mailBody } from './mail-body.js';
import { archiveProjection, validateArchiveDocument } from './attachment-archive-store.js';
import { accountInput, aiConfig, ServiceError } from './validation.js';
import { richContent, richFromHTML } from './rich-text.js';

const strings = (value, names) => names.every(name => typeof value[name] === 'string');
const bools = (value, names) => names.every(name => typeof value[name] === 'boolean');
const integers = (value, names) => names.every(name => Number.isSafeInteger(value[name]));
const stringArray = value => Array.isArray(value) && value.every(item => typeof item === 'string');
const object = value => value && typeof value === 'object' && !Array.isArray(value);
function mailShape(value) {
  if (!strings(value, ['id', 'accountId', 'folder', 'sender', 'senderEmail', 'to', 'cc', 'subject', 'body', 'preview', 'date', 'category'])
    || !bools(value, ['unread', 'starred']) || !stringArray(value.attachmentIds)) return false;
  const summary = value.summary;
  if (value.summaryHidden != null && typeof value.summaryHidden !== 'boolean') return false;
  if (['html', 'translation', 'translationHTML'].some(name => value[name] != null && typeof value[name] !== 'string')) return false;
  return !summary || object(summary) && stringArray(summary.points) && Array.isArray(summary.todos)
    && summary.todos.every(todo => strings(todo, ['id', 'title', 'due']) && bools(todo, ['done']))
    && Array.isArray(summary.keyInfo) && summary.keyInfo.every(item => strings(item, ['label', 'value']));
}

export function validateBackupRecords(records) {
  const values = records.map(row => ({ kind: row.kind, value: JSON.parse(row.data) }));
  const accountIDs = new Set(values.filter(row => row.kind === 'account').map(row => row.value.id));
  const attachmentIDs = new Set(values.filter(row => row.kind === 'attachment').map(row => row.value.id));
  const fail = () => { throw new ServiceError('备份中的记录字段或附件关联无效，当前数据未更改'); };
  for (const { kind, value } of values) {
    if (!object(value) || typeof value.id !== 'string') fail();
    if (kind === 'account' && (!strings(value, ['name', 'email', 'username', 'imapHost', 'smtpHost'])
      || !integers(value, ['imapPort', 'smtpPort']) || !bools(value, ['imapTLS', 'smtpTLS', 'isDemo']))) fail();
    if (kind === 'account' && !value.isDemo) { try { accountInput(value); } catch { fail(); } }
    if (kind === 'message' && !mailShape(value)) fail();
    if (kind === 'draft' && (!strings(value, ['accountId', 'to', 'cc', 'bcc', 'subject', 'body', 'status', 'updatedAt'])
      || !stringArray(value.attachmentIds)
      || (value.forwardedHTML != null || value.forwardedText != null)
        && !strings(value, ['forwardedHTML', 'forwardedText']))) fail();
    if (kind === 'draft') {
      if (value.bodyHTML != null && (typeof value.bodyHTML !== 'string' || value.bodyHTML.length > 8 * 1024 * 1024)) fail();
      try {
        if (value.richText != null) Object.assign(value, richContent(value.richText));
        else if (value.bodyHTML != null) Object.assign(value, richFromHTML(value.bodyHTML));
        if (value.forwardedHTML != null) value.forwardedHTML = mailBody({ html: value.forwardedHTML }).html;
      } catch { fail(); }
      for (const binding of [value.remoteDraft, value.remotePending, value.remotePending?.previous]) {
        if (binding == null) continue;
        if (!object(binding) || typeof binding.path !== 'string' || binding.path.includes('\0') || binding.path.length > 1000
          || binding.uid != null && (!Number.isSafeInteger(binding.uid) || binding.uid < 1)
          || binding.uidValidity != null && !/^\d+$/.test(binding.uidValidity)
          || typeof binding.baseHash !== 'string' || !/^[a-f0-9]{64}$/.test(binding.baseHash)) fail();
      }
    }
    if (kind === 'draftDeletion' && (!accountIDs.has(value.accountId) || typeof value.path !== 'string'
      || (!Number.isSafeInteger(value.uid) || value.uid < 1 || !/^\d+$/.test(value.uidValidity || ''))
        && (typeof value.token !== 'string' || value.token.length > 100))) fail();
    if (['message', 'draft'].includes(kind) && (!accountIDs.has(value.accountId)
      || value.attachmentIds.some(id => !attachmentIDs.has(id)))) fail();
    if (kind === 'attachment' && (!strings(value, ['messageId', 'name', 'contentType', 'path', 'text', 'parseError', 'date'])
      || !integers(value, ['size']) || value.size < 0)) fail();
    if (kind === 'attachment' && value.archive != null) {
      try { validateArchiveDocument(value.archive); } catch { delete value.archive; delete value.archiveInfo; }
    }
    if (kind === 'archive') {
      try { validateArchiveDocument(value); } catch {
        for (const key of Object.keys(value)) if (key !== 'id') delete value[key];
        value.discarded = true;
      }
    }
    if (['relocation', 'recovery'].includes(kind) && (!object(value.original) || !mailShape(value.original)
      || !accountIDs.has(value.original.accountId) || value.original.attachmentIds.some(id => !attachmentIDs.has(id)))) fail();
    if (kind === 'job') {
      if (!strings(value, ['task', 'status', 'createdAt'])) fail();
      if (value.result != null && !object(value.result)) fail();
      if (value.result?.items != null && (!Array.isArray(value.result.items)
        || value.result.items.some(item => !strings(item, ['id', 'category', 'reason'])))) fail();
      if (value.progress != null && !integers(value.progress, ['total', 'completed', 'failed', 'batchSize', 'batch'])) fail();
      if (value.attachmentItems != null && (!Array.isArray(value.attachmentItems)
        || value.attachmentItems.some(item => !strings(item, ['id', 'name', 'status'])))) fail();
    }
    if (kind === 'sync' && !strings(value, ['accountId', 'folder', 'status'])) fail();
    if (kind === 'categoryCatalog' && (!Array.isArray(value.items)
      || value.items.some(item => !strings(item, ['id', 'name', 'description'])))) fail();
    if (kind === 'settings') {
      const ai = value.ai, p = value.preferences;
      if (!object(ai) || !strings(ai, ['baseURL', 'model', 'effort']) || !integers(ai, ['timeout'])
        || !bools(ai, ['enabled']) || !object(ai.prompts) || Object.values(ai.prompts).some(item => typeof item !== 'string')
        || !object(p) || !integers(p, ['syncMinutes', 'fontSize']) || !strings(p, ['signature', 'language'])
        || !bools(p, ['markRead', 'launchAtLogin', 'notifications', 'blockRemoteImages', 'spamFilter'])) fail();
      try { aiConfig(ai, { requireModel: false }); } catch { fail(); }
      if (ai.timeout < 10 || ai.timeout > 600 || p.syncMinutes < 1 || p.syncMinutes > 60
        || p.fontSize < 12 || p.fontSize > 24 || p.signature.length > 4000 || !p.language.trim()) fail();
    }
  }
  const archives = new Map(values.filter(row => row.kind === 'archive').map(row => [row.value.id,row.value]));
  for (const row of values) if (row.kind === 'attachment') {
    const archive = archives.get(row.value.id);
    if (archive?.entries) row.value.archiveInfo = archiveProjection(archive);
    else if (row.value.archive) row.value.archiveInfo = archiveProjection(row.value.archive);
    else delete row.value.archiveInfo;
  }
  values.forEach((row,index) => { records[index].data = JSON.stringify(row.value); });
  if (!values.some(row => row.kind === 'settings' && row.value.id === 'settings')) fail();
}

export { credentialBindings as restoreCredentialReferences } from './credential-bindings.js';
