import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { SearchIndex } from './search-index.js';
import { parseSearch, searchWhere } from './search-query.js';
import { draftSearchPage } from './draft-search.js';
import { mailPreview } from './mail-preview.js';

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
    this.db.exec("CREATE INDEX IF NOT EXISTS records_account ON records(kind,json_extract(data,'$.accountId'))");
    this.searchIndex = new SearchIndex(this);
  }
  rebuildSearch() { return this.searchIndex.rebuild(); }
  list(kind, { accountId, remotePath, messageId } = {}) {
    const clauses = ['kind=?'], params = [kind];
    for (const [field, value] of Object.entries({ accountId, remotePath, messageId })) {
      if (value === undefined) continue;
      clauses.push(`json_extract(data,'$.${field}')=?`);
      params.push(value);
    }
    return this.db
      .prepare(`SELECT data FROM records WHERE ${clauses.join(' AND ')} ORDER BY id`)
      .all(...params)
      .map((r) => JSON.parse(r.data));
  }
  get(kind, id) {
    const r = this.db
      .prepare('SELECT data FROM records WHERE kind=? AND id=?')
      .get(kind, id);
    return r ? JSON.parse(r.data) : null;
  }
  put(kind, value) {
    const result = this.db
      .prepare(
        'INSERT INTO records VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data WHERE records.data<>excluded.data',
      )
      .run(kind, value.id, JSON.stringify(value));
    if (kind === 'message' && result.changes) this.previewCache?.delete(value.id);
    return value;
  }
  remove(kind, id) {
    this.db.prepare('DELETE FROM records WHERE kind=? AND id=?').run(kind, id);
    if (kind === 'message') this.previewCache?.delete(id);
  }
  transaction(fn) {
    const savepoint = this.db.isTransaction ? `boxmail_${randomUUID().replaceAll('-', '')}` : null;
    this.db.exec(savepoint ? `SAVEPOINT ${savepoint}` : 'BEGIN IMMEDIATE');
    try {
      const r = fn();
      this.db.exec(savepoint ? `RELEASE SAVEPOINT ${savepoint}` : 'COMMIT');
      return r;
    } catch (e) {
      this.db.exec(savepoint ? `ROLLBACK TO SAVEPOINT ${savepoint}; RELEASE SAVEPOINT ${savepoint}` : 'ROLLBACK');
      this.previewCache?.clear();
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
  messageHeaders(accountId) {
    return this.db.prepare(`SELECT json_remove(data,'$.body','$.html','$.translation','$.translationHTML') AS data
      FROM records WHERE kind='message'${accountId === undefined ? '' : " AND json_extract(data,'$.accountId')=?"}
      ORDER BY json_extract(data,'$.date') DESC, id`)
      .all(...(accountId === undefined ? [] : [accountId]))
      .map(row => this.messageHeader(JSON.parse(row.data)));
  }
  messageHeader(header) {
    // Only small derived strings are cached, never full bodies. A restored or
    // reopened database has a new handle, so it cannot reuse an old projection.
    if (this.previewDatabase !== this.db) {
      this.previewDatabase = this.db;
      this.previewCache = new Map();
    }
    if (!this.previewCache.has(header.id))
      this.previewCache.set(header.id, mailPreview(this.get('message', header.id) || header));
    return { ...header, preview: this.previewCache.get(header.id), body: '', bodyLoaded: false };
  }
  contactHeaders(accountId) {
    return this.db.prepare(`SELECT json_extract(data,'$.senderEmail') AS senderEmail,
      json_extract(data,'$.sender') AS sender, json_extract(data,'$.to') AS "to",
      json_extract(data,'$.cc') AS cc, json_extract(data,'$.bcc') AS bcc,
      json_extract(data,'$.replyTo') AS replyTo,
      coalesce(nullif(json_extract(data,'$.date'),''),json_extract(data,'$.updatedAt'),'') AS date
      FROM records WHERE kind IN ('message','draft') AND json_extract(data,'$.accountId')=?
      AND (kind='draft' OR coalesce(json_extract(data,'$.folder'),'') NOT IN ('trash','spam'))
      ORDER BY kind DESC,CASE WHEN kind='message' THEN json_extract(data,'$.date') END DESC,id`).all(accountId);
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
      const message = this.messageHeader(JSON.parse(row.data));
      return firstTerm ? { ...message, searchSnippet: this.searchIndex.snippet(message.id, firstTerm) } : message;
    }),
      total, nextOffset: offset + rows.length < total ? offset + rows.length : null };
  }
  close() {
    this.previewCache?.clear();
    this.db.close();
  }
}
