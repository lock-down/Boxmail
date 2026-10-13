import { ImapFlow } from 'imapflow';
import nodemailer from 'nodemailer';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { simpleParser } from 'mailparser';
import { createHash, randomUUID } from 'node:crypto';
import { saveAttachment, attachmentBytes } from './attachments.js';
import { ServiceError, required, recipients } from './validation.js';

function clientFor(account, password) {
  const client = new ImapFlow({
    host: account.imapHost,
    port: account.imapPort,
    secure: account.imapTLS,
    doSTARTTLS: account.imapTLS ? undefined : true,
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
export async function testAccount(account, password) {
  const client = clientFor(account, password);
  try {
    await client.connect();
    await transportFor(account, password).verify();
    return { ok: true };
  } finally {
    await client.logout().catch(() => client.close());
  }
}
const special = {
  '\\Sent': 'sent',
  '\\Drafts': 'drafts',
  '\\Trash': 'trash',
  '\\Archive': 'archive',
  '\\Junk': 'spam',
};
export async function syncAccount(
  repo,
  account,
  password,
  { clientFactory = clientFor } = {},
) {
  const client = clientFactory(account, password);
  let count = 0;
  let skipped = 0;
  try {
    await client.connect();
    const folders = await client.list();
    account.folders = {
      ...account.folders,
      ...Object.fromEntries(
        folders
          .filter((f) => f.specialUse)
          .map((f) => [special[f.specialUse] || f.specialUse, f.path]),
      ),
    };
    account.folders.inbox =
      folders.find((f) => f.path.toUpperCase() === 'INBOX')?.path || 'INBOX';
    for (const mutation of repo
      .list('mutation')
      .filter((m) => m.accountId === account.id)
      .sort((a, b) => Number(!!a.target) - Number(!!b.target))) {
      const lock = await client.getMailboxLock(mutation.path);
      try {
        if (String(client.mailbox.uidValidity) !== mutation.uidValidity) {
          repo.remove('mutation', mutation.id);
          continue;
        }
        if (mutation.flag) {
          if (mutation.value)
            await client.messageFlagsAdd(mutation.uid, [mutation.flag], {
              uid: true,
            });
          else
            await client.messageFlagsRemove(mutation.uid, [mutation.flag], {
              uid: true,
            });
        }
        if (mutation.target) {
          let target = account.folders[mutation.target];
          if (!target) {
            target =
              mutation.target === 'trash'
                ? 'Boxmail Trash'
                : mutation.target === 'archive'
                  ? 'Boxmail Archive'
                  : 'INBOX';
            if (target !== 'INBOX') await client.mailboxCreate(target);
            account.folders[mutation.target] = target;
          }
          const moved = await client.messageMove(mutation.uid, target, {
            uid: true,
          });
          if (!moved) throw new ServiceError('服务器未确认移动邮件');
          const original = repo.get('message', mutation.messageId);
          if (original)
            repo.put('relocation', {
              id: randomUUID(),
              accountId: account.id,
              destination: target,
              original,
            });
          repo.remove('message', mutation.messageId);
        }
        if (repo.get('mutation', mutation.id)?.revision === mutation.revision)
          repo.remove('mutation', mutation.id);
      } finally {
        lock.release();
      }
    }
    for (const [folder, remotePath] of Object.entries(account.folders).filter(
      ([f]) =>
        ['inbox', 'sent', 'trash', 'drafts', 'archive', 'spam'].includes(f),
    )) {
      const lock = await client.getMailboxLock(remotePath, { readOnly: true });
      try {
        const validity = String(client.mailbox.uidValidity);
        for (const old of repo
          .list('message')
          .filter(
            (m) =>
              m.accountId === account.id &&
              m.remotePath === remotePath &&
              m.uidValidity !== validity,
          ))
          repo.remove('message', old.id);
        if (!client.mailbox.exists) {
          for (const old of repo
            .list('message')
            .filter(
              (m) => m.accountId === account.id && m.remotePath === remotePath,
            ))
            repo.remove('message', old.id);
          continue;
        }
        const start = Math.max(1, client.mailbox.exists - 199);
        const fetched = [];
        for await (const remote of client.fetch(
          `${start}:*`,
          { uid: true, flags: true, size: true, internalDate: true },
          { uid: false },
        ))
          fetched.push(remote);
        const seen = new Set(fetched.map((m) => m.uid));
        const smallestUID = Math.min(...seen);
        for (const old of repo
          .list('message')
          .filter(
            (m) =>
              m.accountId === account.id &&
              m.remotePath === remotePath &&
              (start === 1 || m.uid >= smallestUID) &&
              !seen.has(m.uid),
          ))
          repo.remove('message', old.id);
        for (const remote of fetched) {
          if (remote.size > 25 * 1024 * 1024) {
            skipped++;
            continue;
          }
          const id = createHash('sha256')
            .update(`${account.id}:${remotePath}:${validity}:${remote.uid}`)
            .digest('hex');
          const old = repo.get('message', id);
          if (old) {
            const unreadPending = repo.get('mutation', `${id}:unread`),
              starPending = repo.get('mutation', `${id}:starred`);
            repo.put('message', {
              ...old,
              unread: unreadPending
                ? !unreadPending.value
                : !remote.flags.has('\\Seen'),
              starred: starPending
                ? starPending.value
                : remote.flags.has('\\Flagged'),
            });
            continue;
          }
          const full = await client.fetchOne(
            remote.uid,
            { source: true },
            { uid: true },
          );
          if (!full?.source) {
            skipped++;
            continue;
          }
          const parsed = await simpleParser(full.source, {
            skipHtmlToText: false,
            skipTextToHtml: true,
          });
          const from = parsed.from?.value[0];
          const body = parsed.text || '';
          const message = {
            id,
            accountId: account.id,
            folder,
            remotePath,
            uid: remote.uid,
            uidValidity: validity,
            messageId: parsed.messageId || '',
            sender: from?.name || from?.address || '未知发件人',
            senderEmail: from?.address || '',
            to: parsed.to?.text || account.email,
            cc: parsed.cc?.text || '',
            subject: parsed.subject || '(无主题)',
            body,
            preview: body.replace(/\s+/g, ' ').slice(0, 140),
            date: (
              parsed.date ||
              remote.internalDate ||
              new Date()
            ).toISOString(),
            unread: !remote.flags.has('\\Seen'),
            starred: remote.flags.has('\\Flagged'),
            category: '未分类',
            summary: null,
            attachmentIds: [],
          };
          const relocation = repo
            .list('relocation')
            .find(
              (r) =>
                r.accountId === account.id &&
                r.destination === remotePath &&
                parsed.messageId &&
                r.original.messageId === parsed.messageId,
            );
          if (relocation) {
            message.summary = relocation.original.summary;
            message.category = relocation.original.category;
            message.attachmentIds = relocation.original.attachmentIds;
            for (const aid of message.attachmentIds) {
              const a = repo.get('attachment', aid);
              if (a) repo.put('attachment', { ...a, messageId: id });
            }
            for (const draft of repo
              .list('draft')
              .filter((d) => d.sourceMessageId === relocation.original.id))
              repo.put('draft', { ...draft, sourceMessageId: id });
            repo.remove('relocation', relocation.id);
          } else
            for (const a of parsed.attachments) {
              const saved = await saveAttachment(
                repo,
                id,
                a.filename || '附件',
                a.content,
                a.contentType,
              );
              message.attachmentIds.push(saved.id);
            }
          const localSent = repo
            .list('message')
            .find(
              (m) =>
                m.accountId === account.id &&
                m.id.startsWith('sent-') &&
                parsed.messageId &&
                m.messageId === parsed.messageId,
            );
          if (localSent) repo.remove('message', localSent.id);
          repo.put('message', message);
          count++;
        }
      } finally {
        lock.release();
      }
    }
    account.lastSync = new Date().toISOString();
    repo.put('account', account);
    repo.event(
      'sync',
      `${account.email}：新增 ${count} 封，跳过 ${skipped} 个超限邮件`,
    );
    return { count, skipped, ok: true };
  } finally {
    await client.logout().catch(() => client.close());
  }
}
export function updateMessage(repo, id, input) {
  const message = repo.get('message', id);
  if (!message) throw new ServiceError('邮件不存在', 404);
  for (const key of ['starred', 'unread', 'folder', 'category']) {
    if (input[key] === undefined) continue;
    if (['starred', 'unread'].includes(key) && typeof input[key] !== 'boolean')
      throw new ServiceError('状态格式错误');
    if (key === 'folder' && !['inbox', 'trash', 'archive'].includes(input[key]))
      throw new ServiceError('文件夹无效');
    if (key === 'category') input[key] = required(input[key], '分类', 100);
    message[key] = input[key];
    if (message.uid && key !== 'category') {
      const mutation = {
        id: `${message.id}:${key}`,
        revision: randomUUID(),
        messageId: id,
        accountId: message.accountId,
        path: message.remotePath,
        uid: message.uid,
        uidValidity: message.uidValidity,
      };
      if (key === 'folder') mutation.target = input[key];
      else {
        mutation.flag = key === 'starred' ? '\\Flagged' : '\\Seen';
        mutation.value = key === 'unread' ? !input[key] : input[key];
      }
      repo.put('mutation', mutation);
    }
  }
  return repo.put('message', message);
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
    references: draft.inReplyTo || undefined,
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
        ? '发送失败，请检查 SMTP 设置或收件人'
        : '发送连接中断，结果未确认。请先检查已发送邮箱，避免重复发送',
      502,
    );
  }
}
