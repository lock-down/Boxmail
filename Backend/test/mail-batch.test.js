import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { updateMessageBatch } from '../src/mail-batch.js';
import { updateMessage } from '../src/mail.js';

const token = 'boxmail-batch-test-session-0123456789';
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-batch-'));
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  for (const id of ['a1', 'a2']) app.repo.put('account', { id, isDemo: true, email: `${id}@example.test` });
  for (const [id, accountId, folder] of [['m1', 'a1', 'inbox'], ['m2', 'a2', 'sent']]) {
    app.repo.put('message', { id, accountId, folder, sender: 'Test', senderEmail: 'sender@example.test',
      to: 'a1@example.test', cc: '', subject: id, body: '正文', preview: '正文', date: '2026-10-24T00:00:00Z',
      category: '未分类', unread: true, starred: false, attachmentIds: [], uid: 1, remotePath: folder });
  }
  return { repo: app.repo, async request(updates) {
    const response = await fetch(`http://127.0.0.1:${app.port}/messages/batch`, { method: 'POST',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify({ updates }) });
    return { status: response.status, body: await response.json() };
  } };
}

test('batch archive and undo preserve each original folder across accounts and unrelated edits', async t => {
  const app = await fixture(t);
  const archived = await app.request(['m1', 'm2'].map(id => ({ id, changes: { folder: 'archive' } })));
  assert.equal(archived.status, 200);
  assert.equal(archived.body.changedCount, 2);
  assert.equal(app.repo.get('message', 'm2').archivedFromFolder, 'sent');
  updateMessage(app.repo, 'm1', { category: '工作项目' });
  const undone = await app.request(archived.body.undo);
  assert.equal(undone.status, 200);
  assert.equal(app.repo.get('message', 'm1').folder, 'inbox');
  assert.equal(app.repo.get('message', 'm2').folder, 'sent');
  assert.equal(app.repo.get('message', 'm1').category, '工作项目');
  assert.equal(app.repo.get('message', 'm2').archivedFromFolder, undefined);
});

test('invalid later updates roll back every message and pending remote mutation', async t => {
  const app = await fixture(t);
  const result = await app.request([{ id: 'm1', changes: { folder: 'archive' } },
    { id: 'm2', changes: { unread: false, folder: 'invalid-folder' } }]);
  assert.equal(result.status, 400);
  assert.equal(app.repo.get('message', 'm1').folder, 'inbox');
  assert.equal(app.repo.get('message', 'm2').unread, true);
  assert.deepEqual(app.repo.list('mutation'), []);
});

test('undo refuses stale fields atomically while preserving newer manual changes', async t => {
  const app = await fixture(t);
  const result = await app.request(['m1', 'm2'].map(id => ({ id, changes: { folder: 'archive' } })));
  updateMessage(app.repo, 'm2', { folder: 'trash' });
  const undone = await app.request(result.body.undo);
  assert.equal(undone.status, 409);
  assert.equal(app.repo.get('message', 'm1').folder, 'archive');
  assert.equal(app.repo.get('message', 'm2').folder, 'trash');
});

test('batch state changes provide exact undo and omit messages whose state already matches', async t => {
  const app = await fixture(t);
  updateMessage(app.repo, 'm1', { unread: false });
  const result = await app.request(['m1', 'm2'].map(id => ({ id, changes: { unread: false, starred: true } })));
  assert.equal(result.status, 200);
  assert.deepEqual(result.body.undo[0].changes, { starred: false });
  assert.deepEqual(result.body.undo[1].changes, { unread: true, starred: false });
  assert.equal((await app.request(result.body.undo)).status, 200);
  assert.equal(app.repo.get('message', 'm1').unread, false);
  assert.equal(app.repo.get('message', 'm2').unread, true);
  assert.equal(app.repo.get('message', 'm2').starred, false);
  const pending = app.repo.list('mutation');
  assert.deepEqual((await app.request([{ id: 'm1', changes: { unread: false } }])).body,
    { changedCount: 0, undo: [] });
  assert.deepEqual(app.repo.list('mutation'), pending);
});

test('missing messages, duplicate selections, and locked accounts cannot partly apply a batch', async t => {
  const app = await fixture(t);
  const first = { id: 'm1', changes: { folder: 'trash' } };
  assert.equal((await app.request([first, { id: 'missing', changes: { unread: false } }])).status, 409);
  assert.equal((await app.request([first, first])).status, 400);
  assert.throws(() => updateMessageBatch(app.repo, { updates: [first,
    { id: 'm2', changes: { folder: 'trash' } }] }, new Set(['a2'])), /正在同步/);
  assert.equal(app.repo.get('message', 'm1').folder, 'inbox');
  assert.deepEqual(app.repo.list('mutation'), []);
});
