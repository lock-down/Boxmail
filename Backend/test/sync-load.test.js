import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { startServer } from '../src/server.js';
import { syncAccount } from '../src/mail.js';
import { syncSession } from '../src/sync-session.js';
import { Repository } from '../src/database.js';
import { MailContentWorker } from '../src/mail-content-worker.js';

const token = 'synthetic-multi-account-sync-token';
async function service(t, options) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-sync-load-'));
  const app = await startServer({ directory, token, demo: false, ...options });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      method: body ? 'POST' : 'GET', ...(body ? { body: JSON.stringify(body) } : {}),
      signal: AbortSignal.timeout(1000),
    });
    return { status: response.status, ...await response.json() };
  };
  const wait = async predicate => {
    for (let i = 0; i < 1200; i++) {
      const snapshot = await request('/sync-status');
      if (predicate(snapshot)) return snapshot;
      await delay(5);
    }
    assert.fail('Synchronization did not settle');
  };
  for (let i = 1; i <= 6; i++) app.repo.put('account', { id: `a${i}`, email: `private-${i}@example.test` });
  return { ...app, directory, request, wait };
}

test('six-account starts acknowledge promptly, bound work to two, and allow queued cancellation', async t => {
  let active = 0, peak = 0;
  const releases = new Map(), visited = [];
  const app = await service(t, { mailSync: async (repo, account, password, { signal }) => {
    visited.push(account.id); active++; peak = Math.max(peak, active);
    try {
      await new Promise((resolve, reject) => {
        releases.set(account.id, resolve);
        signal.addEventListener('abort', () => reject(signal.reason), { once: true });
      });
      return { count: 0 };
    } finally { active--; }
  } });
  const starts = await Promise.all(Array.from({ length: 6 }, (_, i) => app.request('/sync',
    { accountId: `a${i + 1}`, password: 'private-password', background: true })));
  assert.ok(starts.every(result => result.ok));
  const snapshot = await app.request('/sync-status');
  assert.equal(snapshot.runningAccounts.length, 6);
  assert.equal(snapshot.results.filter(result => result.status === 'queued').length, 4);
  assert.equal(peak, 2);
  assert.equal((await app.request('/health')).status, 200);
  await app.request('/sync/cancel', { accountId: 'a6' });
  await app.wait(value => value.results.find(item => item.accountId === 'a6')?.status === 'paused');
  assert.equal(visited.includes('a6'), false);
  for (const id of ['a1', 'a2', 'a3', 'a4', 'a5']) {
    await app.wait(() => releases.has(id)); releases.get(id)();
  }
  const complete = await app.wait(value => !value.runningAccounts.length);
  assert.equal(complete.results.filter(result => result.status === 'completed').length, 5);
  assert.equal(peak, 2);
  assert.equal((await app.request('/sync', { accountId: 'a6', password: 'private-password', background: true })).status, 'running');
  await app.wait(() => releases.has('a6')); releases.get('a6')();
  await app.wait(value => !value.runningAccounts.length);
});

test('a stalled account fails with a finite deadline, releases its lock, and preserves another account', async t => {
  let hang = true;
  const app = await service(t, { syncStallTimeoutMs: 40,
    mailSync: async (repo, account, password, { signal }) => {
      if (account.id === 'a1' && hang) await new Promise((resolve, reject) =>
        signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
      return { count: 0 };
    } });
  await app.request('/sync', { accountId: 'a1', password: 'secret-token', background: true });
  await app.request('/sync', { accountId: 'a2', password: 'secret-token', background: true });
  const snapshot = await app.wait(value => !value.runningAccounts.length);
  assert.equal(snapshot.results.find(item => item.accountId === 'a1').status, 'failed');
  assert.match(snapshot.results.find(item => item.accountId === 'a1').error, /长时间没有进展/);
  assert.equal(snapshot.results.find(item => item.accountId === 'a2').status, 'completed');
  hang = false;
  await app.request('/sync', { accountId: 'a1', password: 'secret-token', background: true });
  await app.wait(value => !value.runningAccounts.length);
  await app.repo.diagnostics.flush();
  const log = await readFile(path.join(app.directory, 'logs/backend.jsonl'), 'utf8');
  assert.match(log, /sync.stalled/);
  for (const secret of ['secret-token', 'private-1', 'example.test']) assert.equal(log.includes(secret), false);
});

test('large history reuses validated inventory and light cached headers only within one session', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-sync-inventory-load-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a1', email: 'synthetic@example.test' }; repo.put('account', account);
  let size = 1001, searches = 0, metadata = 0;
  const clientFactory = () => ({
    mailbox: { uidValidity: '1', path: 'INBOX' }, async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }]; }, async getMailboxLock() { return { release() {} }; },
    async status() { return { messages: size, uidValidity: '1' }; },
    async search() { searches++; return Array.from({ length: size }, (_, i) => i + 1); },
    async *fetch(page) { for (const uid of page) { metadata++; yield { uid, flags: new Set(), size: 100 }; } },
    async fetchOne(uid) { return { uid, source: Buffer.from(`From: sender@example.test\r\nSubject: ${uid}\r\n\r\nBody`) }; },
  });
  const batch = (r, a, p, options) => syncAccount(r, a, p, { ...options, clientFactory });
  await syncSession(repo, account, 'synthetic', { syncBatch: batch });
  assert.equal(repo.list('message').length, 1001);
  assert.equal(searches, 1); assert.equal(metadata, 1001);
  size = 1002;
  await syncSession(repo, account, 'synthetic', { syncBatch: batch });
  assert.equal(searches, 2); assert.equal(repo.list('message').length, 1002);
  size = 1203;
  let passes = 0;
  await syncSession(repo, account, 'synthetic', { syncBatch: (r, a, p, options) => {
    if (++passes === 2) size = 1204;
    return batch(r, a, p, options);
  } });
  assert.equal(searches, 4, 'mailbox count changes invalidate the session snapshot');
  assert.equal(repo.list('message').length, 1204);
});

test('six large accounts keep status responsive while one server times out and all healthy history finishes', { timeout: 20000 }, async t => {
  const size = 1001, downloads = new Map();
  let broken = true;
  const app = await service(t, { mailSync: (repo, account, password, options) => syncAccount(repo, account, password, {
    ...options, operationTimeoutMs: 30,
    clientFactory: () => ({
      mailbox: { path: 'INBOX', uidValidity: '1' }, async connect() {}, async logout() {}, close() {},
      async list() { return [{ path: 'INBOX' }]; }, async getMailboxLock() { return { release() {} }; },
      async status() { return { messages: size, uidValidity: '1' }; },
      async search() { return Array.from({ length: size }, (_, i) => i + 1); },
      async *fetch(page) { for (const uid of page) yield { uid, flags: new Set(), size: 120 }; },
      async fetchOne(uid) {
        if (broken && account.id === 'a1' && uid < size - 2) return new Promise(() => {});
        const key = `${account.id}:${uid}`; downloads.set(key, (downloads.get(key) || 0) + 1);
        return { uid, source: Buffer.from(`From: sender@example.test\r\nSubject: ${uid}\r\n\r\nBody`) };
      },
    }),
  }) });
  await Promise.all(Array.from({ length: 6 }, (_, i) => app.request('/sync',
    { accountId: `a${i + 1}`, password: 'synthetic', background: true })));
  const complete = await app.wait(value => !value.runningAccounts.length);
  assert.equal(complete.results.find(result => result.accountId === 'a1').status, 'paused');
  assert.equal(complete.results.filter(result => result.status === 'completed').length, 5);
  assert.equal(app.repo.list('message').length, size * 5 + 3);
  broken = false;
  await app.request('/sync', { accountId: 'a1', password: 'synthetic', background: true });
  await app.wait(value => !value.runningAccounts.length);
  assert.equal(app.repo.list('message').length, size * 6);
  assert.ok([...downloads.values()].every(count => count === 1));
});

test('parsing deadlines terminate their worker and a subsequent message can use a clean worker', async () => {
  const worker = new MailContentWorker({ timeoutMs: 1 });
  await assert.rejects(worker.run('mime', Buffer.from('Subject: Synthetic\r\n\r\nBody')), /解析超时/);
  assert.equal(worker.worker, null);
  worker.timeoutMs = 3000;
  try {
    const result = await worker.run('mime', Buffer.from('Subject: Synthetic\r\nContent-Type: text/plain\r\n\r\nBody'));
    assert.equal(result.content.body.trim(), 'Body');
  } finally { await worker.close(); }
});

test('UIDNEXT validates long sessions and detects replacement mail even when the folder count is unchanged', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-sync-revision-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a1', email: 'synthetic@example.test' }; repo.put('account', account);
  let uids = [1, 2, 3], uidNext = 4, searches = 0;
  const clientFactory = () => ({
    mailbox: { path: 'INBOX', uidValidity: '1' }, async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }]; }, async getMailboxLock() { return { release() {} }; },
    async status() { return { messages: uids.length, uidValidity: '1', uidNext }; },
    async search() { searches++; return [...uids]; },
    async *fetch(page) { for (const uid of page) yield { uid, size: 100, flags: new Set() }; },
    async fetchOne(uid) { return { uid, source: Buffer.from(`Subject: ${uid}\r\n\r\nBody`) }; },
  });
  let passes = 0;
  const batch = async (r, a, p, options) => {
    const result = await syncAccount(r, a, p, { ...options, clientFactory, batchSize: 1 });
    if (++passes === 1) { uids = [1, 2, 4]; uidNext = 5; }
    for (const entry of options.inventories.values()) entry.createdAt = performance.now() - 61000;
    return result;
  };
  await syncSession(repo, account, 'synthetic', { syncBatch: batch });
  assert.deepEqual(repo.list('message').map(message => message.uid).sort(), [1, 2, 4]);
  assert.equal(repo.list('recovery').length, 1);
  assert.equal(searches, 2, 'stable UIDNEXT reuses an older snapshot, a changed revision refreshes it');
});

test('cancelling active MIME parsing terminates CPU work and preserves cancellation reason', async () => {
  const controller = new AbortController(), worker = new MailContentWorker({ signal: controller.signal });
  const pending = worker.run('mime', Buffer.alloc(2 * 1024 * 1024, 97));
  controller.abort(new Error('synthetic cancellation'));
  await assert.rejects(pending, /synthetic cancellation/);
  assert.equal(worker.worker, null);
});
