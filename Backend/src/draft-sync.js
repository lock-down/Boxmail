import { createHash, randomUUID } from 'node:crypto';
import { rm } from 'node:fs/promises';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { parseDocument } from 'htmlparser2';
import { prepareAttachment, attachmentBytes, attachmentFiles, removeUnusedAttachments } from './attachments.js';
import { draftRevision } from './draft-state.js';
import { draftContent, inlineForwardImages } from './forward-content.js';
import { richFromHTML } from './rich-text.js';
import { imapOperation, mailboxMetadata, messageSource } from './mail-sync.js';
import { ServiceError } from './validation.js';
import { mailBody } from './mail-body.js';
import { escapeHTML } from './unicode.js';

const digest = value => createHash('sha256').update(value).digest('hex');
const serverIdentity = account => digest(JSON.stringify([account.imapHost?.toLowerCase(), account.imapPort,
  account.imapTLS, account.username, account.email?.toLowerCase()]));
function mimeHash({ parsed, content }) {
  const address = value => (value?.value || []).map(item => (item.address || '').toLowerCase()).sort();
  return digest(JSON.stringify([address(parsed.to), address(parsed.cc), address(parsed.bcc), parsed.subject || '',
    content.body.replace(/\r\n?/g, '\n').trimEnd(), content.html.trim(),
    (parsed.attachments || []).map(file => [file.filename || '', file.contentType, digest(file.content)])]));
}
const matches = (binding, path, validity, uid) => binding?.path === path
  && binding.uidValidity === validity && binding.uid === uid;
function syncHTML(draft, content) {
  if (draft.forwardedHTML == null && draft.forwardedText == null) return content.html;
  const editable = draft.bodyHTML || `<div style="white-space:pre-wrap">${escapeHTML(draft.body)}</div>`;
  const forwarded = draft.forwardedHTML || `<div style="white-space:pre-wrap">${escapeHTML(draft.forwardedText || '')}</div>`;
  return `<div class="boxmail-draft-editable">${editable}</div><div class="boxmail-draft-forwarded">${forwarded}</div>`;
}

function importedBody(content) {
  if (!content.html) return { body: content.body };
  const document = parseDocument(content.html, { withStartIndices: true, withEndIndices: true });
  const inner = name => {
    const node = document.children.find(node => node.name === 'div' && node.attribs?.class === name);
    if (!node) return null;
    const outer = content.html.slice(node.startIndex, node.endIndex + 1);
    return outer.slice(outer.indexOf('>') + 1, outer.lastIndexOf('</'));
  };
  const editable = inner('boxmail-draft-editable'), forwardedHTML = inner('boxmail-draft-forwarded');
  if (editable == null || forwardedHTML == null) return richFromHTML(content.html);
  const rich = richFromHTML(editable), plain = content.body.replace(/\r\n?/g, '\n');
  const prefix = rich.body + '\n\n';
  return { ...rich, forwardedHTML,
    forwardedText: plain.startsWith(prefix) ? plain.slice(prefix.length).replace(/\n$/, '') : mailBody({ html: forwardedHTML }).body };
}

function migrateCachedDrafts(repo, account, path) {
  for (const header of repo.syncMessageHeaders(account.id, path).filter(message => message.folder === 'drafts')) {
    const message = repo.get('message', header.id);
    let body;
    try { body = importedBody({ body: message.body || '', html: message.html || '' }); }
    catch { body = { body: message.body || '' }; }
    const draft = { id: `migrated-${digest(message.id)}`, accountId: account.id,
      to: message.to || '', cc: message.cc || '', bcc: message.bcc || '', subject: message.subject || '',
      ...body, attachmentIds: message.attachmentIds || [], inReplyTo: message.inReplyTo || '',
      references: message.references || [], status: 'draft', updatedAt: message.date || new Date().toISOString(),
      syncState: 'synced', remoteDraft: { path, uid: message.uid, uidValidity: String(message.uidValidity),
        messageId: message.messageId || '', baseHash: '', serverIdentity: serverIdentity(account) } };
    if (!Number.isSafeInteger(message.uid) || !/^\d+$/.test(String(message.uidValidity))) {
      draft.remoteDraft = null; draft.syncState = 'conflict';
      draft.syncError = '旧缓存缺少服务器草稿身份，已保留为本机副本，可确认后同步为新草稿。';
    } else draft.remoteDraft.baseHash = draftRevision(draft);
    repo.transaction(() => {
      if (!repo.get('draft', draft.id)) repo.put('draft', draft);
      repo.remove('message', message.id);
    });
  }
}

export function queueDraftDeletion(repo, draft) {
  for (const binding of [draft.remoteDraft, draft.remotePending]) {
    if (!binding) continue;
    repo.put('draftDeletion', { ...binding, id: randomUUID(), accountId: draft.accountId });
  }
}

// The caller owns the account lock, connection, cancellation and isolated parser.
// APPEND intent is durable before network I/O, so a lost acknowledgement is
// reconciled by a random MIME token rather than blindly appending another copy.
export async function syncRemoteDrafts(repo, account, client, { signal, timeoutMs = 45000, contentWorker } = {}) {
  const path = account.folders.drafts;
  const scope = serverIdentity(account);
  const progressID = digest(`${account.id}:${path}`);
  const previousFailures = repo.get('sync', progressID)?.readFailures;
  let readFailures;
  let progress = { id: progressID, accountId: account.id, folder: 'drafts', remotePath: path,
    status: 'running', phase: 'inventory', total: 0, downloaded: 0, remaining: 0, hasMore: false };
  const publish = changes => { progress = { ...progress, ...changes, ...(readFailures ? { readFailures: readFailures.snapshot() } : {}), updatedAt: new Date().toISOString() }; repo.put('sync', progress); };
  const perform = operation => imapOperation(client, operation, { signal, timeoutMs, phase: 'drafts' });
  let lock, index;
  const warnings = [];
  class DraftContentError extends ServiceError {}
  const contentOperation = async operation => {
    try { return await operation(); } catch (error) {
      if (signal?.aborted) throw error;
      throw new DraftContentError(error instanceof ServiceError ? error.message : '服务器草稿格式无法读取，请在网页版检查。');
    }
  };
  publish({});
  try {
    lock = await perform(() => client.getMailboxLock(path));
    const { fetched, validity } = await mailboxMetadata(client, path, { signal, timeoutMs,
      onInventory: inventory => publish({ inventory }) });
    readFailures = new DraftReadFailures(previousFailures, scope, validity, fetched);
    migrateCachedDrafts(repo, account, path);
    for (const draft of repo.activeDrafts(account.id)) {
      const binding = draft.remotePending || draft.remoteDraft;
      if (binding && binding.serverIdentity !== scope) repo.put('draft', { ...draft,
        remoteDraft: null, remotePending: null, syncState: 'conflict',
        syncError: '邮箱服务器配置已改变，本机草稿已保留。核对账户后可同步为新草稿。' });
    }
    for (const deletion of repo.list('draftDeletion', { accountId: account.id }))
      if (deletion.serverIdentity !== scope) repo.remove('draftDeletion', deletion.id);
    index = new DraftSyncIndex(repo, account.id);
    const knownUIDs = new Set(fetched.map(item => item.uid));
    const activeUIDs = new Set(fetched.filter(item => !item.flags.has('\\Deleted')).map(item => item.uid));
    const stable = async () => {
      const status = await perform(() => client.status(path, { uidValidity: true }));
      if (String(client.mailbox?.uidValidity) !== validity || String(status?.uidValidity) !== validity)
        throw new ServiceError('服务器草稿文件夹身份已变化，已保留双方内容，请再次同步。', 409);
    };
    const unconfirmedDeletes = new Set();
    const deleteUID = async uid => {
      if (unconfirmedDeletes.has(uid)) return false;
      if (!client.capabilities?.has('UIDPLUS'))
        throw new ServiceError('服务器不支持安全的单封草稿清理（UIDPLUS），已保留旧副本，请在网页版清理。', 409);
      await stable();
      if (!await perform(() => client.messageDelete(uid, { uid: true }))) {
        const remaining = await perform(() => client.fetchOne(uid, { uid: true }, { uid: true }));
        await stable();
        if (remaining !== false) {
          unconfirmedDeletes.add(uid);
          warnings.push('服务器未确认一封草稿的清理，删除意图已保留，下次同步重试。');
          return false;
        }
      }
      knownUIDs.delete(uid);
      readFailures.remove(uid);
      return true;
    };
    const matched = new Set(), unreadable = [];
    publish({ total: fetched.length, remaining: fetched.length, phase: 'download' });
    for (const remote of fetched.sort((a, b) => b.uid - a.uid)) {
      signal?.throwIfAborted();
      if (remote.flags.has('\\Deleted')) continue;
      let identity;
      try {
        const direct = index.direct(path, validity, remote.uid);
        const deletion = index.deletion(path, validity, remote.uid);
        if (deletion) {
          if (await deleteUID(remote.uid)) repo.remove('draftDeletion', deletion.id);
        } else if (direct) {
          matched.add(direct.id);
        } else {
          const cached = readFailures.cached(remote);
          if (cached) throw Object.assign(new DraftContentError(cached.error), { cachedFailure: cached });
          if (remote.size > 25 * 1024 * 1024)
            throw new DraftContentError('服务器草稿超过 25 MB，已保留本机版本，请在网页版处理。', 502);
          const source = await messageSource(client, remote, { signal, timeoutMs });
          if (!source) throw new DraftContentError('服务器暂未完整返回草稿正文，本机草稿已保留，稍后会再次核对。');
          const mime = await contentOperation(() => contentWorker.run('mime', source));
          const { parsed, content } = mime, contentHash = mimeHash(mime);
          identity = { token: parsed.draftToken, messageId: parsed.messageId };
          const removedDuringParse = index.deletion(path, validity, remote.uid);
          if (removedDuringParse) {
            if (await deleteUID(remote.uid)) repo.remove('draftDeletion', removedDuringParse.id);
            continue;
          }
          const token = parsed.draftToken;
          const deletionByToken = index.deletion(path, validity, remote.uid, token, parsed.messageId);
          if (deletionByToken) {
            if (await deleteUID(remote.uid)) repo.remove('draftDeletion', deletionByToken.id);
            continue;
          }
          const candidates = index.candidates(token, parsed.messageId);
          const pending = token && candidates.find(draft => draft.remotePending?.token === token);
          let existing = pending || candidates.find(draft => !matched.has(draft.id)
            && draft.remoteDraft?.path === path
            && (token && draft.remoteDraft.token === token
              || parsed.messageId && draft.remoteDraft.messageId === parsed.messageId)
            && !matches(draft.remoteDraft, path, validity, remote.uid)
            && (draft.remoteDraft.uidValidity !== validity || !activeUIDs.has(draft.remoteDraft.uid)));
          if (existing) existing = repo.get('draft', existing.id);
          const currentPending = pending && repo.get('draft', pending.id);
          if (currentPending && currentPending.remotePending?.contentHash === contentHash) {
            const intent = currentPending.remotePending;
            const binding = { path, uid: remote.uid, uidValidity: validity, messageId: parsed.messageId,
              token, contentHash, baseHash: intent.baseHash, serverIdentity: scope };
            repo.put('draft', { ...currentPending, remoteDraft: binding, remotePending: null, syncError: null,
              syncState: draftRevision(currentPending) === intent.baseHash ? 'synced' : 'pending' });
            if (matches(intent.previous, path, validity, intent.previous?.uid) && knownUIDs.has(intent.previous.uid)) {
              repo.put('draftDeletion', { ...intent.previous, id: randomUUID(), accountId: account.id });
            }
            matched.add(pending.id);
          } else if (existing && existing.remoteDraft?.contentHash === contentHash) {
            repo.put('draft', { ...existing, remoteDraft: { ...existing.remoteDraft, uid: remote.uid, uidValidity: validity },
              syncState: draftRevision(existing) === existing.remoteDraft.baseHash ? 'synced' : 'pending', syncError: null, remoteReadBlocked: false });
            matched.add(existing.id);
          } else {
            // Prepare files first; compare again after every await before deciding
            // whether a concurrent local edit needs its own conflict copy.
            const expectedID = existing?.id;
            const id = expectedID || randomUUID(), prepared = [];
            let committed = false;
            try {
              for (const file of parsed.attachments || []) prepared.push(await prepareAttachment(repo, id,
                file.filename || '附件', file.content, file.contentType, { signal, contentWorker }));
              const rich = await contentOperation(() => importedBody(content));
              const imported = { id, accountId: account.id, to: parsed.to?.text || '', cc: parsed.cc?.text || '',
                bcc: parsed.bcc?.text || '', subject: parsed.subject || '', ...rich,
                attachmentIds: prepared.map(file => file.id), inReplyTo: parsed.inReplyTo || '',
                references: typeof parsed.references === 'string' ? [parsed.references] : parsed.references || [],
                status: 'draft', updatedAt: new Date().toISOString(), syncState: 'synced',
                remoteDraft: { path, uid: remote.uid, uidValidity: validity, messageId: parsed.messageId || '', token,
                  contentHash, baseHash: '', serverIdentity: scope } };
              imported.remoteDraft.baseHash = draftRevision(imported);
              let oldFiles = [];
              repo.transaction(() => {
                existing = existing && repo.get('draft', existing.id);
                if (expectedID && !existing)
                  throw new DraftContentError('草稿已在本机移除，未重新创建；下次同步将核对服务器副本。', 409);
                if (existing && existing.accountId !== account.id)
                  throw new DraftContentError('草稿的发件账户已改变，本机修改仍保留，请再次同步。', 409);
                if (existing && existing.status !== 'draft') throw new DraftContentError('草稿正在发送，服务器版本将在下次同步读取。', 409);
                if (existing && draftRevision(existing) !== (existing.remoteDraft?.baseHash || existing.remotePending?.baseHash)) {
                  const copy = { ...existing, id: randomUUID(), remoteDraft: null, remotePending: null,
                    conflictOf: id, syncState: 'conflict', updatedAt: new Date().toISOString(),
                    syncError: '本机与服务器均有修改，已分别保留。本份为本机副本，可继续编辑或同步为新草稿。' };
                  repo.put('draft', copy);
                  imported.syncError = '发现同时编辑，服务器版本与本机冲突副本已分别保留。';
                } else oldFiles = existing?.attachmentIds || [];
                for (const file of prepared) repo.put('attachment', file);
                repo.put('draft', imported);
              });
              committed = true;
              if (oldFiles.length) await removeUnusedAttachments(repo, oldFiles);
              matched.add(id);
            } finally {
              if (!committed) await Promise.allSettled(prepared.map(file => rm(file.path, { force: true })));
            }
          }
        }
        readFailures.remove(remote.uid);
      } catch (error) {
        if (!(error instanceof DraftContentError)) throw error;
        unreadable.push(error.cachedFailure || readFailures.record(remote, error.message, identity));
        warnings.push(`服务器草稿 UID ${remote.uid}：${error.message}`);
      }
      publish({ downloaded: progress.downloaded + 1, remaining: Math.max(0, progress.remaining - 1) });
    }
    // Reconcile only after a complete, stable inventory. A vanished remote draft
    // never silently erases unsent local work or gets resurrected automatically.
    await stable();
    for (const draft of repo.activeDrafts(account.id)) {
      if (draft.remoteDraft?.path !== path || matched.has(draft.id)) continue;
      const uncertain = unreadable.some(item => !item.token && !item.messageId
        || item.token && item.token === draft.remoteDraft.token
        || item.messageId && item.messageId === draft.remoteDraft.messageId);
      if (uncertain) {
        repo.put('draft', { ...draft, syncState: 'conflict', remoteReadBlocked: true,
          syncError: '服务器草稿暂时无法读取，本机内容及服务器绑定已保留，待服务器版本可读取后继续核对。' });
        continue;
      }
      repo.put('draft', { ...draft, remoteDraft: null, remotePending: null, syncState: 'conflict',
        syncError: '服务器草稿已删除或文件夹身份已变化，本机内容仍保留。确认后可同步为新草稿。' });
    }
    let manualDeletions = 0;
    for (const deletion of repo.list('draftDeletion', { accountId: account.id }).filter(item => item.path === path)) {
      if (deletion.uidValidity === validity) {
        if (!knownUIDs.has(deletion.uid) || await deleteUID(deletion.uid)) repo.remove('draftDeletion', deletion.id);
      } else {
        const pending = unresolvedDeletion(repo, deletion);
        if (pending.reviewRequired) manualDeletions++;
        else warnings.push('部分已删除草稿的服务器身份已变化，删除意图已保留，将在下次同步继续核对。');
      }
    }
    if (manualDeletions) warnings.push(`${manualDeletions} 份草稿删除意图连续三轮无法核对，已转为人工处理，请在网页版确认；记录仍保留在备份中。`);
    publish({ phase: 'upload' });
    for (const header of repo.draftSyncHeaders(account.id)) {
      const draft = repo.get('draft', header.id);
      if (!draft || draft.accountId !== account.id || draft.status !== 'draft' || typeof draft.body !== 'string' || draft.syncState === 'conflict') continue;
      if (draft.remoteDraft && draftRevision(draft) === draft.remoteDraft.baseHash) {
        if (draft.syncState !== 'synced' || draft.syncError) repo.put('draft', { ...draft, syncState: 'synced', syncError: null });
        continue;
      }
      try {
        const files = await attachmentFiles(repo, draft.attachmentIds, {
          operation: contentOperation, maxTotalBytes: 25 * 1024 * 1024,
          tooLarge: () => new DraftContentError('草稿附件合计超过服务器草稿的 25 MB 上限，已保留本机版本。'),
        });
        signal?.throwIfAborted();
        const content = draftContent(draft), token = randomUUID();
        const messageId = draft.remoteDraft?.messageId || `<${randomUUID()}@boxmail.draft>`;
        const composer = new MailComposer({ from: { name: account.name, address: account.email },
          to: draft.to || undefined, cc: draft.cc || undefined, bcc: draft.bcc || undefined,
          subject: draft.subject, text: content.text, html: inlineForwardImages(syncHTML(draft, content), files), attachments: files,
          inReplyTo: draft.inReplyTo || undefined, references: draft.references?.length ? draft.references : undefined,
          messageId, headers: { 'X-Boxmail-Draft-Token': token }, disableFileAccess: true, disableUrlAccess: true }).compile();
        composer.keepBcc = true;
        const raw = await composer.build();
        if (raw.length > 25 * 1024 * 1024)
          throw new DraftContentError('草稿正文与附件编码后超过 25 MB，已保留本机版本，请缩小附件后同步。');
        const contentHash = mimeHash(await contentWorker.run('mime', raw));
        const intent = { path, token, messageId, contentHash, baseHash: draftRevision(draft),
          previous: draft.remoteDraft || null, serverIdentity: scope };
        await stable();
        const latest = repo.get('draft', draft.id);
        if (!latest || latest.status !== 'draft' || latest.accountId !== account.id) continue;
        repo.put('draft', { ...latest, remotePending: intent, syncState: 'pending' });
        const appended = await perform(() => client.append(path, raw, ['\\Draft', '\\Seen']));
        if (!appended?.uid || String(appended.uidValidity) !== validity)
          throw new ServiceError('服务器尚未确认草稿编号，本机内容与同步意图已保存，请再次同步核对。', 502);
        knownUIDs.add(appended.uid);
        const current = repo.get('draft', draft.id);
        const binding = { path, token, messageId, contentHash, baseHash: intent.baseHash, uid: appended.uid,
          uidValidity: validity, serverIdentity: scope };
        if (current && current.status === 'draft' && current.accountId === account.id) repo.put('draft', { ...current, remoteDraft: binding,
          remotePending: null, syncError: null, syncState: draftRevision(current) === intent.baseHash ? 'synced' : 'pending' });
        else repo.put('draftDeletion', { ...binding, id: randomUUID(), accountId: account.id });
        if (draft.remoteDraft?.uidValidity === validity && knownUIDs.has(draft.remoteDraft.uid)) {
          const deletion = { ...draft.remoteDraft, id: randomUUID(), accountId: account.id };
          repo.put('draftDeletion', deletion);
          if (await deleteUID(draft.remoteDraft.uid)) repo.remove('draftDeletion', deletion.id);
        }
      } catch (error) {
        if (!(error instanceof DraftContentError)) throw error;
        const current = repo.get('draft', draft.id);
        if (current?.accountId === account.id && current.status === 'draft')
          repo.put('draft', { ...current, syncState: 'pending', syncError: error.message });
        warnings.push(error.message);
      }
    }
    publish({ status: 'completed', phase: 'completed', remaining: 0, lastError: warnings.length ? [...new Set(warnings)].join('\n') : null });
  } catch (error) {
    publish({ status: signal?.aborted ? 'paused' : 'failed', lastError: error instanceof ServiceError
      ? error.message : '服务器草稿同步未完成，本机内容已保留，可再次同步。' });
    throw error;
  } finally { index?.close(); lock?.release(); }
}

const key = binding => binding && JSON.stringify([binding.path, binding.uidValidity, binding.uid]);
class Lookup {
  values = new Map();
  add(key, id) { if (!key) return; if (!this.values.has(key)) this.values.set(key, new Set()); this.values.get(key).add(id); }
  remove(key, id) { const ids = this.values.get(key); ids?.delete(id); if (!ids?.size) this.values.delete(key); }
  ids(key) { return this.values.get(key) || []; }
}
// Track concurrent saves/deletes without reparsing all bodies after every await.
export class DraftSyncIndex {
  drafts = new Map(); deletions = new Map();
  uid = new Lookup(); token = new Lookup(); message = new Lookup(); pending = new Lookup();
  deletedUID = new Lookup(); deletedToken = new Lookup(); deletedMessage = new Lookup();
  constructor(repo, accountId) {
    this.repo = repo; this.accountId = accountId;
    this.reset();
    this.listener = change => change ? this.update(change.kind, change.id, change.value) : this.reset();
    repo.recordObservers.add(this.listener);
  }
  reset() {
    for (const id of this.drafts.keys()) this.update('draft', id, null);
    for (const id of this.deletions.keys()) this.update('draftDeletion', id, null);
    for (const draft of this.repo.draftSyncHeaders(this.accountId)) this.update('draft', draft.id, draft);
    for (const deletion of this.repo.list('draftDeletion', { accountId: this.accountId })) this.update('draftDeletion', deletion.id, deletion);
  }
  update(kind, id, value) {
    if (!['draft', 'draftDeletion'].includes(kind)) return;
    const draft = kind === 'draft', records = draft ? this.drafts : this.deletions;
    const indexes = draft ? [this.uid, this.token, this.message, this.pending] : [this.deletedUID, this.deletedToken, this.deletedMessage];
    const keys = record => { const binding = draft ? record.remoteDraft : record;
      return [key(binding), binding?.token, binding?.messageId, record.remotePending?.token]; };
    const old = records.get(id);
    if (old) keys(old).forEach((key, i) => indexes[i]?.remove(key, id));
    records.delete(id);
    if (!value || value.accountId !== this.accountId || draft && value.status === 'sent') return;
    // No body/rich-text copies are retained by the index.
    const header = draft ? { id, accountId: value.accountId, remoteDraft: value.remoteDraft, remotePending: value.remotePending, status: value.status } : value;
    records.set(id, header);
    keys(header).forEach((key, i) => indexes[i]?.add(key, id));
  }
  direct(path, validity, uid) { return this.drafts.get([...this.uid.ids(key({path,uidValidity:validity,uid}))][0]); }
  deletion(path, validity, uid, token, messageId) {
    const ids = new Set([...this.deletedUID.ids(key({path,uidValidity:validity,uid})), ...this.deletedToken.ids(token), ...this.deletedMessage.ids(messageId)]);
    return [...ids].map(id => this.deletions.get(id)).find(item => item.path === path);
  }
  candidates(token, messageId) { return [...new Set([...this.pending.ids(token), ...this.token.ids(token), ...this.message.ids(messageId)])].map(id => this.drafts.get(id)); }
  close() { this.repo.recordObservers.delete(this.listener); }
}

export const DRAFT_READ_RETRY_MS = 60000;
const MAX_READ_FAILURES = 100;
const MAX_DELETION_CHECKS = 3;

// IMAP content is immutable for a UID. Cache content failures briefly, bounded
// by this mailbox identity, so a bad replacement doesn't get parsed every poll.
export class DraftReadFailures {
  constructor(saved, serverIdentity, validity, fetched) {
    this.serverIdentity = serverIdentity;
    this.validity = validity;
    const sizes = new Map(fetched.map(remote => [remote.uid, remote.size]));
    const items = saved?.serverIdentity === serverIdentity && saved?.validity === validity && Array.isArray(saved.items)
      ? saved.items.slice(0, MAX_READ_FAILURES) : [];
    this.items = new Map(items.filter(item => sizes.get(item.uid) === item.size
      && typeof item.error === 'string' && item.error.length <= 2000 && Number.isFinite(item.retryAfter))
      .map(item => [item.uid, item]));
  }
  cached(remote) {
    const item = this.items.get(remote.uid);
    return item?.size === remote.size && item.retryAfter > Date.now() ? item : null;
  }
  record(remote, error, identity = {}) {
    const item = { uid: remote.uid, size: remote.size, error: error.slice(0, 2000),
      retryAfter: Date.now() + DRAFT_READ_RETRY_MS, ...identity };
    if (!this.items.has(remote.uid) && this.items.size >= MAX_READ_FAILURES) this.items.delete(this.items.keys().next().value);
    this.items.set(remote.uid, item);
    return item;
  }
  remove(uid) { this.items.delete(uid); }
  snapshot() { return { serverIdentity: this.serverIdentity, validity: this.validity, items: [...this.items.values()] }; }
}

export function unresolvedDeletion(repo, deletion) {
  if (deletion.reviewRequired) return deletion;
  const checks = Math.min(MAX_DELETION_CHECKS, (deletion.verificationAttempts || 0) + 1);
  return repo.put('draftDeletion', { ...deletion, verificationAttempts: checks,
    reviewRequired: checks === MAX_DELETION_CHECKS });
}
