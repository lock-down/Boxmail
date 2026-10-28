import { textSlice } from './unicode.js';
import { mailPreviewText } from './mail-preview.js';

const normalize = text => String(text || '').normalize('NFKC').toLocaleLowerCase();
const INDEX_VERSION = 3;
function humanText(value) {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(humanText).filter(Boolean).join('\n');
  if (value && typeof value === 'object') return Object.entries(value)
    .filter(([key]) => !['id', 'draftId', 'messageId'].includes(key)).map(([, item]) => humanText(item)).filter(Boolean).join('\n');
  return '';
}
function grams(text) {
  const chars = Array.from(text), result = new Set();
  for (let i = 0; i + 1 < chars.length; i++)
    result.add(`g${chars[i].codePointAt(0).toString(16)}x${chars[i + 1].codePointAt(0).toString(16)}`);
  return [...result];
}

export class SearchIndex {
  constructor(repo) {
    this.repo = repo;
    const db = repo.db;
    db.exec(`CREATE VIRTUAL TABLE IF NOT EXISTS mail_fts USING fts5(message_id UNINDEXED, text UNINDEXED, grams, tokenize='ascii');
      CREATE TABLE IF NOT EXISTS search_dirty (message_id TEXT PRIMARY KEY);
      CREATE TABLE IF NOT EXISTS search_meta (id INTEGER PRIMARY KEY, version INTEGER, updated_at TEXT);
      CREATE TABLE IF NOT EXISTS search_documents (rowid INTEGER PRIMARY KEY, message_id TEXT NOT NULL UNIQUE);
      CREATE INDEX IF NOT EXISTS records_message_owner ON records(kind,json_extract(data,'$.messageId'));`);
    for (const [event, prefix] of [['INSERT', 'new'], ['DELETE', 'old'], ['UPDATE', 'new'], ['UPDATE', 'old']]) {
      db.exec(`CREATE TRIGGER IF NOT EXISTS search_${event.toLowerCase()}_${prefix} AFTER ${event} ON records
        WHEN ${prefix}.kind IN ('message','attachment','job') BEGIN
          INSERT INTO search_dirty(message_id)
          SELECT CASE WHEN ${prefix}.kind='message' THEN ${prefix}.id ELSE json_extract(${prefix}.data,'$.messageId') END
          WHERE CASE WHEN ${prefix}.kind='message' THEN ${prefix}.id ELSE json_extract(${prefix}.data,'$.messageId') END IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM search_dirty WHERE message_id=CASE WHEN ${prefix}.kind='message' THEN ${prefix}.id ELSE json_extract(${prefix}.data,'$.messageId') END);
        END;`);
    }
    if (db.prepare('SELECT version FROM search_meta WHERE id=1').get()?.version !== INDEX_VERSION) this.rebuild();
  }
  update(id) {
    const db = this.repo.db, message = this.repo.get('message', id);
    let key = db.prepare('SELECT rowid FROM search_documents WHERE message_id=?').get(id);
    if (key) db.prepare('DELETE FROM mail_fts WHERE rowid=?').run(key.rowid);
    if (message) {
      if (!key) {
        db.prepare('INSERT INTO search_documents(message_id) VALUES(?)').run(id);
        key = db.prepare('SELECT rowid FROM search_documents WHERE message_id=?').get(id);
      }
      const related = db.prepare("SELECT kind,data FROM records WHERE kind IN ('attachment','job') AND json_extract(data,'$.messageId')=?")
        .all(id).map(row => ({ kind: row.kind, value: JSON.parse(row.data) }));
      const text = normalize([message.subject, message.sender, message.senderEmail, message.to, message.cc,
        message.bcc, message.body, message.category, message.translation, humanText(message.summary),
        ...related.map(({ kind, value }) => kind === 'attachment' ? [value.name, value.text, value.analysis].join('\n')
          : humanText(value.result))].filter(Boolean).join('\n'));
      db.prepare('INSERT INTO mail_fts(rowid,message_id,text,grams) VALUES(?,?,?,?)').run(key.rowid, id, text, grams(text).join(' '));
    } else if (key) db.prepare('DELETE FROM search_documents WHERE rowid=?').run(key.rowid);
    db.prepare('DELETE FROM search_dirty WHERE message_id=?').run(id);
  }
  flush() {
    const pending = this.repo.db.prepare('SELECT message_id FROM search_dirty').all();
    if (!pending.length) return;
    this.repo.transaction(() => {
      for (const { message_id: id } of pending) this.update(id);
      this.repo.db.prepare('INSERT OR REPLACE INTO search_meta VALUES(1,?,?)').run(INDEX_VERSION, new Date().toISOString());
    });
  }
  rebuild() {
    this.repo.transaction(() => {
      this.repo.db.exec(`DELETE FROM mail_fts; DELETE FROM search_documents; DELETE FROM search_dirty;
        INSERT INTO search_dirty SELECT id FROM records WHERE kind='message';`);
      this.flush();
      this.repo.db.prepare('INSERT OR REPLACE INTO search_meta VALUES(1,?,?)').run(INDEX_VERSION, new Date().toISOString());
    });
    return this.status();
  }
  status() {
    const db = this.repo.db;
    return { indexed: db.prepare('SELECT COUNT(*) AS n FROM mail_fts').get().n,
      cached: db.prepare("SELECT COUNT(*) AS n FROM records WHERE kind='message'").get().n,
      pending: db.prepare('SELECT COUNT(*) AS n FROM search_dirty').get().n,
      updatedAt: db.prepare('SELECT updated_at FROM search_meta WHERE id=1').get()?.updated_at || null,
      partial: this.repo.list('sync').some(item => item.hasMore || item.remaining > 0), version: INDEX_VERSION };
  }
  snippet(id, term) {
    let text = this.repo.db.prepare('SELECT text FROM mail_fts WHERE rowid=(SELECT rowid FROM search_documents WHERE message_id=?)').get(id)?.text;
    if (!text) return undefined;
    let position = text.indexOf(normalize(term));
    if (position < 0) return undefined;
    const message = this.repo.get('message', id);
    if (message?.body) {
      const prefix = normalize([message.subject, message.sender, message.senderEmail, message.to, message.cc,
        message.bcc].filter(Boolean).join('\n'));
      const bodyStart = prefix ? prefix.length + 1 : 0;
      if (position >= bodyStart && position < bodyStart + normalize(message.body).length) {
        text = normalize(mailPreviewText(message));
        position = text.indexOf(normalize(term));
        if (position < 0) return undefined;
      }
    }
    const lineStart = text.lastIndexOf('\n', position) + 1;
    const lineEnd = text.indexOf('\n', position);
    const start = Math.max(lineStart, position - 35), end = Math.min(lineEnd < 0 ? text.length : lineEnd, position + 140);
    return `${start > lineStart ? '…' : ''}${textSlice(text, start, end).replace(/\s+/gu, ' ')}${end < (lineEnd < 0 ? text.length : lineEnd) ? '…' : ''}`;
  }
  where(terms) {
    if (!terms.length) return { clause: null, params: [] };
    this.flush();
    const normalized = terms.map(normalize);
    const tokens = [...new Set(normalized.flatMap(term => grams(term).slice(0, 16)))];
    const clauses = [], params = [];
    if (tokens.length) { clauses.push('mail_fts MATCH ?'); params.push(tokens.join(' AND ')); }
    for (const term of normalized) { clauses.push('instr(text,?)>0'); params.push(term); }
    return { clause: `m.id IN (SELECT message_id FROM mail_fts WHERE ${clauses.join(' AND ')})`, params };
  }
}
