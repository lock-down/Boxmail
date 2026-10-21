import { ServiceError } from './validation.js';

const strings = (value, names) => names.every(name => typeof value[name] === 'string');
const bools = (value, names) => names.every(name => typeof value[name] === 'boolean');
const integers = (value, names) => names.every(name => Number.isSafeInteger(value[name]));
const stringArray = value => Array.isArray(value) && value.every(item => typeof item === 'string');
const object = value => value && typeof value === 'object' && !Array.isArray(value);
function mailShape(value) {
  if (!strings(value, ['id', 'accountId', 'folder', 'sender', 'senderEmail', 'to', 'cc', 'subject', 'body', 'preview', 'date', 'category'])
    || !bools(value, ['unread', 'starred']) || !stringArray(value.attachmentIds)) return false;
  const summary = value.summary;
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
    if (kind === 'message' && !mailShape(value)) fail();
    if (kind === 'draft' && (!strings(value, ['accountId', 'to', 'cc', 'bcc', 'subject', 'body', 'status', 'updatedAt'])
      || !stringArray(value.attachmentIds))) fail();
    if (['message', 'draft'].includes(kind) && (!accountIDs.has(value.accountId)
      || value.attachmentIds.some(id => !attachmentIDs.has(id)))) fail();
    if (kind === 'attachment' && (!strings(value, ['messageId', 'name', 'contentType', 'path', 'text', 'parseError', 'date'])
      || !integers(value, ['size']) || value.size < 0)) fail();
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
    }
  }
  if (!values.some(row => row.kind === 'settings' && row.value.id === 'settings')) fail();
}
