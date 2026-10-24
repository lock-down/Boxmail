import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { syncAccount } from '../src/mail.js';
import { ServiceError } from '../src/validation.js';

const token = 'boxmail-auto-sync-synthetic-session';
async function fixture(t, boxes = { INBOX: 2601, Sent: 201 }) {
  const state = { calls: [], sources: [], missing: false, failingFolder: null, bodyDelay: 0 };
  const clientFactory = () => {
    let selected, closed = false;
    return {
      mailbox: {}, async connect() {}, async logout() {}, close() { closed = true; },
      async list() { return Object.keys(boxes).map(folder => ({ path: folder,
        ...(folder === 'Sent' ? { specialUse: '\\Sent' } : {}) })); },
      async getMailboxLock(folder) {
        if (folder === state.failingFolder) throw new ServiceError('合成文件夹暂不可用', 502);
        selected = folder;
        this.mailbox = { path: folder, uidValidity: '10', exists: boxes[folder] };
        return { release() {} };
      },
      async status(folder) { return { messages: boxes[folder], uidValidity: '10' }; },
      async search() { return Array.from({ length: boxes[selected] }, (_, i) => i + 1); },
      async *fetch(page) { for (const uid of page) yield { uid, flags: new Set(), size: 200 }; },
      async fetchOne(uid) {
        if (state.bodyDelay) await delay(state.bodyDelay);
        if (closed || state.missing) return false;
        state.sources.push(`${selected}:${uid}`);
        return { uid, internalDate: new Date('2026-10-24T00:00:00Z'), source: Buffer.from(
          `From: Sender <sender@example.test>\r\nSubject: Mail ${uid}\r\nMessage-ID: <${selected}-${uid}@example.test>\r\n\r\nBody`) };
      },
    };
  };
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-auto-sync-'));
  const app = await startServer({ directory, token, demo: false,
    mailSync: (repo, account, password, options) => {
      state.calls.push({ accountId: account.id, folder: options.folder });
      return syncAccount(repo, account, password, { ...options, clientFactory });
    } });
  app.repo.put('account', { id: 'a1', email: 'reader@example.test', isDemo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: body ? 'POST' : 'GET', headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    return { status: response.status, body: await response.json() };
  };
  const waitFor = async predicate => {
    const deadline = Date.now() + 10000;
    while (Date.now() < deadline) {
      const snapshot = (await request('/sync-status')).body;
      if (predicate(snapshot)) return snapshot;
      await delay(5);
    }
    assert.fail('Synthetic synchronization did not reach its expected state');
  };
  const start = extra => request('/sync', { accountId: 'a1', password: 'synthetic', background: true, ...extra });
  return { ...app, state, request, waitFor, start };
}

test('one background request automatically downloads thousands of messages and every remaining folder', { timeout: 15000 }, async t => {
  const app = await fixture(t);
  assert.equal((await app.start()).status, 200);
  const snapshot = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(app.repo.list('message').length, 2802);
  assert.equal(snapshot.results[0].status, 'completed');
  assert.ok(snapshot.folders.every(folder => folder.status === 'completed' && !folder.hasMore && folder.remaining === 0));
  assert.equal(app.state.sources.length, 2802);
  assert.equal(new Set(app.state.sources).size, 2802);
  assert.ok(app.state.calls.length > 2);
});

test('a folder-specific request drains only that folder and leaves other unfinished checkpoints alone', async t => {
  const app = await fixture(t, { INBOX: 405, Sent: 50 });
  app.repo.put('sync', { id: 'other-checkpoint', accountId: 'a1', folder: 'sent', status: 'partial',
    downloaded: 0, total: 50, remaining: 50, hasMore: true });
  await app.start({ folder: 'inbox' });
  await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(app.repo.list('message').length, 405);
  assert.ok(app.repo.list('message').every(message => message.folder === 'inbox'));
  assert.ok(app.state.calls.every(call => call.folder === 'inbox'));
  assert.equal(app.repo.get('sync', 'other-checkpoint').remaining, 50);
});

test('no-progress downloads pause safely instead of completing or looping forever', async t => {
  const app = await fixture(t, { INBOX: 3 });
  app.state.missing = true;
  await app.start();
  const snapshot = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(snapshot.results[0].status, 'paused');
  assert.equal(app.state.calls.length, 1);
  assert.equal(snapshot.folders[0].remaining, 3);
  assert.equal(snapshot.folders[0].hasMore, true);
  assert.equal(snapshot.folders[0].status, 'paused');
  assert.match(snapshot.folders[0].lastError, /未返回|暂停/);
});

test('one failed folder still allows healthy folders to finish all automatic batches', async t => {
  const app = await fixture(t, { INBOX: 605, Sent: 5 });
  app.state.failingFolder = 'Sent';
  await app.start();
  const snapshot = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(snapshot.results[0].status, 'failed');
  assert.equal(app.repo.list('message').length, 605);
  assert.equal(snapshot.folders.find(folder => folder.folder === 'inbox').status, 'completed');
  assert.equal(snapshot.folders.find(folder => folder.folder === 'sent').status, 'failed');
});

test('stopping a session preserves its checkpoint, releases the lock and resumes without duplicate downloads', async t => {
  const app = await fixture(t, { INBOX: 405 });
  app.state.bodyDelay = 4;
  await app.start();
  await app.waitFor(value => value.folders.some(folder => folder.downloaded >= 3));
  assert.equal((await app.start()).status, 409);
  assert.equal((await app.request('/sync/cancel', { accountId: 'a1' })).status, 200);
  const paused = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(paused.results[0].status, 'paused');
  assert.ok(paused.folders[0].downloaded >= 3 && paused.folders[0].downloaded < 405);
  app.state.bodyDelay = 0;
  assert.equal((await app.start()).status, 200);
  const completed = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(completed.results[0].status, 'completed');
  assert.equal(app.repo.list('message').length, 405);
  assert.equal(new Set(app.state.sources).size, 405);
  assert.equal(app.state.sources.length, 405);
});

test('cancelling an unknown account fails without changing another running session', async t => {
  const app = await fixture(t, { INBOX: 5 });
  assert.equal((await app.request('/sync/cancel', { accountId: 'missing' })).status, 404);
  assert.equal((await app.request('/sync/cancel', { accountId: 'a1' })).status, 200);
});

test('stopping one account does not interrupt another account synchronizing in parallel', async t => {
  const app = await fixture(t, { INBOX: 25 });
  app.state.bodyDelay = 4;
  app.repo.put('account', { id: 'a2', email: 'second@example.test', isDemo: false });
  await app.start();
  await app.request('/sync', { accountId: 'a2', password: 'synthetic', background: true });
  await app.waitFor(value => value.folders.some(folder => folder.accountId === 'a1' && folder.downloaded >= 3));
  await app.request('/sync/cancel', { accountId: 'a1' });
  const snapshot = await app.waitFor(value => !value.runningAccounts.length);
  assert.equal(snapshot.results.find(result => result.accountId === 'a1').status, 'paused');
  assert.equal(snapshot.results.find(result => result.accountId === 'a2').status, 'completed');
  assert.equal(app.repo.list('message', { accountId: 'a2' }).length, 25);
  assert.ok(app.repo.list('message', { accountId: 'a1' }).length < 25);
});
