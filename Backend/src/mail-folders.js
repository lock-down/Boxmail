import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';

export const mailFolderNames = {
  inbox: 'INBOX', sent: 'Boxmail Sent', drafts: 'Boxmail Drafts',
  trash: 'Boxmail Trash', archive: 'Boxmail Archive', spam: 'Boxmail Spam',
};
const specialFolders = {
  '\\Sent': 'sent', '\\Drafts': 'drafts', '\\Trash': 'trash',
  '\\Archive': 'archive', '\\Junk': 'spam',
};

export function discoverMailFolders(account, folders) {
  account.folders = {
    ...account.folders,
    ...Object.fromEntries(folders.filter(f => f.specialUse)
      .map(f => [specialFolders[f.specialUse] || f.specialUse, f.path])),
    inbox: folders.find(f => f.path.toUpperCase() === 'INBOX')?.path || 'INBOX',
  };
  for (const [folder, path] of Object.entries(mailFolderNames))
    if (!account.folders[folder] && folders.some(f => f.path === path)) account.folders[folder] = path;
}

export function folderForPath(path, account) {
  if (!path) return undefined;
  if (path.toUpperCase() === 'INBOX') return 'inbox';
  return Object.keys(mailFolderNames).find(folder => account?.folders?.[folder] === path
    || mailFolderNames[folder] === path);
}

function originalFolder(message, account, prefix, excluded) {
  const recorded = message[`${prefix}FromFolder`];
  if (!excluded.includes(recorded) && Object.hasOwn(mailFolderNames, recorded)) return recorded;
  // Older moves may still point at their source mailbox until the next sync.
  const source = folderForPath(message[`${prefix}FromPath`] || message.remotePath, account);
  if (source && !excluded.includes(source)) return source;
  const addresses = [account?.email, ...(account?.aliases || [])]
    .filter(Boolean).map(value => value.trim().toLowerCase());
  if (message.id.startsWith('sent-') || addresses.includes(message.senderEmail?.trim().toLowerCase()))
    return 'sent';
  return 'inbox';
}

export function trashRestoreFolder(message, account) {
  return originalFolder(message, account, 'deleted', ['trash']);
}

export function archiveRestoreFolder(message, account) {
  return originalFolder(message, account, 'archived', ['archive', 'trash']);
}

export async function applyMailMutations(repo, account, client, { strict = false } = {}) {
  for (const mutation of repo.list('mutation').filter(m => m.accountId === account.id)
    .sort((a, b) => Number(!!a.target) - Number(!!b.target))) {
    const path = mutation.path || account.folders[mutation.sourceFolder];
    if (!path) {
      if (mutation.rfcMessageId) { repo.remove('mutation', mutation.id); continue; }
      throw new ServiceError('找不到邮件所在的服务器文件夹，请先同步邮箱');
    }
    const lock = await client.getMailboxLock(path);
    try {
      if (mutation.uid && String(client.mailbox.uidValidity) !== mutation.uidValidity) {
        if (strict) throw new ServiceError('邮件文件夹已改变，请先同步邮箱后再清空', 409);
        repo.remove('mutation', mutation.id);
        repo.event('sync', '文件夹身份已改变，已取消旧的远端操作，避免误改邮件');
        continue;
      }
      let uid = mutation.uid;
      if (!uid && mutation.rfcMessageId) {
        const matches = await client.search({ header: { 'Message-ID': mutation.rfcMessageId } }, { uid: true });
        if (!matches?.length) { repo.remove('mutation', mutation.id); continue; }
        if (matches.length !== 1) throw new ServiceError('服务器中有多份相同邮件，请先同步邮箱后重试', 409);
        uid = matches[0];
      }
      if (mutation.flag) {
        if (mutation.value) await client.messageFlagsAdd(uid, [mutation.flag], { uid: true });
        else await client.messageFlagsRemove(uid, [mutation.flag], { uid: true });
      }
      if (mutation.target) {
        let target = mutation.targetPath || account.folders[mutation.target];
        if (!target) {
          target = mailFolderNames[mutation.target];
          if (!target) throw new ServiceError('文件夹无效');
          if (target !== 'INBOX') await client.mailboxCreate(target);
          account.folders[mutation.target] = target;
        }
        // Restoring before a pending deletion has synced may already be a no-op remotely.
        if (target !== path) {
          const moved = await client.messageMove(uid, target, { uid: true });
          if (!moved) throw new ServiceError('服务器未确认移动邮件');
          const original = repo.get('message', mutation.messageId);
          if (original) repo.put('relocation', {
            id: randomUUID(), accountId: account.id, destination: target, original,
            destinationUID: moved.uidMap?.get(uid),
            uidValidity: moved.uidValidity == null ? undefined : String(moved.uidValidity),
          });
          repo.remove('message', mutation.messageId);
        }
      }
      if (repo.get('mutation', mutation.id)?.revision === mutation.revision)
        repo.remove('mutation', mutation.id);
    } finally { lock.release(); }
  }
}
