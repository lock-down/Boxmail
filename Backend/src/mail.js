import { ImapFlow } from 'imapflow';
import nodemailer from 'nodemailer';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { simpleParser } from 'mailparser';
import { createHash, randomUUID } from 'node:crypto';
import { saveAttachment, attachmentBytes, copyBorrowedAttachments, reassignAttachments } from './attachments.js';
import { ServiceError, required, recipients } from './validation.js';
import { mailServiceError } from './mail-errors.js';
import { mailBody, MAIL_BODY_VERSION } from './mail-body.js';
import { applyMailMutations, archiveRestoreFolder, discoverMailFolders, folderForPath, mailFolderNames, trashRestoreFolder } from './mail-folders.js';
import { clearTrash } from './mail-trash.js';
import { imapOperation, mailboxMetadata, messageSource } from './mail-sync.js';

// Status changes re-read the stored draft, so a slow send never writes back the snapshot it
// started with and clobbers fields saved in the meantime.
function updateDraft(repo, draft, changes) {
  repo.put('draft', { ...(repo.get('draft', draft.id) || draft), ...changes });
}

function remapAttachmentJobs(repo, messageId, previousIds, attachmentIds) {
  const changed = new Map(previousIds.map((id, index) => [id, attachmentIds[index]])
    .filter(([before, after]) => before !== after));
  if (!changed.size) return;
  for (const job of repo.list('job', { messageId })) {
    if (!changed.has(job.attachmentId) && !job.attachmentItems?.some(item => changed.has(item.id))) continue;
    repo.put('job', { ...job,
      ...(job.attachmentId ? { attachmentId: changed.get(job.attachmentId) || job.attachmentId } : {}),
      ...(job.attachmentItems ? { attachmentItems: job.attachmentItems.map(item =>
        ({ ...item, id: changed.get(item.id) || item.id })) } : {}),
    });
  }
}

function clientFor(account, password) {
  const client = new ImapFlow({
    host: account.imapHost,
    port: account.imapPort,
    secure: account.imapTLS,
    doSTARTTLS: account.imapTLS ? undefined : true,
    tls: { rejectUnauthorized: true },
    auth: {
      user: account.username,
      pass: required(password, '邮箱授权码', 4000),
    },
    logger: false,
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 60000,
  });
  client.on('error', () => {});
  return client;
}
function transportFor(account, password) {
  return nodemailer.createTransport({
    host: account.smtpHost,
    port: account.smtpPort,
    secure: account.smtpTLS,
    requireTLS: !account.smtpTLS,
    tls: { rejectUnauthorized: true },
    auth: {
      user: account.username,
      pass: required(password, '邮箱授权码', 4000),
    },
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 30000,
    disableFileAccess: true,
    disableUrlAccess: true,
  });
}
export async function testAccount(account, password, { clientFactory = clientFor, transportFactory = transportFor } = {}) {
  const results = await Promise.allSettled([
    (async () => {
      let client;
      try {
        client = clientFactory(account, password);
        await client.connect();
      } catch (error) { throw mailServiceError(error, 'IMAP', account); }
      finally { if (client) await client.logout().catch(() => client.close()); }
    })(),
    (async () => {
      let transport;
      try {
        transport = transportFactory(account, password);
        await transport.verify();
      } catch (error) { throw mailServiceError(error, 'SMTP', account); }
      finally { transport?.close(); }
    })(),
  ]);
  if (results.some(result => result.status === 'rejected')) {
    throw new ServiceError(results.map((result, index) => result.status === 'fulfilled'
      ? `${index === 0 ? 'IMAP' : 'SMTP'} 连接成功。`
      : result.reason.message).join('\n'), 502);
  }
  return { ok: true };
}
export async function syncAccount(
  repo,
  account,
  password,
  { clientFactory = clientFor, batchSize = 200, folder: requestedFolder, signal,
    downloadBudgetMs = 20000, operationTimeoutMs = 45000 } = {},
) {
  let client = clientFactory(account, password);
  const operationOptions = { signal, timeoutMs: operationTimeoutMs };
  const perform = operation => imapOperation(client, operation, operationOptions);
  let count = 0;
  let repaired = 0;
  let skipped = 0;
  let currentSync;
  const failures = [];
  const names = { inbox: '收件箱', sent: '已发送', drafts: '草稿箱', archive: '已归档', trash: '已删除', spam: '垃圾邮件' };
  const abort = () => client?.close();
  signal?.addEventListener('abort', abort, { once: true });
  try {
    signal?.throwIfAborted();
    try { await perform(() => client.connect()); }
    catch (error) { throw mailServiceError(error, 'IMAP', account); }
    const folders = await perform(() => client.list());
    discoverMailFolders(account, folders);
    await applyMailMutations(repo, account, client);
    if (requestedFolder && !account.folders[requestedFolder])
      throw new ServiceError(`服务器未提供${names[requestedFolder] || '该'}文件夹，请检查网页版邮箱及收取范围。`, 502);
    for (const folder of Object.keys(names).filter(f => account.folders[f] && (!requestedFolder || requestedFolder === f))) {
      const remotePath = account.folders[folder];
      signal?.throwIfAborted();
      const syncId = createHash('sha256').update(`${account.id}:${remotePath}`).digest('hex');
      const previous = repo.get('sync', syncId);
      currentSync = { ...previous, id: syncId, accountId: account.id, folder, remotePath,
        status: 'running', lastError: null, inventory: {}, updatedAt: new Date().toISOString() };
      repo.put('sync', currentSync);
      let lock;
      try {
        // A failed SELECT or download may leave the connection unusable. The next
        // folder gets a fresh session instead of inheriting that failure.
        if (!client) {
          client = clientFactory(account, password);
          await perform(() => client.connect());
        }
        lock = await perform(() => client.getMailboxLock(remotePath, { readOnly: true }));
        const { fetched, validity } = await mailboxMetadata(client, remotePath, {
          ...operationOptions,
          onInventory: snapshot => {
            currentSync = { ...currentSync, inventory: { ...currentSync.inventory, ...snapshot } };
            repo.put('sync', currentSync);
          },
        });
        const seen = new Set(fetched.map(m => m.uid));
        const stored = repo.syncMessageHeaders(account.id, remotePath);
        const cached = new Map(stored.filter(m => m.uidValidity === validity).map(m => [m.uid, m]));
        repo.transaction(() => {
          for (const old of stored) if (old.uidValidity !== validity) {
            repo.put('recovery', { id: old.id, accountId: account.id, remotePath, original: repo.get('message', old.id) });
            repo.remove('message', old.id);
          }
          for (const [uid, old] of cached) if (!seen.has(uid)) {
            repo.put('recovery', { id: old.id, accountId: account.id, remotePath, original: repo.get('message', old.id) });
            repo.remove('message', old.id); cached.delete(uid);
          }
          for (const remote of fetched) {
            const old = cached.get(remote.uid);
            if (!old) continue;
            const unreadPending = repo.get('mutation', `${old.id}:unread`);
            const starPending = repo.get('mutation', `${old.id}:starred`);
            const unread = unreadPending ? !unreadPending.value : !remote.flags.has('\\Seen');
            const starred = starPending ? starPending.value : remote.flags.has('\\Flagged');
            if (old.unread === unread && old.starred === starred) continue;
            repo.put('message', { ...repo.get('message', old.id), unread, starred });
            cached.set(remote.uid, { ...old, unread, starred });
          }
        });
        // Legacy forwards may already be fully cached; repair ownership without downloading again.
        for (const [uid, old] of cached) {
          signal?.throwIfAborted();
          const shared = (old.attachmentIds || []).some(id => {
            const attachment = repo.get('attachment', id);
            return attachment && attachment.messageId !== old.id;
          });
          if (!shared) continue;
          const updated = await copyBorrowedAttachments(repo, old.attachmentIds, old.id, {
            preserveMissing: true,
            save: attachmentIds => {
              const latest = repo.get('message', old.id);
              if (!latest) throw new ServiceError('邮件不存在', 404);
              remapAttachmentJobs(repo, old.id, old.attachmentIds, attachmentIds);
              return repo.put('message', { ...latest, attachmentIds });
            },
          });
          cached.set(uid, updated);
        }
        const missing = fetched.filter(remote => !cached.has(remote.uid)
          || cached.get(remote.uid).bodyVersion !== MAIL_BODY_VERSION
          || cached.get(remote.uid).headersVersion !== 1).sort((a,b) => b.uid-a.uid);
        let beforeUID = Infinity, highestUID = -Infinity;
        for (const uid of cached.keys()) {
          beforeUID = Math.min(beforeUID, uid);
          highestUID = Math.max(highestUID, uid);
        }
        currentSync = { ...currentSync, uidValidity: validity, total: fetched.length,
          downloaded: cached.size, remaining: missing.length, hasMore: missing.length > 0,
          beforeUID: Number.isFinite(beforeUID) ? beforeUID : undefined,
          highestUID: Number.isFinite(highestUID) ? highestUID : undefined };
        repo.put('sync', currentSync);
        const downloadStarted = performance.now();
        let processed = 0;
        for (const remote of missing.slice(0, Math.min(200, Math.max(1, batchSize)))) {
          signal?.throwIfAborted();
          if (processed && performance.now() - downloadStarted >= downloadBudgetMs) break;
          processed++;
          const id = createHash('sha256').update(`${account.id}:${remotePath}:${validity}:${remote.uid}`).digest('hex');
          const old = repo.get('message', id);
          let parsed;
          if (remote.size <= 25 * 1024 * 1024) {
            const source = await messageSource(client, remote, operationOptions);
            if (!source) {
              // A message can disappear between listing and downloading. Retry on the next pass.
              skipped++; continue;
            }
            parsed = await simpleParser(source, { skipHtmlToText: true, skipTextToHtml: true });
          } else {
            skipped++;
            parsed = { ...remote.envelope, text: '该邮件超过 25 MB，暂未下载正文，请在邮箱服务商查看原邮件。',
              from: { value: remote.envelope?.from || [] },
              to: { text: (remote.envelope?.to || []).map(x => x.address).join(', ') },
              cc: { text: (remote.envelope?.cc || []).map(x => x.address).join(', ') }, attachments: [] };
          }
          const from = parsed.from?.value[0];
          const content = mailBody(parsed);
          const headers = { headersVersion: 1, replyTo: parsed.replyTo?.text || '',
            inReplyTo: parsed.inReplyTo || '',
            references: typeof parsed.references === 'string' ? [parsed.references] : parsed.references || [] };
          if (old) {
            repo.put('message', { ...repo.get('message', id), ...content, ...headers });
            repaired++;
          } else {
            const message = {
              id, accountId: account.id, folder, remotePath, uid: remote.uid, uidValidity: validity,
              messageId: parsed.messageId || '', sender: from?.name || from?.address || '未知发件人',
              senderEmail: from?.address || '', to: parsed.to?.text || account.email, cc: parsed.cc?.text || '',
              subject: parsed.subject || '(无主题)', ...content, ...headers,
              date: (parsed.date || remote.internalDate || new Date()).toISOString(),
              unread: !remote.flags.has('\\Seen'), starred: remote.flags.has('\\Flagged'),
              category: '未分类', summary: null, attachmentIds: [], oversized: remote.size > 25 * 1024 * 1024,
            };
            const relocations = repo.list('relocation', { accountId: account.id })
              .filter(r => r.destination === remotePath);
            const legacyRelocations = relocations.filter(r => (!r.destinationUID || r.uidValidity !== validity)
              && parsed.messageId && r.original.messageId === parsed.messageId);
            const relocation = relocations.find(r => r.destinationUID === remote.uid && r.uidValidity === validity)
              || (legacyRelocations.length === 1 ? legacyRelocations[0] : null);
            const recoveries = parsed.messageId ? repo.list('recovery', { accountId: account.id })
              .filter(r => r.original.messageId === parsed.messageId) : [];
            const sameFolder = recoveries.filter(r => r.remotePath === remotePath);
            const localSent = folder === 'sent' && parsed.messageId
              ? repo.localSentMessage(account.id, parsed.messageId) : null;
            const retained = relocation || (sameFolder.length === 1 ? sameFolder[0]
              : recoveries.length === 1 ? recoveries[0] : null)
              || (localSent ? { id: localSent.id, original: localSent } : null);
            if (retained) {
              message.summary = retained.original.summary;
              message.summaryHidden = retained.original.summaryHidden;
              message.translation = retained.original.translation;
              message.translationHTML = retained.original.translationHTML;
              message.category = retained.original.category;
              // Older forwarded copies may still share ids with their source mail.
              message.attachmentIds = await copyBorrowedAttachments(
                repo, retained.original.attachmentIds || [], retained.original.id, {
                  preserveMissing: true,
                  save: attachmentIds => {
                    remapAttachmentJobs(repo, retained.original.id, retained.original.attachmentIds || [], attachmentIds);
                    return attachmentIds;
                  },
                });
              if (folder === 'trash') {
                message.deletedFromFolder = retained.original.deletedFromFolder;
                message.deletedFromPath = retained.original.deletedFromPath;
              }
              if (folder === 'archive' || folder === 'trash') {
                message.archivedFromFolder = retained.original.archivedFromFolder;
                message.archivedFromPath = retained.original.archivedFromPath;
              }
              reassignAttachments(repo, message.attachmentIds, id, retained.original.id);
              for (const draft of repo.list('draft').filter(d => d.sourceMessageId === retained.original.id))
                repo.put('draft', { ...draft, sourceMessageId: id });
              for (const job of repo.list('job', { messageId: retained.original.id }))
                repo.put('job', { ...job, messageId: id });
              repo.remove(relocation ? 'relocation' : retained.id === localSent?.id ? 'message' : 'recovery', retained.id);
            } else {
              for (const a of parsed.attachments || []) {
                const saved = await saveAttachment(repo, id, a.filename || '附件', a.content, a.contentType);
                message.attachmentIds.push(saved.id);
              }
            }
            if (localSent) repo.remove('message', localSent.id);
            repo.put('message', message);
            if (localSent && localSent.folder !== folder)
              updateMessage(repo, id, { folder: localSent.folder });
            count++;
          }
          cached.set(remote.uid, repo.get('message', id));
          beforeUID = Math.min(beforeUID, remote.uid);
          highestUID = Math.max(highestUID, remote.uid);
          currentSync = { ...currentSync, downloaded: cached.size,
            remaining: Math.max(0, currentSync.remaining - 1),
            beforeUID, highestUID,
            updatedAt: new Date().toISOString() };
          currentSync.hasMore = currentSync.remaining > 0;
          repo.put('sync', currentSync);
        }
        currentSync = { ...currentSync, status: currentSync.hasMore ? 'partial' : 'completed',
          updatedAt: new Date().toISOString() };
        repo.put('sync', currentSync);
      } catch (error) {
        if (signal?.aborted) throw error;
        const safe = mailServiceError(error, 'IMAP', account);
        currentSync = { ...currentSync, status: 'failed', lastError: safe.message,
          updatedAt: new Date().toISOString() };
        repo.put('sync', currentSync);
        failures.push(`${names[folder]}：${safe.message}`);
        client?.close?.();
        client = null;
      } finally { lock?.release(); }
    }
    // The account may have been edited while the sync ran: merge this sync's folder discoveries
    // and lastSync into the latest record instead of writing back the pre-sync snapshot.
    const latest = repo.get('account', account.id) || account;
    repo.put('account', {
      ...latest,
      folders: account.folders ?? latest.folders,
      lastSync: new Date().toISOString(),
    });
    repo.event(
      'sync',
      `${account.email}：新增 ${count} 封，补齐 ${repaired} 封正文，跳过 ${skipped} 个邮件${failures.length ? `，${failures.length} 个文件夹未完成` : ''}`,
    );
    if (failures.length) throw new ServiceError(failures.join('\n'), 502);
    return { count, repaired, skipped, ok: true };
  } catch (error) {
    if (currentSync?.status === 'running') repo.put('sync', { ...currentSync,
      status: signal?.aborted ? 'paused' : 'failed',
      lastError: signal?.aborted ? '同步已中断，下次将继续未完成的邮件' : mailServiceError(error, 'IMAP', account).message,
      updatedAt: new Date().toISOString() });
    throw error;
  } finally {
    signal?.removeEventListener('abort', abort);
    if (client) {
      const active = client;
      await imapOperation(active, () => active.logout(), { timeoutMs: 2000 }).catch(() => active.close());
    }
  }
}
export function updateMessage(repo, id, input) {
  return repo.transaction(() => applyMessageUpdate(repo, id, input));
}
function applyMessageUpdate(repo, id, input) {
  const message = repo.get('message', id);
  if (!message) throw new ServiceError('邮件不存在', 404);
  const account = repo.get('account', message.accountId);
  for (const key of ['starred', 'unread', 'folder', 'category']) {
    if (input[key] === undefined) continue;
    if (['starred', 'unread'].includes(key) && typeof input[key] !== 'boolean')
      throw new ServiceError('状态格式错误');
    if (key === 'folder' && !Object.hasOwn(mailFolderNames, input[key]))
      throw new ServiceError('文件夹无效');
    if (key === 'category') input[key] = required(input[key], '分类', 100);
    let targetPath;
    if (key === 'folder') {
      if (message.folder === input[key]) continue;
      const previousFolder = message.folder;
      const trashSource = previousFolder === 'trash' ? trashRestoreFolder(message, account) : null;
      if (input[key] === 'archive' && trashSource !== 'archive') {
        const source = trashSource || previousFolder;
        message.archivedFromFolder = source;
        message.archivedFromPath = trashSource ? message.deletedFromPath
          : account?.folders?.[source]
            || (folderForPath(message.remotePath, account) === source ? message.remotePath : undefined);
      } else if (!['archive', 'trash'].includes(input[key])) {
        if (previousFolder === 'archive' && input[key] === archiveRestoreFolder(message, account))
          targetPath = message.archivedFromPath;
        delete message.archivedFromFolder;
        delete message.archivedFromPath;
      }
      if (input[key] === 'trash') {
        message.deletedFromFolder = message.folder;
        message.deletedFromPath = account?.folders?.[message.folder]
          || (folderForPath(message.remotePath, account) === message.folder ? message.remotePath : undefined);
      } else {
        if (message.folder === 'trash' && input[key] === trashRestoreFolder(message, account))
          targetPath = message.deletedFromPath;
        delete message.deletedFromFolder;
        delete message.deletedFromPath;
      }
    }
    message[key] = input[key];
    if ((message.uid || (message.id.startsWith('sent-') && message.messageId)) && key !== 'category') {
      const mutation = {
        id: `${message.id}:${key}`,
        revision: randomUUID(),
        messageId: id,
        accountId: message.accountId,
        path: message.remotePath,
        uid: message.uid,
        uidValidity: message.uidValidity,
      };
      if (!message.uid) {
        mutation.sourceFolder = 'sent';
        mutation.rfcMessageId = message.messageId;
      }
      if (key === 'folder') { mutation.target = input[key]; mutation.targetPath = targetPath; }
      else {
        mutation.flag = key === 'starred' ? '\\Flagged' : '\\Seen';
        mutation.value = key === 'unread' ? !input[key] : input[key];
      }
      repo.put('mutation', mutation);
    }
  }
  return repo.put('message', message);
}
export function restoreMessage(repo, id) {
  const message = repo.get('message', id);
  if (!message) throw new ServiceError('邮件不存在', 404);
  if (message.folder !== 'trash') throw new ServiceError('只能恢复已删除的邮件', 409);
  return updateMessage(repo, id, {
    folder: trashRestoreFolder(message, repo.get('account', message.accountId)),
  });
}
export function unarchiveMessage(repo, id) {
  const message = repo.get('message', id);
  if (!message) throw new ServiceError('邮件不存在', 404);
  if (message.folder !== 'archive') throw new ServiceError('只能取消已归档邮件的归档', 409);
  return updateMessage(repo, id, {
    folder: archiveRestoreFolder(message, repo.get('account', message.accountId)),
  });
}
export function emptyTrash(repo, accountId, password, approved, options = {}) {
  return clearTrash(repo, accountId, password, approved, { clientFactory: clientFor, ...options });
}
async function saveSent(account, password, raw) {
  const client = clientFor(account, password);
  try {
    await client.connect();
    const folders = await client.list();
    let target =
      folders.find((f) => f.specialUse === '\\Sent')?.path ||
      account.folders?.sent;
    if (!target) {
      target = 'Boxmail Sent';
      await client.mailboxCreate(target);
    }
    await client.append(target, raw, ['\\Seen']);
  } finally {
    await client.logout().catch(() => client.close());
  }
}
export async function sendDraft(
  repo,
  draftId,
  password,
  approved,
  { storeSent = saveSent } = {},
) {
  if (approved !== true) throw new ServiceError('发送邮件需要明确确认', 403);
  // Claim the draft synchronously before any await, so concurrent sends cannot both pass the check.
  const claimed = repo.transaction(() => {
    const current = repo.get('draft', draftId);
    if (!current) throw new ServiceError('草稿不存在', 404);
    if (current.status === 'sent') return null;
    if (current.status === 'sending' || current.status === 'uncertain')
      throw new ServiceError(
        '上次发送结果尚未确认，请检查邮箱后另存草稿，避免重复发送',
        409,
      );
    const sending = { ...current, status: 'sending' };
    repo.put('draft', sending);
    return sending;
  });
  if (!claimed) return { ok: true, alreadySent: true };
  let draft = claimed;
  let account, transport, raw, envelope, options;
  try {
    account = repo.get('account', draft.accountId);
    if (!account || account.isDemo)
      throw new ServiceError('请先添加真实邮箱账号');
    const to = recipients(draft.to);
    if (!to.length) throw new ServiceError('请填写收件人');
    const cc = recipients(draft.cc),
      bcc = recipients(draft.bcc);
    draft = await copyBorrowedAttachments(repo, draft.attachmentIds || [], draft.id, {
      save: attachmentIds => {
        updateDraft(repo, draft, { attachmentIds });
        return { ...draft, attachmentIds };
      },
    });
    const attachments = [];
    for (const id of draft.attachmentIds || []) {
      const a = await attachmentBytes(repo, id);
      attachments.push({
        filename: a.metadata.name,
        content: a.buffer,
        contentType: a.metadata.contentType,
      });
    }
    transport = transportFor(account, password);
    options = {
      from: { name: account.name, address: account.email },
      to,
      cc,
      bcc,
      subject: draft.subject,
      text: draft.body,
      attachments,
      inReplyTo: draft.inReplyTo || undefined,
      references: draft.references?.length ? draft.references : draft.inReplyTo || undefined,
      messageId: `<${draft.id}@boxmail.local>`,
      disableFileAccess: true,
      disableUrlAccess: true,
    };
    const composer = new MailComposer(options).compile();
    raw = await composer.build();
    envelope = composer.getEnvelope();
  } catch (error) {
    // Nothing reached SMTP yet: release the claim so the draft can be edited or sent again.
    updateDraft(repo, draft, { status: 'draft' });
    throw error;
  }
  try {
    const result = await transport.sendMail({
      envelope,
      raw,
      messageId: options.messageId,
    });
    if (!result.accepted?.length)
      throw new ServiceError('SMTP 未接受任何收件人');
    const sentId = `sent-${draft.id}`;
    repo.transaction(() => {
      updateDraft(repo, draft, { status: 'sent', sentAt: new Date().toISOString() });
      repo.put('message', {
        id: sentId,
        accountId: account.id,
        folder: 'sent',
        sender: account.name,
        senderEmail: account.email,
        to: draft.to,
        cc: draft.cc,
        subject: draft.subject,
        body: draft.body,
        preview: draft.body.slice(0, 140),
        date: new Date().toISOString(),
        unread: false,
        starred: false,
        category: '未分类',
        summary: null,
        attachmentIds: draft.attachmentIds || [],
        messageId: result.messageId,
        inReplyTo: draft.inReplyTo || '',
        references: draft.references?.length ? draft.references : draft.inReplyTo ? [draft.inReplyTo] : [],
      });
      // Borrowed files were copied before SMTP, so every sent attachment belongs to this draft.
      reassignAttachments(repo, draft.attachmentIds || [], sentId, draft.id);
      repo.event('send', `已发送：${draft.subject}`);
    });
    let warning = '';
    try {
      await storeSent(account, password, raw);
    } catch {
      warning = '邮件已发送，但写入服务器已发送文件夹失败，本机已保留副本';
      repo.event('send-warning', warning);
    }
    return { ok: true, rejected: result.rejected || [], warning };
  } catch (e) {
    const certainFailure =
      ['EAUTH', 'EENVELOPE', 'ECONNECTION', 'ETLS', 'EDNS'].includes(e.code) ||
      e.responseCode >= 400;
    updateDraft(repo, draft, { status: certainFailure ? 'draft' : 'uncertain' });
    throw new ServiceError(
      certainFailure
        ? (e.code === 'EENVELOPE'
          ? 'SMTP 服务器拒绝收件人，请检查收件地址'
          : mailServiceError(e, 'SMTP', account).message)
        : '发送连接中断，结果未确认。请先检查已发送邮箱，避免重复发送',
      502,
    );
  }
}
