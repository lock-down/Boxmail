import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { SearchIndex } from './search-index.js';
import { parseSearch, searchWhere } from './search-query.js';
import { draftSearchPage } from './draft-search.js';

export class Repository {
  constructor(directory) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.directory = directory;
    this.db = new DatabaseSync(path.join(directory, 'boxmail.sqlite'));
    chmodSync(path.join(directory, 'boxmail.sqlite'), 0o600);
    const version = this.db.prepare('PRAGMA user_version').get().user_version;
    if (version > 2) { this.db.close(); throw new Error('数据库版本较新，请使用更新版本的 Boxmail'); }
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(kind,id));
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, time TEXT NOT NULL, type TEXT NOT NULL, detail TEXT NOT NULL);
      `);
    if (version < 2) {
      if (this.db.prepare('SELECT COUNT(*) AS count FROM records').get().count) {
        const backups = path.join(directory, 'backups');
        mkdirSync(backups, { recursive: true, mode: 0o700 });
        const backup = path.join(backups, `before-v2-${randomUUID()}.sqlite`);
        this.db.exec(`VACUUM INTO '${backup.replaceAll("'", "''")}'`);
        chmodSync(backup, 0o600);
      }
      this.transaction(() => this.db.exec(`
        CREATE INDEX IF NOT EXISTS message_account_date ON records (
          json_extract(data,'$.accountId'), json_extract(data,'$.date') DESC, id
        ) WHERE kind='message';
        CREATE INDEX IF NOT EXISTS message_remote_uid ON records (
          json_extract(data,'$.accountId'), json_extract(data,'$.remotePath'), json_extract(data,'$.uid')
        ) WHERE kind='message';
        PRAGMA user_version=2;
      `));
    }
    this.searchIndex = new SearchIndex(this);
  }
  rebuildSearch() { return this.searchIndex.rebuild(); }
  list(kind) {
    return this.db
      .prepare('SELECT data FROM records WHERE kind=?')
      .all(kind)
      .map((r) => JSON.parse(r.data));
  }
  get(kind, id) {
    const r = this.db
      .prepare('SELECT data FROM records WHERE kind=? AND id=?')
      .get(kind, id);
    return r ? JSON.parse(r.data) : null;
  }
  put(kind, value) {
    this.db
      .prepare(
        'INSERT INTO records VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data',
      )
      .run(kind, value.id, JSON.stringify(value));
    return value;
  }
  remove(kind, id) {
    this.db.prepare('DELETE FROM records WHERE kind=? AND id=?').run(kind, id);
  }
  transaction(fn) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const r = fn();
      this.db.exec('COMMIT');
      return r;
    } catch (e) {
      this.db.exec('ROLLBACK');
      throw e;
    }
  }
  event(type, detail) {
    this.db
      .prepare('INSERT INTO events VALUES (?,?,?,?)')
      .run(randomUUID(), new Date().toISOString(), type, detail);
  }
  events() {
    return this.db
      .prepare('SELECT * FROM events ORDER BY time DESC LIMIT 100')
      .all();
  }
  search(query, accountId) {
    const drafts = draftSearchPage(this, { query, accountId, limit: Number.MAX_SAFE_INTEGER });
    if (drafts) return drafts.messages;
    const { where, params } = this.messageWhere({ query, accountId });
    return this.db.prepare(`SELECT m.data FROM records m WHERE ${where}
      ORDER BY json_extract(m.data,'$.date') DESC,m.id`).all(...params).map(row => JSON.parse(row.data));
  }
  messageWhere({ query = '', accountId, folder, filter } = {}) {
    const parsed = parseSearch(query);
    const { clauses, params } = searchWhere(parsed, { accountId, folder, filter, accounts: this.list('account') });
    const fullText = this.searchIndex.where(parsed.terms);
    if (fullText.clause) { clauses.push(fullText.clause); params.push(...fullText.params); }
    return { where: clauses.join(' AND '), params };
  }
  messageHeaders() {
    return this.db.prepare(`SELECT json_remove(data,'$.body','$.html','$.translation','$.translationHTML') AS data
      FROM records WHERE kind='message' ORDER BY json_extract(data,'$.date') DESC, id`)
      .all().map(row => ({ ...JSON.parse(row.data), body: '', bodyLoaded: false }));
  }
  attachmentHeaders() {
    return this.db.prepare(`SELECT json_remove(data,'$.text','$.analysis') AS data,
      length(json_extract(data,'$.text')) > 0 AS hasText,
      length(json_extract(data,'$.analysis')) > 0 AS hasAnalysis,
      substr(json_extract(data,'$.text'),1,160) AS textPreview,
      substr(json_extract(data,'$.analysis'),1,160) AS analysisPreview
      FROM records WHERE kind='attachment'`)
      .all().map(row => ({ ...JSON.parse(row.data), text: '', hasExtractedText: !!row.hasText, hasAnalysis: !!row.hasAnalysis,
        textPreview: row.textPreview || null, analysisPreview: row.analysisPreview || null }));
  }
  searchAttachmentIDs(query, accountId) {
    return this.db.prepare(`SELECT a.id FROM records a WHERE a.kind='attachment'
      AND instr(lower(coalesce(json_extract(a.data,'$.name'),'')||char(10)||
        coalesce(json_extract(a.data,'$.text'),'')||char(10)||coalesce(json_extract(a.data,'$.analysis'),'')),lower(?))>0
      AND EXISTS(SELECT 1 FROM records m WHERE m.kind='message'
        AND m.id=json_extract(a.data,'$.messageId') AND json_extract(m.data,'$.accountId')=?)`)
      .all(query.trim(), accountId).map(row => row.id);
  }
  messagePage({ accountId, folder, filter, query = '', offset = 0, limit = 100 }) {
    const drafts = draftSearchPage(this, { query, accountId, folder, filter, offset, limit });
    if (drafts) return drafts;
    const { where, params } = this.messageWhere({ accountId, folder, filter, query });
    const total = this.db.prepare(`SELECT COUNT(*) AS total FROM records m WHERE ${where}`).get(...params).total;
    const rows = this.db.prepare(`SELECT json_remove(m.data,'$.body','$.html','$.translation','$.translationHTML') AS data
      FROM records m WHERE ${where} ORDER BY json_extract(m.data,'$.date') DESC, m.id LIMIT ? OFFSET ?`)
      .all(...params, limit, offset);
    const firstTerm = parseSearch(query).terms[0];
    return { messages: rows.map(row => {
      const message = { ...JSON.parse(row.data), body: '', bodyLoaded: false };
      return firstTerm ? { ...message, searchSnippet: this.searchIndex.snippet(message.id, firstTerm) } : message;
    }),
      total, nextOffset: offset + rows.length < total ? offset + rows.length : null };
  }
  close() {
    this.db.close();
  }
}
