import { unicodeJSON } from './unicode.js';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { SearchIndex } from './search-index.js';
import { parseSearch, searchWhere } from './search-query.js';
import { draftSearchPage, draftPreview } from './draft-search.js';
import { mailPreview } from './mail-preview.js';
import { senderMessagePage } from './sender-groups.js';
import { attachmentContentType, attachmentMetadata } from './attachment-metadata.js';

export class Repository {
  constructor(directory, { diagnostics } = {}) {
    this.diagnostics = diagnostics;
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
    this.db.exec(`CREATE INDEX IF NOT EXISTS message_identity ON records(
      json_extract(data,'$.accountId'),json_extract(data,'$.messageId')) WHERE kind='message'`);
    this.db.exec(`CREATE INDEX IF NOT EXISTS retained_identity ON records(kind,
      json_extract(data,'$.accountId'),json_extract(data,'$.original.messageId'));
      CREATE INDEX IF NOT EXISTS relocation_uid ON records(kind,json_extract(data,'$.accountId'),
      json_extract(data,'$.destination'),json_extract(data,'$.uidValidity'),json_extract(data,'$.destinationUID'));`);
    this.searchIndex = new SearchIndex(this);
    this.repairAttachmentMetadata();
  }
  repairAttachmentMetadata() {
    const invalid = [];
    // Scan only MIME metadata, not all attachment text and AI analysis. Repair
    // existing cached records transactionally before startup or backup reads.
    for (const row of this.db.prepare(`SELECT id,json_type(data,'$.contentType') AS type,
      json_extract(data,'$.contentType') AS value FROM records WHERE kind='attachment'`).iterate())
      if (row.type !== 'text' || attachmentContentType(row.value) !== row.value) invalid.push(row.id);
    for (let offset = 0; offset < invalid.length; offset += 100) this.transaction(() => {
      for (const id of invalid.slice(offset, offset + 100)) {
        const row = this.db.prepare("SELECT data FROM records WHERE kind='attachment' AND id=?").get(id);
        const repaired = attachmentMetadata(JSON.parse(row.data), { diagnostics: this.diagnostics, phase: 'migration' });
        this.db.prepare("UPDATE records SET data=json_set(data,'$.contentType',?) WHERE kind='attachment' AND id=?")
          .run(repaired.contentType, id);
      }
    });
    if (invalid.length) this.searchIndex.schedule();
    return invalid.length;
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
      .map((r) => kind === 'attachment' ? attachmentMetadata(JSON.parse(r.data), { diagnostics: this.diagnostics }) : JSON.parse(r.data));
  }
  get(kind, id) {
    const r = this.db
      .prepare('SELECT data FROM records WHERE kind=? AND id=?')
      .get(kind, id);
    if (!r) return null;
    const value = JSON.parse(r.data);
    return kind === 'attachment' ? attachmentMetadata(value, { diagnostics: this.diagnostics }) : value;
  }
  activeDrafts(accountId) {
    return this.db.prepare(`SELECT data FROM records WHERE kind='draft'
      AND coalesce(json_extract(data,'$.status'),'draft')!='sent'
      ${accountId === undefined ? '' : "AND json_extract(data,'$.accountId')=?"} ORDER BY id`)
      .all(...(accountId === undefined ? [] : [accountId])).map(row => JSON.parse(row.data));
  }
  draftHeaders() {
    const accounts = new Map(this.list('account').map(account => [account.id, account]));
    const rows = this.db.prepare(`SELECT json_set(json_remove(data,'$.forwardedText','$.forwardedHTML','$.preview'),
      '$.body','','$.bodyLoaded',json('false')) AS data,
      substr(coalesce(json_extract(data,'$.body'),''),1,8192) AS previewBody,
      substr(coalesce(json_extract(data,'$.forwardedText'),''),1,8192) AS previewForwarded
      FROM records WHERE kind='draft' AND coalesce(json_extract(data,'$.status'),'draft')!='sent' ORDER BY id`);
    const headers = [];
    for (const row of rows.iterate()) {
      const draft = JSON.parse(row.data);
      headers.push({ ...draft, preview: draftPreview({ body: row.previewBody, forwardedText: row.previewForwarded }, accounts.get(draft.accountId)) });
    }
    return headers;
  }
  localSentMessage(accountId, messageId) {
    const row = this.db.prepare(`SELECT data FROM records WHERE kind='message'
      AND json_extract(data,'$.accountId')=? AND json_extract(data,'$.messageId')=?
      AND id LIKE 'sent-%' ORDER BY id LIMIT 1`).get(accountId, messageId);
    return row ? JSON.parse(row.data) : null;
  }
  retainedMail(accountId, remotePath, validity, uid, messageId) {
    const exact = this.db.prepare(`SELECT data FROM records WHERE kind='relocation'
      AND json_extract(data,'$.accountId')=? AND json_extract(data,'$.destination')=?
      AND json_extract(data,'$.uidValidity')=? AND json_extract(data,'$.destinationUID')=? LIMIT 1`)
      .get(accountId, remotePath, validity, uid);
    if (exact) return { kind: 'relocation', value: JSON.parse(exact.data) };
    if (!messageId) return null;
    const find = (kind, extra = '', params = []) => this.db.prepare(`SELECT id FROM records WHERE kind=?
      AND json_extract(data,'$.accountId')=? AND json_extract(data,'$.original.messageId')=? ${extra} LIMIT 2`)
      .all(kind, accountId, messageId, ...params);
    const moved = find('relocation', `AND json_extract(data,'$.destination')=?
      AND (json_extract(data,'$.destinationUID') IS NULL OR json_extract(data,'$.uidValidity') IS NOT ?)`, [remotePath, validity]);
    if (moved.length === 1) return { kind: 'relocation', value: this.get('relocation', moved[0].id) };
    const same = find('recovery', "AND json_extract(data,'$.remotePath')=?", [remotePath]);
    const recovered = same.length === 1 ? same : find('recovery');
    return recovered.length === 1 ? { kind: 'recovery', value: this.get('recovery', recovered[0].id) } : null;
  }
  syncMessageHeaders(accountId, remotePath) {
    return this.db.prepare(`SELECT json_remove(data,'$.body','$.html','$.translation','$.translationHTML','$.summary') AS data
      FROM records WHERE kind='message' AND json_extract(data,'$.accountId')=?
      AND json_extract(data,'$.remotePath')=? ORDER BY id`).all(accountId, remotePath).map(row => JSON.parse(row.data));
  }
  jobHeaders() {
    // These results already live on the message/attachment and are loaded there.
    // Reply previews and reviewable workflows still need their complete results.
    return this.db.prepare(`SELECT CASE WHEN json_extract(data,'$.task') IN ('summary','translate','attachment')
      THEN json_remove(data,'$.result') ELSE data END AS data FROM records WHERE kind='job' ORDER BY id`)
      .all().map(row => JSON.parse(row.data));
  }
  put(kind, value) {
    if (kind === 'attachment') value = attachmentMetadata(value, { diagnostics: this.diagnostics, phase: 'persist' });
    const result = this.db
      .prepare(
        'INSERT INTO records VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data WHERE records.data<>excluded.data',
      )
      .run(kind, value.id, unicodeJSON(value, { recordKind: kind,
        ...(this.diagnostics ? { onInvalid: details => this.diagnostics.recordCoalesced('data.unicode.repaired',
          { ...details, phase: 'persist' }) } : {}) }));
    if (kind === 'message' && result.changes) this.previewCache?.delete(value.id);
    if (kind === 'sync' && result.changes) this.onSyncProgress?.(value);
    if (result.changes && ['message', 'attachment', 'job'].includes(kind)) this.searchIndex?.schedule();
    return value;
  }
  remove(kind, id) {
    this.db.prepare('DELETE FROM records WHERE kind=? AND id=?').run(kind, id);
    if (kind === 'message') this.previewCache?.delete(id);
    if (['message', 'attachment', 'job'].includes(kind)) this.searchIndex?.schedule();
  }
  invalidateMessagePreviews() {
    this.previewCache?.clear();
    // A rolled-back transaction can have cached uncommitted grouping metadata.
    this.senderPageSnapshot = null;
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
      this.invalidateMessagePreviews();
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
  messageHeaders(accountId, { previews = true } = {}) {
    return this.db.prepare(`SELECT json_remove(data,'$.body','$.html','$.translation','$.translationHTML') AS data
      FROM records WHERE kind='message'${accountId === undefined ? '' : " AND json_extract(data,'$.accountId')=?"}
      ORDER BY json_extract(data,'$.date') DESC, id`)
      .all(...(accountId === undefined ? [] : [accountId]))
      .map(row => this.messageHeader(JSON.parse(row.data), { previews }));
  }
  messageHeader(header, { previews = true } = {}) {
    // Only small derived strings are cached, never full bodies. A restored or
    // reopened database has a new handle, so it cannot reuse an old projection.
    if (this.previewDatabase !== this.db) {
      this.previewDatabase = this.db;
      this.previewCache = new Map();
    }
    if (previews && !this.previewCache.has(header.id)) {
      const source = typeof header.body === 'string' && header.bodyLoaded !== false
        ? header : this.get('message', header.id) || header;
      this.previewCache.set(header.id, mailPreview(source));
    }
    return { ...header, preview: this.previewCache.get(header.id) ?? '', body: '', bodyLoaded: false };
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
      .all().map(row => ({ ...attachmentMetadata(JSON.parse(row.data), { diagnostics: this.diagnostics }), text: '', hasExtractedText: !!row.hasText, hasAnalysis: !!row.hasAnalysis,
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
  messagePage({ accountId, folder, filter, query = '', offset = 0, limit = 100, groupBy, senderGroup, revealId }) {
    const drafts = draftSearchPage(this, { query, accountId, folder, filter, offset, limit });
    if (drafts) return drafts;
    if (groupBy === 'sender' || senderGroup)
      return senderMessagePage(this, { accountId, folder, filter, query, offset, limit, senderGroup, revealId });
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
    this.searchIndex.close();
    this.invalidateMessagePreviews();
    this.db.close();
  }
}
