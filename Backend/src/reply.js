import { randomUUID } from 'node:crypto';
import addressparser from 'nodemailer/lib/addressparser/index.js';
import { ServiceError } from './validation.js';

export function addresses(value) {
  return addressparser(String(value || '').replace(/[，；]/g, ','), { flatten: true })
    .map(item => item.address?.trim())
    .filter(value => value && /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value));
}

export function referenceChain(message) {
  const values = [...(Array.isArray(message.references) ? message.references : []), message.messageId];
  return [...new Set(values.filter(value => typeof value === 'string' && /^<[^<>\s]+>$/.test(value)))];
}

export function buildReplyDraft(message, account = {}, { all = false, forward = false, body, subject } = {}) {
  account ??= {};
  const own = new Set([account.email, account.username, ...(account.aliases || [])]
    .filter(Boolean).map(value => value.toLowerCase()));
  const used = new Set(own);
  const take = list => list.filter(value => {
    const key = value.toLowerCase();
    if (used.has(key)) return false;
    used.add(key); return true;
  });
  const fromSelf = own.has(String(message.senderEmail).toLowerCase());
  let to = take(addresses(fromSelf ? message.to : message.replyTo || message.senderEmail));
  if (all) to = [...to, ...take(addresses(message.to))];
  const cc = all ? take(addresses(message.cc)) : [];
  const prefix = forward ? 'Fwd: ' : 'Re: ';
  const title = subject ?? (new RegExp(forward ? '^(?:fwd?|转发):' : '^(?:re|回复):', 'i').test(message.subject)
    ? message.subject : prefix + message.subject);
  const signature = account.signature ? `\n\n${account.signature}` : '';
  return {
    id: randomUUID(), accountId: message.accountId,
    to: forward ? '' : to.join(', '), cc: forward ? '' : cc.join(', '), bcc: '', subject: title,
    body: body ?? (forward ? `${signature}\n\n---------- 转发邮件 ----------\n发件人：${message.sender} <${message.senderEmail}>\n日期：${message.date}\n主题：${message.subject}\n\n${message.body}` : signature),
    attachmentIds: forward ? [...message.attachmentIds] : [],
    inReplyTo: forward ? '' : message.messageId || '',
    references: forward ? [] : referenceChain(message),
    sourceMessageId: message.id, status: 'draft', updatedAt: new Date().toISOString(),
  };
}

export function createReplyDraft(repo, id, options) {
  const message = repo.get('message', id);
  if (!message) throw new ServiceError('原邮件不存在，请刷新后重试', 404);
  const account = repo.get('account', message.accountId);
  if (!account) throw new ServiceError('原邮件所属账户不存在', 404);
  const signature = repo.get('settings', 'settings')?.preferences.signature || '';
  return repo.put('draft', buildReplyDraft(message, { ...account, signature }, options));
}
