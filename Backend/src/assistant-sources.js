import { draftSearchMessage } from './draft-search.js';
import { conversationMembers } from './threads.js';
import { normalizeSearchText, textSlice } from './unicode.js';

export const ASSISTANT_FOLDERS = ['inbox', 'drafts', 'sent', 'archive', 'starred', 'spam', 'trash'];
const segmenter = new Intl.Segmenter('zh', { granularity: 'word' });

export function assistantTerms(prompt) {
  // The local index is based on bigrams. Keep distinct searchable terms.
  const terms = [...new Set(Array.from(segmenter.segment(normalizeSearchText(prompt)))
    .filter(word => word.isWordLike && word.segment.length > 1).map(word => word.segment))];
  return terms.sort((a, b) => b.length - a.length).slice(0, 40);
}

export function readAssistantSource(repo, id) {
  return repo.get('message', id) || draftSearchMessage(repo, id);
}

export function assistantCandidates(repo, scope, terms, previousIds, limit) {
  if (scope.kind === 'message') return { ids: [scope.messageId], total: 1 };
  if (scope.kind === 'conversation') {
    const ids = conversationMembers(repo, scope.messageId).members.map(item => item.id);
    return { ids: ids.slice(0, limit), total: ids.length };
  }
  if (scope.kind === 'attachments') {
    const ids = [...new Set(scope.attachmentIds.map(id => repo.get('attachment', id)?.messageId || ''))];
    return { ids, total: ids.length };
  }

  const drafts = scope.kind === 'folder' && scope.query.folder === 'drafts';
  const { where, params } = drafts ? {
    where: "m.kind='draft' AND coalesce(json_extract(m.data,'$.status'),'draft')!='sent'"
      + (scope.query.accountId ? " AND json_extract(m.data,'$.accountId')=?" : ''),
    params: scope.query.accountId ? [scope.query.accountId] : [],
  } : repo.messageWhere(scope.query);
  const id = drafts ? "'draft:'||m.id" : 'm.id';
  const date = drafts ? '$.updatedAt' : '$.date';
  const draftText = "lower(coalesce(json_extract(m.data,'$.subject'),'')||char(10)||coalesce(json_extract(m.data,'$.body'),'')||char(10)||coalesce(json_extract(m.data,'$.to'),'')||char(10)||coalesce(json_extract(m.data,'$.forwardedText'),''))";
  const matches = terms.map(term => drafts
    ? { clause: `instr(${draftText},?)>0`, params: [term] }
    : repo.searchIndex.where([term]));
  const score = matches.map(match => `CASE WHEN ${match.clause} THEN 1 ELSE 0 END`).join('+') || '0';
  const rows = repo.db.prepare(`SELECT ${id} AS id, COUNT(*) OVER() AS total,
    (${score}) AS relevance, ${id} IN (SELECT value FROM json_each(?)) AS previous
    FROM records m WHERE ${where}
    ORDER BY relevance DESC, previous DESC, json_extract(m.data,'${date}') DESC, m.id LIMIT ?`)
    .all(...matches.flatMap(match => match.params), JSON.stringify(previousIds), ...params, limit);
  const relevant = rows.filter(row => row.relevance || row.previous);
  return { ids: (relevant.length ? relevant : rows).map(row => row.id), total: rows[0]?.total ?? 0 };
}

export function sourceAttachments(scope, message) {
  return scope.kind === 'attachments'
    ? scope.attachmentIds.filter(id => message.attachmentIds.includes(id))
    : message.attachmentIds;
}

function excerpt(text, length, terms) {
  if (length <= 0) return '';
  if (text.length <= length) return text;
  const normalized = text.toLowerCase();
  let start = 0;
  for (const term of terms) {
    const index = normalized.indexOf(term);
    if (index >= 0) {
      start = Math.max(0, index - Math.floor(length / 4));
      break;
    }
  }
  return (start ? '…' : '') + textSlice(text, start, start + length)
    + (start + length < text.length ? '…' : '');
}

export function cachedAssistantDocument(repo, message, attachmentIds, terms, length) {
  const files = attachmentIds.map(id => {
    const file = repo.get('attachment', id);
    return { id, file, relevance: fileRelevance(file, terms) };
  }).sort((a, b) => b.relevance - a.relevance);
  const attachments = [];
  const limit = Math.floor(length / (files.length ? 2 : 1));
  const sourceBody = message.body || message.preview || '';
  const body = excerpt(sourceBody, limit, terms);
  let remaining = length - body.length;
  for (const { id, file } of files) {
    const name = textSlice(file?.name || '附件', 0, Math.max(0, remaining));
    if (!name || remaining <= name.length) break;
    remaining -= name.length;
    const cached = file?.text || '';
    const text = excerpt(cached, Math.floor(remaining / (files.length - attachments.length)), terms);
    remaining -= text.length;
    const status = !text ? 'unavailable' : text === cached && !file.textTruncated ? 'included' : 'partial';
    const reason = status === 'included' ? null : text ? '本轮只纳入缓存片段。' : '本轮未纳入可读附件内容。';
    attachments.push({ id, name, status, reason, text });
  }
  const coverage = { attachments: attachments.map(({ text, ...file }) => file),
    partial: attachments.length < files.length || attachments.some(file => file.status !== 'included') };
  return { content: {
    sender: excerpt(message.sender || '', length, []), subject: excerpt(message.subject || '', length, []),
    to: excerpt(message.to || '', length, []), date: message.date, body, attachments,
  }, images: [], coverage, partial: body !== sourceBody || coverage.partial };
}

function fileRelevance(file, terms) {
  const text = normalizeSearchText(`${file?.name || ''}\n${file?.text || ''}`);
  return terms.reduce((score, term) => score + Number(text.includes(term)), 0);
}
