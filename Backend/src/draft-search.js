import { parseSearch, searchWhere } from './search-query.js';
import { mailPreview, mailPreviewText } from './mail-preview.js';

const normalize = value => String(value || '').normalize('NFKC').toLocaleLowerCase();
const prefix = 'draft:';
export function draftPreview(draft, account = {}) {
  return mailPreview({ body: draft.body, sender: account.name || account.email });
}
function presentDraft(draft, account) {
  return { id: prefix + draft.id, draftId: draft.id, accountId: draft.accountId, folder: 'drafts',
    sender: account.name || account.email, senderEmail: account.email, to: draft.to || '', cc: draft.cc || '', bcc: draft.bcc || '',
    subject: draft.subject || '无主题草稿', body: draft.body || '',
    preview: draftPreview(draft, account),
    date: draft.updatedAt, category: '未分类', unread: false, starred: false,
    attachmentIds: draft.attachmentIds || [], bodyLoaded: true };
}
export function draftSearchMessage(repo, id) {
  if (!id.startsWith(prefix)) return null;
  const draft = repo.get('draft', id.slice(prefix.length));
  const account = draft && repo.get('account', draft.accountId);
  return draft && account && draft.status !== 'sent' ? presentDraft(draft, account) : null;
}
export function draftSearchPage(repo, { query = '', accountId, folder, filter, offset = 0, limit = 100 } = {}) {
  const parsed = parseSearch(query);
  const explicit = parsed.conditions.some(item => item.field === 'folder' && item.value === 'drafts');
  if (!explicit && !(folder === 'drafts' && !parsed.terms.length && !parsed.conditions.length)) return null;
  const accounts = repo.list('account'), byAccount = new Map(accounts.map(item => [item.id, item]));
  const attachments = new Map(repo.list('attachment').map(item => [item.id, item]));
  const messages = repo.list('draft').filter(draft => draft.status !== 'sent' && byAccount.has(draft.accountId)).map(draft => {
    const message = presentDraft(draft, byAccount.get(draft.accountId));
    const files = message.attachmentIds.map(id => attachments.get(id)).filter(Boolean);
    return { ...message, draftSearchText: normalize([message.subject, message.body, message.sender, message.senderEmail,
      message.to, message.cc, message.bcc, ...files.flatMap(file => [file.name, file.text, file.analysis])].filter(Boolean).join('\n')) };
  });
  const { clauses, params } = searchWhere(parsed, { accountId, filter, accounts });
  for (const term of parsed.terms) {
    clauses.push("instr(json_extract(m.data,'$.draftSearchText'),?)>0"); params.push(normalize(term));
  }
  const source = JSON.stringify(messages);
  const cte = "WITH mail AS (SELECT 'message' AS kind,json_extract(value,'$.id') AS id,value AS data FROM json_each(?))";
  const where = clauses.join(' AND ');
  const total = repo.db.prepare(`${cte} SELECT count(*) AS total FROM mail m WHERE ${where}`).get(source, ...params).total;
  const rows = repo.db.prepare(`${cte} SELECT data FROM mail m WHERE ${where}
    ORDER BY json_extract(data,'$.date') DESC,id LIMIT ? OFFSET ?`).all(source, ...params, limit, offset);
  return { messages: rows.map(row => {
    const { draftSearchText, ...message } = JSON.parse(row.data);
    if (parsed.terms.length) {
      const term = normalize(parsed.terms[0]);
      const files = message.attachmentIds.map(id => attachments.get(id)).filter(Boolean);
      const snippetText = normalize([message.subject, mailPreviewText(message), message.sender, message.senderEmail,
        message.to, message.cc, message.bcc, ...files.flatMap(file => [file.name, file.text, file.analysis])]
        .filter(Boolean).join('\n'));
      const position = snippetText.indexOf(term);
      if (position >= 0) message.searchSnippet = snippetText.slice(Math.max(0, position - 28), position + 132).replace(/\n/g, ' ');
    }
    return message;
  }), total, nextOffset: offset + rows.length < total ? offset + rows.length : null };
}
