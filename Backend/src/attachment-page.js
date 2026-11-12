import { ServiceError } from './validation.js';
import { attachmentMetadata } from './attachment-metadata.js';

import { attachmentKind, extensions } from './attachment-kind.js';

const databases = new WeakSet();
function prepareFunctions(db) {
  if (databases.has(db)) return;
  db.function('attachment_kind', { deterministic: true }, (name, mime) =>
    attachmentKind(name, mime));
  db.function('attachment_name_key', { deterministic: true }, name => String(name || '').toLowerCase()
    .replace(/\d+/g, digits => {
      const value = digits.replace(/^0+(?=\d)/, '');
      return `\u0001${String(value.length).padStart(8, '0')}${value}\u0002`;
    }));
  databases.add(db);
}

/** SQL filters and sorts the whole account; only one compact page crosses the process boundary. */
export function attachmentPage(repo, { accountId = '', query = '', type = 'all', sort = 'date',
  ascending = false, offset = 0, limit = 50 } = {}) {
  if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100)
    throw new ServiceError('附件分页参数无效');
  if (!['all', ...new Set(Object.values(extensions)), 'other'].includes(type)
    || !['name', 'size', 'date'].includes(sort)) throw new ServiceError('附件筛选或排序参数无效');
  prepareFunctions(repo.db);
  const from = `FROM records a JOIN records m ON m.kind='message' AND m.id=json_extract(a.data,'$.messageId')
    WHERE a.kind='attachment' AND json_extract(m.data,'$.accountId')=?`;
  const stats = repo.db.prepare(`SELECT count(*) AS accountTotal,
    coalesce(sum(length(coalesce(json_extract(a.data,'$.analysis'),''))>0),0) AS analyzedTotal ${from}`).get(accountId);
  const clauses = [], parameters = [accountId];
  if (type !== 'all') {
    clauses.push("attachment_kind(json_extract(a.data,'$.name'),json_extract(a.data,'$.contentType'))=?");
    parameters.push(type);
  }
  if (query.trim()) {
    clauses.push(`instr(lower(coalesce(json_extract(a.data,'$.name'),'')||char(10)||
      coalesce(json_extract(a.data,'$.text'),'')||char(10)||coalesce(json_extract(a.data,'$.analysis'),'')||char(10)||
      coalesce(json_extract(a.data,'$.archiveInfo.searchText'),'')),lower(?))>0`);
    parameters.push(query.trim());
  }
  const where = from + clauses.map(clause => ` AND ${clause}`).join('');
  const total = repo.db.prepare(`SELECT count(*) AS total ${where}`).get(...parameters).total;
  offset = Math.min(offset, Math.max(0, Math.ceil(total / limit) - 1) * limit);
  const name = "attachment_name_key(json_extract(a.data,'$.name'))";
  const date = "coalesce(nullif(json_extract(m.data,'$.date'),''),json_extract(a.data,'$.date'),'')";
  const order = { name, date, size: "coalesce(json_extract(a.data,'$.size'),0)" }[sort];
  const rows = repo.db.prepare(`SELECT json_object(
    'id',a.id,'messageId',m.id,'name',coalesce(json_extract(a.data,'$.name'),''),
    'contentType',json_extract(a.data,'$.contentType'),
    'size',coalesce(json_extract(a.data,'$.size'),0),'text','','parseError',coalesce(json_extract(a.data,'$.parseError'),''),
    'date',coalesce(json_extract(a.data,'$.date'),'')) AS attachment,
    json_object('id',m.id,'subject',coalesce(json_extract(m.data,'$.subject'),''),
      'sender',coalesce(json_extract(m.data,'$.sender'),''),'date',${date}) AS source,
    length(coalesce(json_extract(a.data,'$.text'),''))>0 AS hasText,
    length(coalesce(json_extract(a.data,'$.analysis'),''))>0 AS hasAnalysis,
    json_extract(a.data,'$.archiveInfo.totalFiles') AS archiveTotal,
    json_extract(a.data,'$.archiveInfo.status') AS archiveStatus,
    json_extract(a.data,'$.archiveInfo.completedCount') AS archiveCompleted
    ${where} ORDER BY ${order} ${ascending ? 'ASC' : 'DESC'}, ${name} ASC, a.id ASC LIMIT ? OFFSET ?`)
    .all(...parameters, limit, offset);
  const items = rows.map(row => ({
    attachment: { ...attachmentMetadata(JSON.parse(row.attachment), { diagnostics: repo.diagnostics }),
      hasExtractedText: !!row.hasText, hasAnalysis: !!row.hasAnalysis,
      hasPartialAnalysis: !!row.hasAnalysis && (row.archiveTotal > row.archiveCompleted
        || ['partial', 'paused', 'running'].includes(row.archiveStatus)) },
    source: JSON.parse(row.source),
  }));
  return { items, total, offset, limit, ...stats };
}
