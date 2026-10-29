import { textSlice } from './unicode.js';
import { mailPreviewText } from './mail-preview.js';

const normalize = text => String(text || '').normalize('NFKC').toLocaleLowerCase();
const INDEX_VERSION = 4;
export const MAX_INDEX_TEXT = 262144;
function humanText(value) {
  if (typeof value === 'string' || typeof value === 'number') return String(value);
  if (Array.isArray(value)) return value.map(humanText).filter(Boolean).join('\n');
  if (value && typeof value === 'object') return Object.entries(value)
    .filter(([key]) => !['id', 'draftId', 'messageId'].includes(key)).map(([, item]) => humanText(item)).filter(Boolean).join('\n');
  return '';
}
function grams(text, limit = Infinity) {
  const result = new Set();
  let previous;
  for (const char of text) {
    if (previous !== undefined) result.add(`g${previous.toString(16)}x${char.codePointAt(0).toString(16)}`);
    if (result.size >= limit) break;
    previous = char.codePointAt(0);
  }
  return [...result];
}

export class SearchIndex {
  constructor(repo) {
    this.repo = repo;
    const db = repo.db;
    db.exec(`CREATE VIRTUAL TABLE IF NOT EXISTS mail_fts USING fts5(message_id UNINDEXED, text UNINDEXED, grams, tokenize='ascii');
      CREATE TABLE IF NOT EXISTS search_dirty (message_id TEXT PRIMARY KEY);
      CREATE TABLE IF NOT EXISTS search_failures (message_id TEXT PRIMARY KEY);
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
    else this.schedule();
  }
  message(id) {
    const row = this.repo.db.prepare(`SELECT json_object('id',id,
      'subject',substr(json_extract(data,'$.subject'),1,65536),
      'sender',substr(json_extract(data,'$.sender'),1,8192),
      'senderEmail',substr(json_extract(data,'$.senderEmail'),1,8192),
      'to',substr(json_extract(data,'$.to'),1,8192),
      'cc',substr(json_extract(data,'$.cc'),1,8192),
      'bcc',substr(json_extract(data,'$.bcc'),1,8192),
      'category',substr(json_extract(data,'$.category'),1,4096),
      'html',substr(json_extract(data,'$.html'),1,?),
      'body',substr(coalesce(json_extract(data,'$.body'),''),1,?),
      'translation',substr(coalesce(json_extract(data,'$.translation'),''),1,65536),
      'summary',json(CASE WHEN length(json_extract(data,'$.summary'))<=65536
        THEN coalesce(json_extract(data,'$.summary'),'null') ELSE 'null' END)) AS data
      FROM records WHERE kind='message' AND id=?`).get(MAX_INDEX_TEXT, MAX_INDEX_TEXT, id);
    return row ? JSON.parse(row.data) : null;
  }
  update(id) {
    const db = this.repo.db, message = this.message(id);
    let key = db.prepare('SELECT rowid FROM search_documents WHERE message_id=?').get(id);
    if (key) db.prepare('DELETE FROM mail_fts WHERE rowid=?').run(key.rowid);
    if (message) {
      if (!key) {
        db.prepare('INSERT INTO search_documents(message_id) VALUES(?)').run(id);
        key = db.prepare('SELECT rowid FROM search_documents WHERE message_id=?').get(id);
      }
      let text = [message.subject, message.sender, message.senderEmail, message.to, message.cc,
        message.bcc, message.body, message.category, message.translation, humanText(message.summary),
      ].filter(Boolean).join('\n');
      const related = db.prepare(`SELECT kind,CASE WHEN kind='attachment' THEN
        substr(coalesce(json_extract(data,'$.name'),'')||char(10)||coalesce(json_extract(data,'$.text'),'')
          ||char(10)||coalesce(json_extract(data,'$.analysis'),''),1,65536)
        ELSE CASE WHEN length(json_extract(data,'$.result'))<=65536 THEN json_extract(data,'$.result') END END AS text
        FROM records WHERE kind IN ('attachment','job') AND json_extract(data,'$.messageId')=?`);
      for (const row of related.iterate(id)) {
        if (text.length >= MAX_INDEX_TEXT) break;
        text += '\n' + (row.kind === 'attachment' ? row.text || '' : humanText(row.text ? JSON.parse(row.text) : null));
      }
      text = textSlice(normalize(textSlice(text, 0, MAX_INDEX_TEXT)), 0, MAX_INDEX_TEXT);
      db.prepare('INSERT INTO mail_fts(rowid,message_id,text,grams) VALUES(?,?,?,?)').run(key.rowid, id, text, grams(text).join(' '));
    } else if (key) db.prepare('DELETE FROM search_documents WHERE rowid=?').run(key.rowid);
    db.prepare('DELETE FROM search_dirty WHERE message_id=?').run(id);
    db.prepare('DELETE FROM search_failures WHERE message_id=?').run(id);
  }
  flush({ limit = 20 } = {}) {
    const db = this.repo.db;
    const pending = db.prepare('SELECT message_id FROM search_dirty LIMIT ?').all(limit);
    for (const { message_id: id } of pending) {
      try { this.repo.transaction(() => this.update(id)); }
      catch {
        // A bad document cannot roll back its neighbours or poison every search.
        this.repo.transaction(() => {
          db.prepare('DELETE FROM mail_fts WHERE message_id=?').run(id);
          db.prepare('DELETE FROM search_dirty WHERE message_id=?').run(id);
          db.prepare('INSERT OR IGNORE INTO search_failures VALUES(?)').run(id);
        });
        this.repo.event('search', '一封邮件的搜索索引未完成，已跳过；可在设置中重建索引。');
      }
    }
    if (pending.length)
      this.repo.db.prepare('INSERT OR REPLACE INTO search_meta VALUES(1,?,?)').run(INDEX_VERSION, new Date().toISOString());
    return pending.length;
  }
  schedule() {
    if (this.closed || this.timer) return;
    this.timer = setImmediate(() => {
      this.timer = null;
      if (this.closed) return;
      if (this.repo.db.isTransaction) { this.schedule(); return; }
      try { if (this.flush({ limit: 1 })) this.schedule(); }
      catch {
        // Database I/O failure must not become an unhandled background exception.
        // Dirty markers remain durable; retry later without a tight failure loop.
        clearTimeout(this.retryTimer);
        this.retryTimer = setTimeout(() => { this.retryTimer = null; this.schedule(); }, 30000);
        this.retryTimer.unref();
      }
    });
    this.timer.unref();
  }
  async drain() {
    while (!this.closed && this.repo.db.prepare('SELECT 1 FROM search_dirty LIMIT 1').get()) {
      await new Promise(resolve => setImmediate(resolve));
      if (!this.closed) this.flush({ limit: 1 });
    }
    return this.status();
  }
  close() {
    this.closed = true;
    clearImmediate(this.timer);
    clearTimeout(this.retryTimer);
  }
  rebuild() {
    this.repo.transaction(() => {
      this.repo.db.exec(`DELETE FROM mail_fts; DELETE FROM search_documents; DELETE FROM search_dirty; DELETE FROM search_failures;
        INSERT INTO search_dirty SELECT id FROM records WHERE kind='message';`);
      this.repo.db.prepare('INSERT OR REPLACE INTO search_meta VALUES(1,?,?)').run(INDEX_VERSION, new Date().toISOString());
    });
    this.schedule();
    return this.status();
  }
  status() {
    const db = this.repo.db;
    return { indexed: db.prepare('SELECT COUNT(*) AS n FROM mail_fts').get().n,
      cached: db.prepare("SELECT COUNT(*) AS n FROM records WHERE kind='message'").get().n,
      pending: db.prepare('SELECT COUNT(*) AS n FROM search_dirty').get().n,
      failed: db.prepare('SELECT COUNT(*) AS n FROM search_failures').get().n,
      updatedAt: db.prepare('SELECT updated_at FROM search_meta WHERE id=1').get()?.updated_at || null,
      partial: this.repo.list('sync').some(item => item.hasMore || item.remaining > 0), version: INDEX_VERSION };
  }
  snippet(id, term) {
    let text = this.repo.db.prepare('SELECT text FROM mail_fts WHERE rowid=(SELECT rowid FROM search_documents WHERE message_id=?)').get(id)?.text;
    if (!text) return undefined;
    let position = text.indexOf(normalize(term));
    if (position < 0) return undefined;
    const message = this.message(id);
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
    const normalized = terms.map(normalize);
    const tokens = [...new Set(normalized.flatMap(term => grams(term, 16)))];
    const clauses = ['message_id NOT IN (SELECT message_id FROM search_dirty)'], params = [];
    if (tokens.length) { clauses.push('mail_fts MATCH ?'); params.push(tokens.join(' AND ')); }
    for (const term of normalized) { clauses.push('instr(text,?)>0'); params.push(term); }
    return { clause: `m.id IN (SELECT message_id FROM mail_fts WHERE ${clauses.join(' AND ')})`, params };
  }
}
