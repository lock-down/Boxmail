import { parseSearch } from './search-query.js';

function identity(row) {
  const address = (row.senderEmail || '').trim().toLowerCase();
  return JSON.stringify([row.accountId, address, address ? null : row.id]);
}

function newestFirst(a, b) {
  return b.timestamp - a.timestamp
    || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

function senderSnapshot(repo, where, params) {
  const key = JSON.stringify([where, params]);
  const revision = repo.db.prepare('SELECT total_changes() AS revision').get().revision;
  const dataVersion = repo.db.prepare('PRAGMA data_version').get().data_version;
  const cached = repo.senderPageSnapshot;
  if (cached?.database === repo.db && cached.key === key && cached.revision === revision
    && cached.dataVersion === dataVersion) return cached;
  const metadata = repo.db.prepare(`SELECT m.id,
    json_extract(m.data,'$.accountId') AS accountId,
    coalesce(json_extract(m.data,'$.senderEmail'),'') AS senderEmail,
    json_extract(m.data,'$.date') AS date,
    json_extract(m.data,'$.unread') AS unread
    FROM records m WHERE ${where}`).all(...params)
    .map(row => ({ ...row, timestamp: Date.parse(row.date) || 0 })).sort(newestFirst);
  const groups = new Map();
  for (const row of metadata) {
    const id = identity(row);
    if (!groups.has(id)) groups.set(id, { id, accountId: row.accountId,
      senderEmail: row.senderEmail.trim().toLowerCase(), latestMessageId: row.id,
      count: 0, unreadCount: 0, members: [] });
    const group = groups.get(id);
    group.count++;
    if (row.unread === 1) group.unreadCount++;
    group.members.push(row);
  }
  // Keep one metadata-only query snapshot, independent of page/member offsets.
  // SQLite revisions also catch direct SQL writes and backup restoration.
  return repo.senderPageSnapshot = { database: repo.db, key, revision, dataVersion, metadata, groups };
}

// Group over all matching metadata, then project only the requested mail headers.
// A large newsletter must not consume every slot before another sender can appear.
export function senderMessagePage(repo, { accountId, folder, filter, query = '', offset = 0,
  limit = 100, senderGroup, revealId } = {}) {
  const { where, params } = repo.messageWhere({ accountId, folder, filter, query });
  const { metadata, groups } = senderSnapshot(repo, where, params);
  const firstTerm = parseSearch(query).terms[0];
  const header = repo.db.prepare(`SELECT json_remove(data,'$.body','$.html','$.translation','$.translationHTML') AS data
    FROM records WHERE kind='message' AND id=?`);
  const project = row => {
    const message = repo.messageHeader(JSON.parse(header.get(row.id).data));
    return firstTerm ? { ...message, searchSnippet: repo.searchIndex.snippet(message.id, firstTerm) } : message;
  };
  if (senderGroup) {
    const members = groups.get(senderGroup)?.members || [];
    const rows = members.slice(offset, offset + limit);
    return { messages: rows.map(project), total: members.length,
      nextOffset: offset + rows.length < members.length ? offset + rows.length : null };
  }
  const allGroups = [...groups.values()];
  const page = allGroups.slice(offset, offset + limit);
  const anchor = revealId ? metadata.find(row => row.id === revealId) : null;
  if (anchor && !page.some(group => group.id === identity(anchor))) {
    page.push(groups.get(identity(anchor)));
    page.sort((a, b) => newestFirst(a.members[0], b.members[0]));
  }
  const latest = page.map(group => group.members[0]);
  const messages = latest.map(project);
  return { messages, total: metadata.length,
    senderGroups: page.map(({ members, ...group }) => group), groupTotal: groups.size,
    revealedMessage: anchor ? messages.find(message => message.id === anchor.id) || project(anchor) : null,
    nextOffset: offset + Math.min(limit, Math.max(0, allGroups.length - offset)) < allGroups.length
      ? offset + limit : null };
}
