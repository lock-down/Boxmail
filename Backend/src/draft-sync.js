import { createHash, randomUUID } from 'node:crypto';
import { rm } from 'node:fs/promises';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { parseDocument } from 'htmlparser2';
import { prepareAttachment, attachmentBytes, removeUnusedAttachments } from './attachments.js';
import { draftRevision } from './draft-state.js';
import { draftContent, inlineForwardImages } from './forward-content.js';
import { richFromHTML } from './rich-text.js';
import { imapOperation, mailboxMetadata, messageSource } from './mail-sync.js';
import { ServiceError } from './validation.js';
import { mailBody } from './mail-body.js';

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
const escape = value => value.replace(/[&<>"']/g,
  character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);

function syncHTML(draft, content) {
  if (draft.forwardedHTML == null && draft.forwardedText == null) return content.html;
  const editable = draft.bodyHTML || `<div style="white-space:pre-wrap">${escape(draft.body)}</div>`;
  const forwarded = draft.forwardedHTML || `<div style="white-space:pre-wrap">${escape(draft.forwardedText || '')}</div>`;
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
  let progress = { id: progressID, accountId: account.id, folder: 'drafts', remotePath: path,
    status: 'running', phase: 'inventory', total: 0, downloaded: 0, remaining: 0, hasMore: false };
  const publish = changes => { progress = { ...progress, ...changes, updatedAt: new Date().toISOString() }; repo.put('sync', progress); };
  const perform = operation => imapOperation(client, operation, { signal, timeoutMs, phase: 'drafts' });
  let lock;
  publish({});
  try {
    lock = await perform(() => client.getMailboxLock(path));
    const { fetched, validity } = await mailboxMetadata(client, path, { signal, timeoutMs,
      onInventory: inventory => publish({ inventory }) });
    migrateCachedDrafts(repo, account, path);
    for (const draft of repo.activeDrafts(account.id)) {
      const binding = draft.remotePending || draft.remoteDraft;
      if (binding && binding.serverIdentity !== scope) repo.put('draft', { ...draft,
        remoteDraft: null, remotePending: null, syncState: 'conflict',
        syncError: '邮箱服务器配置已改变，本机草稿已保留。核对账户后可同步为新草稿。' });
    }
    for (const deletion of repo.list('draftDeletion', { accountId: account.id }))
      if (deletion.serverIdentity !== scope) repo.remove('draftDeletion', deletion.id);
    const knownUIDs = new Set(fetched.map(item => item.uid));
    const activeUIDs = new Set(fetched.filter(item => !item.flags.has('\\Deleted')).map(item => item.uid));
    const stable = async () => {
      const current = await perform(() => client.search({ all: true }, { uid: true }));
      if (String(client.mailbox?.uidValidity) !== validity || !Array.isArray(current)
        || current.length !== knownUIDs.size || current.some(uid => !knownUIDs.has(uid)))
        throw new ServiceError('服务器草稿在同步期间发生变化，已保留双方内容，请再次同步。', 409);
    };
    const deleteUID = async uid => {
      if (!client.capabilities?.has('UIDPLUS'))
        throw new ServiceError('服务器不支持安全的单封草稿清理（UIDPLUS），已保留旧副本，请在网页版清理。', 409);
      await stable();
      if (!await perform(() => client.messageDelete(uid, { uid: true })))
        throw new ServiceError('服务器未确认草稿清理，下次同步会重试。', 502);
      knownUIDs.delete(uid);
    };
    const pendingDeletes = repo.list('draftDeletion', { accountId: account.id }).filter(item => item.path === path);
    const matched = new Set();
    publish({ total: fetched.length, remaining: fetched.length, phase: 'download' });
    for (const remote of fetched.sort((a, b) => b.uid - a.uid)) {
      signal?.throwIfAborted();
      if (remote.flags.has('\\Deleted')) continue;
      const direct = repo.activeDrafts(account.id).find(draft => matches(draft.remoteDraft, path, validity, remote.uid));
      const deletion = repo.list('draftDeletion', { accountId: account.id }).find(item => matches(item, path, validity, remote.uid));
      if (deletion) {
        await deleteUID(remote.uid); repo.remove('draftDeletion', deletion.id);
      } else if (direct) {
        matched.add(direct.id);
      } else {
        if (remote.size > 25 * 1024 * 1024)
          throw new ServiceError('服务器草稿超过 25 MB，已保留本机版本，请在网页版处理。', 502);
        const source = await messageSource(client, remote, { signal, timeoutMs });
        if (!source) throw new ServiceError('服务器未完整返回草稿正文，未覆盖本机草稿。', 502);
        const mime = await contentWorker.run('mime', source);
        const { parsed, content } = mime, contentHash = mimeHash(mime);
        const removedDuringParse = repo.list('draftDeletion', { accountId: account.id })
          .find(item => matches(item, path, validity, remote.uid));
        if (removedDuringParse) {
          await deleteUID(remote.uid); repo.remove('draftDeletion', removedDuringParse.id); continue;
        }
        const token = parsed.draftToken;
        const deletionByToken = token && pendingDeletes.find(item => item.token === token);
        if (deletionByToken) {
          await deleteUID(remote.uid); repo.remove('draftDeletion', deletionByToken.id);
          continue;
        }
        const candidates = repo.activeDrafts(account.id);
        const pending = token && candidates.find(draft => draft.remotePending?.token === token);
        let existing = pending || candidates.find(draft => !matched.has(draft.id)
          && draft.remoteDraft?.path === path
          && (token && draft.remoteDraft.token === token
            || parsed.messageId && draft.remoteDraft.messageId === parsed.messageId)
          && !matches(draft.remoteDraft, path, validity, remote.uid)
          && (draft.remoteDraft.uidValidity !== validity || !activeUIDs.has(draft.remoteDraft.uid)));
        if (pending && pending.remotePending.contentHash === contentHash) {
          const intent = pending.remotePending;
          const binding = { path, uid: remote.uid, uidValidity: validity, messageId: parsed.messageId,
            token, contentHash, baseHash: intent.baseHash, serverIdentity: scope };
          repo.put('draft', { ...pending, remoteDraft: binding, remotePending: null, syncError: null,
            syncState: draftRevision(pending) === intent.baseHash ? 'synced' : 'pending' });
          if (matches(intent.previous, path, validity, intent.previous?.uid) && knownUIDs.has(intent.previous.uid)) {
            repo.put('draftDeletion', { ...intent.previous, id: randomUUID(), accountId: account.id });
          }
          matched.add(pending.id);
        } else if (existing && existing.remoteDraft?.contentHash === contentHash) {
          repo.put('draft', { ...existing, remoteDraft: { ...existing.remoteDraft, uid: remote.uid, uidValidity: validity },
            syncState: draftRevision(existing) === existing.remoteDraft.baseHash ? 'synced' : 'pending', syncError: null });
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
            const rich = importedBody(content);
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
                throw new ServiceError('草稿已在本机移除，未重新创建；下次同步将核对服务器副本。', 409);
              if (existing && existing.accountId !== account.id)
                throw new ServiceError('草稿的发件账户已改变，本机修改仍保留，请再次同步。', 409);
              if (existing && existing.status !== 'draft') throw new ServiceError('草稿正在发送，服务器版本将在下次同步读取。', 409);
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
      publish({ downloaded: progress.downloaded + 1, remaining: Math.max(0, progress.remaining - 1) });
    }
    // Reconcile only after a complete, stable inventory. A vanished remote draft
    // never silently erases unsent local work or gets resurrected automatically.
    await stable();
    for (const draft of repo.activeDrafts(account.id)) {
      if (draft.remoteDraft?.path !== path || matched.has(draft.id)) continue;
      repo.put('draft', { ...draft, remoteDraft: null, remotePending: null, syncState: 'conflict',
        syncError: '服务器草稿已删除或文件夹身份已变化，本机内容仍保留。确认后可同步为新草稿。' });
    }
    for (const deletion of repo.list('draftDeletion', { accountId: account.id }).filter(item => item.path === path)) {
      if (deletion.uidValidity === validity && knownUIDs.has(deletion.uid)) await deleteUID(deletion.uid);
      repo.remove('draftDeletion', deletion.id);
    }
    publish({ phase: 'upload' });
    for (const header of repo.activeDrafts(account.id)) {
      const draft = repo.get('draft', header.id);
      if (draft.status !== 'draft' || typeof draft.body !== 'string' || draft.syncState === 'conflict'
        || draft.remoteDraft && draftRevision(draft) === draft.remoteDraft.baseHash) continue;
      const files = [];
      let attachmentSize = 0;
      for (const id of draft.attachmentIds || []) {
        const { metadata, buffer } = await attachmentBytes(repo, id);
        attachmentSize += buffer.length;
        if (attachmentSize > 25 * 1024 * 1024)
          throw new ServiceError('草稿附件合计超过服务器草稿的 25 MB 上限，已保留本机版本。');
        files.push({ filename: metadata.name, contentType: metadata.contentType, content: buffer });
      }
      signal?.throwIfAborted();
      const content = draftContent(draft), token = randomUUID();
      const messageId = draft.remoteDraft?.messageId || `<${randomUUID()}@boxmail.draft>`;
      const composer = new MailComposer({ from: { name: account.name, address: account.email },
        to: draft.to || undefined, cc: draft.cc || undefined, bcc: draft.bcc || undefined, keepBcc: true,
        subject: draft.subject, text: content.text, html: inlineForwardImages(syncHTML(draft, content), files), attachments: files,
        inReplyTo: draft.inReplyTo || undefined, references: draft.references?.length ? draft.references : undefined,
        messageId, headers: { 'X-Boxmail-Draft-Token': token }, disableFileAccess: true, disableUrlAccess: true }).compile();
      composer.keepBcc = true;
      const raw = await composer.build();
      if (raw.length > 25 * 1024 * 1024)
        throw new ServiceError('草稿正文与附件编码后超过 25 MB，已保留本机版本，请缩小附件后同步。');
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
        await deleteUID(draft.remoteDraft.uid); repo.remove('draftDeletion', deletion.id);
      }
    }
    publish({ status: 'completed', phase: 'completed', remaining: 0, lastError: null });
  } catch (error) {
    publish({ status: signal?.aborted ? 'paused' : 'failed', lastError: error instanceof ServiceError
      ? error.message : '服务器草稿同步未完成，本机内容已保留，可再次同步。' });
    throw error;
  } finally { lock?.release(); }
}
