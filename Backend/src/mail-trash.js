import { ServiceError } from './validation.js';
import { mailServiceError } from './mail-errors.js';
import { applyMailMutations, discoverMailFolders } from './mail-folders.js';
import { removeUnusedAttachments } from './attachments.js';

export async function clearTrash(repo, accountId, password, approved, { clientFactory }) {
  if (approved !== true) throw new ServiceError('清空已删除邮件需要明确确认', 403);
  const account = repo.get('account', accountId);
  if (!account) throw new ServiceError('账户不存在', 404);
  if (!account.isDemo) {
    const client = clientFactory(account, password);
    try {
      try { await client.connect(); }
      catch (error) { throw mailServiceError(error, 'IMAP', account); }
      discoverMailFolders(account, await client.list());
      // Apply pending restores first so those messages are outside Trash before expunging.
      await applyMailMutations(repo, account, client, { strict: true });
      const trashPath = account.folders.trash;
      if (trashPath) {
        const lock = await client.getMailboxLock(trashPath);
        try {
          // Clear the entire server mailbox, including messages not downloaded locally.
          if (client.mailbox.exists && !await client.messageDelete('1:*'))
            throw new ServiceError('服务器未确认清空已删除邮件，请同步后重试');
        } finally { lock.release(); }
      }
      const latest = repo.get('account', accountId);
      if (latest) repo.put('account', { ...latest, folders: account.folders });
    } finally { await client.logout().catch(() => client.close()); }
  }

  const messages = repo.list('message').filter(m => m.accountId === accountId && m.folder === 'trash');
  const retained = ['relocation', 'recovery'].flatMap(kind => repo.list(kind)
    .filter(r => r.accountId === accountId && r.original.folder === 'trash')
    .map(record => ({ kind, record })));
  const originals = [...messages, ...retained.map(r => r.record.original)];
  const ids = new Set(originals.map(m => m.id));
  const candidates = new Set(originals.flatMap(m => m.attachmentIds || []));
  repo.transaction(() => {
    for (const message of messages) repo.remove('message', message.id);
    for (const { kind, record } of retained) repo.remove(kind, record.id);
    for (const kind of ['mutation', 'job'])
      for (const record of repo.list(kind).filter(r => r.accountId === accountId && ids.has(r.messageId)))
        repo.remove(kind, record.id);
    for (const progress of repo.list('sync').filter(p => p.accountId === accountId && p.folder === 'trash'))
      repo.put('sync', { ...progress, total: 0, downloaded: 0, remaining: 0, hasMore: false,
        status: 'completed', lastError: null, updatedAt: new Date().toISOString() });
  });
  await removeUnusedAttachments(repo, candidates);
  repo.event('trash', '已清空当前账户的已删除邮件');
  return { ok: true, count: ids.size };
}
