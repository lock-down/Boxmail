import { createHash } from 'node:crypto';
import { ServiceError } from './validation.js';

function references(value) {
  return (Array.isArray(value) ? value : [value]).flatMap(item => typeof item === 'string'
    ? item.match(/<[^<>\s]+>/g) || [] : []);
}

export function conversationMembers(repo, id) {
  const selected = repo.get('message', id);
  if (!selected) throw new ServiceError('邮件不存在或已移动，请刷新列表', 404);
  if (selected.folder === 'drafts') throw new ServiceError('草稿尚未投递，请从已收发邮件中打开会话。');
  const messages = repo.messageHeaders(selected.accountId, { previews: false }).filter(message => message.folder !== 'drafts');
  const parent = new Map();
  const find = key => {
    if (!parent.has(key)) parent.set(key, key);
    let root = key;
    while (parent.get(root) !== root) root = parent.get(root);
    while (parent.get(key) !== key) { const next = parent.get(key); parent.set(key, root); key = next; }
    return root;
  };
  const join = (a, b) => { a = find(a); b = find(b); if (a !== b) parent.set(a < b ? b : a, a < b ? a : b); };
  for (const message of messages) {
    const own = `local:${message.id}`;
    find(own);
    for (const reference of [...references(message.messageId), ...references(message.inReplyTo), ...references(message.references)])
      join(own, `rfc:${reference}`);
  }
  const group = find(`local:${id}`);
  const members = messages.filter(message => find(`local:${message.id}`) === group)
    .sort((a, b) => Number(b.id === id) - Number(a.id === id)
      || (Date.parse(b.date) || 0) - (Date.parse(a.date) || 0) || a.id.localeCompare(b.id));
  return { id: createHash('sha256').update(`${selected.accountId}\n${group}`).digest('hex'),
    accountId: selected.accountId, members,
    partial: repo.list('sync').some(progress => progress.accountId === selected.accountId && (progress.hasMore || progress.remaining > 0)) };
}

export function conversationFingerprint(repo, thread) {
  const hash = createHash('sha256');
  for (const member of [...thread.members].sort((a, b) => a.id.localeCompare(b.id))) {
    hash.update(JSON.stringify([member.id, member.messageId, member.date, member.subject, member.inReplyTo, member.references]));
  }
  return hash.digest('hex');
}

export function conversation(repo, id, { offset = 0, limit = 100 } = {}) {
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 200)
    throw new ServiceError('会话分页参数无效');
  const thread = conversationMembers(repo, id);
  return { id: thread.id, accountId: thread.accountId, fingerprint: conversationFingerprint(repo, thread),
    messages: thread.members.slice(offset, offset + limit).map(message => repo.messageHeader(message)),
    total: thread.members.length, nextOffset: offset + limit < thread.members.length ? offset + limit : null,
    partial: thread.partial };
}
