import { ImapFlow } from 'imapflow';
import nodemailer from 'nodemailer';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { simpleParser } from 'mailparser';
import { createHash, randomUUID } from 'node:crypto';
import { saveAttachment, attachmentBytes } from './attachments.js';
import { ServiceError, required, recipients } from './validation.js';
import { mailServiceError } from './mail-errors.js';
import { mailBody, MAIL_BODY_VERSION } from './mail-body.js';
import { applyMailMutations, archiveRestoreFolder, discoverMailFolders, folderForPath, mailFolderNames, trashRestoreFolder } from './mail-folders.js';
import { clearTrash } from './mail-trash.js';

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
  { clientFactory = clientFor, batchSize = 200, folder: requestedFolder, signal } = {},
) {
  const client = clientFactory(account, password);
  let count = 0;
  let repaired = 0;
  let skipped = 0;
  let currentSync;
  const abort = () => client.close();
  signal?.addEventListener('abort', abort, { once: true });
  try {
    signal?.throwIfAborted();
    try { await client.connect(); }
    catch (error) { throw mailServiceError(error, 'IMAP', account); }
    const folders = await client.list();
    discoverMailFolders(account, folders);
    await applyMailMutations(repo, account, client);
    for (const [folder, remotePath] of Object.entries(account.folders).filter(
      ([f]) => ['inbox', 'sent', 'trash', 'drafts', 'archive', 'spam'].includes(f)
        && (!requestedFolder || requestedFolder === f),
    )) {
      signal?.throwIfAborted();
      const syncId = createHash('sha256').update(`${account.id}:${remotePath}`).digest('hex');
      const previous = repo.get('sync', syncId);
      currentSync = { ...previous, id: syncId, accountId: account.id, folder, remotePath,
        status: 'running', lastError: null, updatedAt: new Date().toISOString() };
      repo.put('sync', currentSync);
      const lock = await client.getMailboxLock(remotePath, { readOnly: true });
      try {
        const validity = String(client.mailbox.uidValidity);
        repo.transaction(() => {
          for (const old of repo.list('message').filter(m => m.accountId === account.id
            && m.remotePath === remotePath && m.uidValidity !== validity)) {
            repo.put('recovery', { id: old.id, accountId: account.id, remotePath, original: old });
            repo.remove('message', old.id);
          }
        });
        // Finish the metadata pass before reconciling deletions or issuing another IMAP command.
        const fetched = [];
        if (client.mailbox.exists) {
          for await (const remote of client.fetch('1:*',
            { uid: true, flags: true, size: true, internalDate: true, envelope: true }, { uid: false })) {
            signal?.throwIfAborted();
            fetched.push(remote);
          }
        }
        signal?.throwIfAborted();
        const seen = new Set(fetched.map(m => m.uid));
        const cached = new Map(repo.list('message').filter(m => m.accountId === account.id
          && m.remotePath === remotePath && m.uidValidity === validity).map(m => [m.uid, m]));
        repo.transaction(() => {
          for (const [uid, old] of cached) if (!seen.has(uid)) {
            repo.put('recovery', { id: old.id, accountId: account.id, remotePath, original: old });
            repo.remove('message', old.id); cached.delete(uid);
          }
          for (const remote of fetched) {
            const old = cached.get(remote.uid);
            if (!old) continue;
            const unreadPending = repo.get('mutation', `${old.id}:unread`);
            const starPending = repo.get('mutation', `${old.id}:starred`);
            const updated = { ...old,
              unread: unreadPending ? !unreadPending.value : !remote.flags.has('\\Seen'),
              starred: starPending ? starPending.value : remote.flags.has('\\Flagged') };
            repo.put('message', updated); cached.set(remote.uid, updated);
          }
        });
        const missing = fetched.filter(remote => !cached.has(remote.uid)
          || cached.get(remote.uid).bodyVersion !== MAIL_BODY_VERSION
          || cached.get(remote.uid).headersVersion !== 1).sort((a,b) => b.uid-a.uid);
        currentSync = { ...currentSync, uidValidity: validity, total: fetched.length,
          downloaded: cached.size, remaining: missing.length, hasMore: missing.length > 0 };
        repo.put('sync', currentSync);
        for (const remote of missing.slice(0, Math.min(200, Math.max(1, batchSize)))) {
          signal?.throwIfAborted();
          const id = createHash('sha256').update(`${account.id}:${remotePath}:${validity}:${remote.uid}`).digest('hex');
          const old = repo.get('message', id);
          let parsed;
          if (remote.size <= 25 * 1024 * 1024) {
            const full = await client.fetchOne(remote.uid, { source: true }, { uid: true });
            if (!full?.source) {
              // A message can disappear between listing and downloading. Retry on the next pass.
              skipped++; continue;
            }
            parsed = await simpleParser(full.source, { skipHtmlToText: true, skipTextToHtml: true });
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
            const relocations = repo.list('relocation').filter(r => r.accountId === account.id
              && r.destination === remotePath);
            const legacyRelocations = relocations.filter(r => (!r.destinationUID || r.uidValidity !== validity)
              && parsed.messageId && r.original.messageId === parsed.messageId);
            const relocation = relocations.find(r => r.destinationUID === remote.uid && r.uidValidity === validity)
              || (legacyRelocations.length === 1 ? legacyRelocations[0] : null);
            const recoveries = repo.list('recovery').filter(r => r.accountId === account.id
              && parsed.messageId && r.original.messageId === parsed.messageId);
            const sameFolder = recoveries.filter(r => r.remotePath === remotePath);
            const localSent = folder === 'sent' ? repo.list('message').find(m => m.accountId === account.id
              && m.id.startsWith('sent-') && parsed.messageId && m.messageId === parsed.messageId) : null;
            const retained = relocation || (sameFolder.length === 1 ? sameFolder[0]
              : recoveries.length === 1 ? recoveries[0] : null)
              || (localSent ? { id: localSent.id, original: localSent } : null);
            if (retained) {
              message.summary = retained.original.summary;
              message.translation = retained.original.translation;
              message.category = retained.original.category;
              message.attachmentIds = retained.original.attachmentIds;
              if (folder === 'trash') {
                message.deletedFromFolder = retained.original.deletedFromFolder;
                message.deletedFromPath = retained.original.deletedFromPath;
              }
              if (folder === 'archive' || folder === 'trash') {
                message.archivedFromFolder = retained.original.archivedFromFolder;
                message.archivedFromPath = retained.original.archivedFromPath;
              }
              for (const aid of message.attachmentIds) {
                const a = repo.get('attachment', aid);
                if (a) repo.put('attachment', { ...a, messageId: id });
              }
              for (const draft of repo.list('draft').filter(d => d.sourceMessageId === retained.original.id))
                repo.put('draft', { ...draft, sourceMessageId: id });
              for (const job of repo.list('job').filter(j => j.messageId === retained.original.id))
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
          currentSync = { ...currentSync, downloaded: cached.size,
            remaining: Math.max(0, currentSync.remaining - 1),
            beforeUID: Math.min(...cached.keys()), highestUID: Math.max(...cached.keys()),
            updatedAt: new Date().toISOString() };
          currentSync.hasMore = currentSync.remaining > 0;
          repo.put('sync', currentSync);
        }
        currentSync = { ...currentSync, status: currentSync.hasMore ? 'partial' : 'completed',
          updatedAt: new Date().toISOString() };
        repo.put('sync', currentSync);
      } finally { lock.release(); }
    }
    account.lastSync = new Date().toISOString();
    repo.put('account', account);
    repo.event(
      'sync',
      `${account.email}：新增 ${count} 封，补齐 ${repaired} 封正文，跳过 ${skipped} 个超限邮件`,
    );
    return { count, repaired, skipped, ok: true };
  } catch (error) {
    if (currentSync) repo.put('sync', { ...currentSync,
      status: signal?.aborted ? 'paused' : 'failed',
      lastError: signal?.aborted ? '同步已中断，下次将继续未完成的邮件' : '同步未完成，请检查网络与邮箱配置后重试',
      updatedAt: new Date().toISOString() });
    throw error;
  } finally {
    signal?.removeEventListener('abort', abort);
    await client.logout().catch(() => client.close());
  }
}
export function updateMessage(repo, id, input) {
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
  const draft = repo.get('draft', draftId);
  if (!draft) throw new ServiceError('草稿不存在', 404);
  if (draft.status === 'sent') return { ok: true, alreadySent: true };
  if (draft.status === 'sending' || draft.status === 'uncertain')
    throw new ServiceError(
      '上次发送结果尚未确认，请检查邮箱后另存草稿，避免重复发送',
      409,
    );
  const account = repo.get('account', draft.accountId);
  if (!account || account.isDemo)
    throw new ServiceError('请先添加真实邮箱账号');
  const to = recipients(draft.to);
  if (!to.length) throw new ServiceError('请填写收件人');
  const cc = recipients(draft.cc),
    bcc = recipients(draft.bcc);
  const attachments = [];
  for (const id of draft.attachmentIds || []) {
    const a = await attachmentBytes(repo, id);
    attachments.push({
      filename: a.metadata.name,
      content: a.buffer,
      contentType: a.metadata.contentType,
    });
  }
  const transport = transportFor(account, password);
  const options = {
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
  const raw = await composer.build();
  const envelope = composer.getEnvelope();
  repo.put('draft', { ...draft, status: 'sending' });
  try {
    const result = await transport.sendMail({
      envelope,
      raw,
      messageId: options.messageId,
    });
    if (!result.accepted?.length)
      throw new ServiceError('SMTP 未接受任何收件人');
    repo.transaction(() => {
      repo.put('draft', {
        ...draft,
        status: 'sent',
        sentAt: new Date().toISOString(),
      });
      repo.put('message', {
        id: `sent-${draft.id}`,
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
      });
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
    repo.put('draft', {
      ...draft,
      status: certainFailure ? 'draft' : 'uncertain',
    });
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
