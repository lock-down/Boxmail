import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync } from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

export class Repository {
  constructor(directory) {
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.directory = directory;
    this.db = new DatabaseSync(path.join(directory, 'boxmail.sqlite'));
    chmodSync(path.join(directory, 'boxmail.sqlite'), 0o600);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
      CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(kind,id));
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, time TEXT NOT NULL, type TEXT NOT NULL, detail TEXT NOT NULL);
      PRAGMA user_version=1;`);
  }
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
    const q = query.trim().toLocaleLowerCase();
    const attachmentIDs = new Set(
      this.list('attachment')
        .filter((a) =>
          `${a.name}\n${a.text || ''}\n${a.analysis || ''}`
            .toLocaleLowerCase()
            .includes(q),
        )
        .map((a) => a.messageId),
    );
    return this.list('message')
      .filter(
        (m) =>
          (!accountId || m.accountId === accountId) &&
          (!q ||
            `${m.subject}\n${m.sender}\n${m.senderEmail}\n${m.body}\n${m.category}\n${JSON.stringify(m.summary || '')}`
              .toLocaleLowerCase()
              .includes(q) ||
            attachmentIDs.has(m.id)),
      )
      .sort((a, b) => b.date.localeCompare(a.date));
  }
  close() {
    this.db.close();
  }
}
