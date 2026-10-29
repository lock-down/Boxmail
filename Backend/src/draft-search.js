import { textSlice } from './unicode.js';
import { parseSearch, searchWhere } from './search-query.js';
import { mailPreview, mailPreviewText } from './mail-preview.js';
import { draftContent, upgradeForwardDraft } from './forward-content.js';

const normalize = value => String(value || '').normalize('NFKC').toLocaleLowerCase();
const prefix = 'draft:';
export const DRAFT_SEARCH_LIMIT = 65536;
export function draftPreview(draft, account = {}) {
  return mailPreview({ body: draftContent(draft).text, sender: account.name || account.email });
}
function presentDraft(draft, account, repo) {
  draft = upgradeForwardDraft(draft, () => draft.sourceMessageId ? repo.get('message', draft.sourceMessageId) : null);
  const content = draftContent(draft);
  return { id: prefix + draft.id, draftId: draft.id, accountId: draft.accountId, folder: 'drafts',
    sender: account.name || account.email, senderEmail: account.email, to: draft.to || '', cc: draft.cc || '', bcc: draft.bcc || '',
    subject: draft.subject || '无主题草稿', body: content.text, ...(content.html ? { html: content.html } : {}),
    preview: draftPreview(draft, account),
    date: draft.updatedAt, category: '未分类', unread: false, starred: false,
    attachmentIds: draft.attachmentIds || [], bodyLoaded: true };
}
export function draftSearchMessage(repo, id) {
  if (!id.startsWith(prefix)) return null;
  const draft = repo.get('draft', id.slice(prefix.length));
  const account = draft && repo.get('account', draft.accountId);
  return draft && account && draft.status !== 'sent' ? presentDraft(draft, account, repo) : null;
}
export function draftSearchPage(repo, { query = '', accountId, folder, filter, offset = 0, limit = 100 } = {}) {
  const parsed = parseSearch(query);
  const explicit = parsed.conditions.some(item => item.field === 'folder' && item.value === 'drafts');
  if (!explicit && folder !== 'drafts') return null;
  const accounts = repo.list('account'), byAccount = new Map(accounts.map(item => [item.id, item]));
  const db = repo.db;
  // Project one bounded draft at a time. Never materialize all source bodies or
  // unrelated attachment text in JS, nor serialize the library as one JSON value.
  db.exec('CREATE TEMP TABLE IF NOT EXISTS draft_search (kind TEXT,id TEXT PRIMARY KEY,data TEXT); DELETE FROM draft_search');
  const insert = db.prepare('INSERT INTO draft_search VALUES(?,?,?)');
  const attachment = db.prepare(`SELECT substr(coalesce(json_extract(data,'$.name'),'')||char(10)||
    coalesce(json_extract(data,'$.text'),'')||char(10)||coalesce(json_extract(data,'$.analysis'),''),1,?) AS text
    FROM records WHERE kind='attachment' AND id=?`);
  const drafts = db.prepare(`SELECT json_remove(json_set(data,
    '$.body',substr(coalesce(json_extract(data,'$.body'),''),1,?),
    '$.forwardedText',substr(coalesce(json_extract(data,'$.forwardedText'),''),1,?),
    '$.forwardedHTML',''),'$.sourceMessageId') AS data FROM records WHERE kind='draft'
    AND coalesce(json_extract(data,'$.status'),'draft')!='sent'`);
  try {
    for (const row of drafts.iterate(DRAFT_SEARCH_LIMIT, DRAFT_SEARCH_LIMIT)) {
      const draft = JSON.parse(row.data), account = byAccount.get(draft.accountId);
      if (!account) continue;
      const message = presentDraft(draft, account, repo);
      let text = [message.subject, message.body, message.sender, message.senderEmail, message.to, message.cc, message.bcc].join('\n');
      let snippet = [message.subject, mailPreviewText(message), message.sender, message.senderEmail, message.to, message.cc, message.bcc].join('\n');
      // Limit each field and the combined document, including many tiny files.
      for (const id of message.attachmentIds) {
        if (text.length >= DRAFT_SEARCH_LIMIT * 4) break;
        const extra = '\n' + (attachment.get(DRAFT_SEARCH_LIMIT, id)?.text || '');
        text += extra; snippet += extra;
      }
      const draftSearchText = textSlice(normalize(textSlice(text, 0, DRAFT_SEARCH_LIMIT * 4)), 0, DRAFT_SEARCH_LIMIT * 4);
      const draftSnippetText = textSlice(normalize(textSlice(snippet, 0, DRAFT_SEARCH_LIMIT * 4)), 0, DRAFT_SEARCH_LIMIT * 4);
      insert.run('message', message.id, JSON.stringify({ ...message, body: '', html: undefined,
        bodyLoaded: false, draftSearchText, draftSnippetText }));
    }
    const { clauses, params } = searchWhere(parsed, { accountId, filter, accounts });
    for (const term of parsed.terms) {
      clauses.push("instr(json_extract(m.data,'$.draftSearchText'),?)>0"); params.push(normalize(term));
    }
    const where = clauses.join(' AND ');
    const total = db.prepare(`SELECT count(*) AS total FROM draft_search m WHERE ${where}`).get(...params).total;
    const rows = db.prepare(`SELECT data FROM draft_search m WHERE ${where}
      ORDER BY json_extract(data,'$.date') DESC,id LIMIT ? OFFSET ?`).all(...params, limit, offset);
    return { messages: rows.map(row => {
      const { draftSearchText, draftSnippetText, ...message } = JSON.parse(row.data);
      if (parsed.terms.length) {
        const term = normalize(parsed.terms[0]);
        const snippetText = draftSnippetText;
        const position = snippetText.indexOf(term);
        if (position >= 0) message.searchSnippet = textSlice(snippetText, Math.max(0, position - 28), position + 132).replace(/\n/g, ' ');
      }
      return message;
    }), total, nextOffset: offset + rows.length < total ? offset + rows.length : null };
  } finally { db.exec('DELETE FROM draft_search'); }
}
