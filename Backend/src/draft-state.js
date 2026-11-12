import { createHash } from 'node:crypto';

export function draftRevision(draft) {
  return createHash('sha256').update(JSON.stringify(['accountId', 'to', 'cc', 'bcc', 'subject', 'body',
    'bodyHTML', 'richText', 'attachmentIds', 'inReplyTo', 'references', 'forwardedText', 'forwardedHTML']
    .map(key => draft[key] ?? null))).digest('hex');
}

export function presentDraft(draft) {
  const { remoteDraft, remotePending, ...publicDraft } = draft;
  return { ...publicDraft, revision: draftRevision(draft),
    syncState: draft.syncState || (draft.remoteDraft ? 'synced' : 'local') };
}
