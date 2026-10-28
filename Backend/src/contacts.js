import { textSlice } from './unicode.js';
import addressparser from 'nodemailer/lib/addressparser/index.js';
import { ServiceError } from './validation.js';

export function contactSuggestions(repo, accountId, query = '', limit = 8) {
  const account = repo.get('account', accountId);
  if (!account) throw new ServiceError('请选择联系人所属的邮箱账户');
  if (typeof query !== 'string' || query.length > 500) throw new ServiceError('联系人查询过长');
  const own = new Set([account.email, account.username, ...(account.aliases || [])].filter(Boolean).map(item => item.toLowerCase()));
  const contacts = new Map();
  for (const message of repo.contactHeaders(accountId)) {
    const date = message.date || message.updatedAt || '';
    const parsed = [
      { address: message.senderEmail, name: message.sender },
      ...addressparser([message.to, message.cc, message.bcc, message.replyTo].filter(Boolean).join(', '), { flatten: true }),
    ];
    const used = new Set();
    for (const item of parsed) {
      const email = item.address?.trim().toLowerCase();
      if (!email || !/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(email) || own.has(email) || used.has(email)) continue;
      used.add(email);
      const previous = contacts.get(email);
      contacts.set(email, { email, name: item.name?.trim() && (!previous?.name || date >= previous.lastUsed)
        ? textSlice(item.name.trim(), 0, 200) : previous?.name || '',
        frequency: (previous?.frequency || 0) + 1, lastUsed: date > (previous?.lastUsed || '') ? date : previous?.lastUsed || date });
    }
  }
  const term = query.normalize('NFKC').trim().toLocaleLowerCase();
  return { contacts: [...contacts.values()]
    .filter(item => !term || `${item.name}\n${item.email}`.normalize('NFKC').toLocaleLowerCase().includes(term))
    .sort((a, b) => b.frequency - a.frequency || b.lastUsed.localeCompare(a.lastUsed) || a.email.localeCompare(b.email))
    .slice(0, Math.min(20, Math.max(1, Number(limit) || 8))) };
}
