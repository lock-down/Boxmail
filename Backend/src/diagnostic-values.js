import { existsSync, readFileSync } from 'node:fs';
import { accountReference } from './diagnostics.js';

const packaged = new URL('../Resources/DiagnosticKnownFields.json', import.meta.url);
const source = new URL('../../Sources/BoxmailCore/Resources/DiagnosticKnownFields.json', import.meta.url);
const knownFields = new Set(JSON.parse(readFileSync(existsSync(packaged) ? packaged : source, 'utf8')));
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
