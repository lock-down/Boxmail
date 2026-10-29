import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';

const token = 'summary-overview-session-0123456789';
const summary = { overview: '项目评审摘要', points: ['核对预算'], todos: [{ id: 't1', title: '确认排期', due: '10 月 31 日', done: false }],
  keyInfo: [{ label: '预算', value: '128,000 元' }], nextSteps: [] };
function mail(id, accountId = 'a1', folder = 'inbox') {
  return { id, accountId, folder, sender: 'Test', senderEmail: 'sender@example.test', to: 'me@example.test', cc: '',
    subject: '评审 ' + id, body: '邮件原文 ' + id, html: '<p>邮件原文</p>', preview: '评审', date: '2026-10-23T00:00:00Z',
    category: '工作项目', unread: true, starred: false, attachmentIds: [], summary: structuredClone(summary) };
}
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-summary-overview-'));
  let app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  for (const id of ['a1', 'a2']) app.repo.put('account', { id, isDemo: true });
  app.repo.put('message', mail('m1')); app.repo.put('message', mail('m2'));
  app.repo.put('message', mail('m3', 'a2')); app.repo.put('message', mail('trash', 'a1', 'trash'));
  app.repo.put('message', { ...mail('plain'), summary: null });
  return {
    get repo() { return app.repo; },
    async restart() { await app.close(); app = await startServer({ directory, token, demo: false }); },
    async request(body) {
      const response = await fetch(`http://127.0.0.1:${app.port}/summaries/visibility`, { method: 'POST',
        headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      return { status: response.status, body: await response.json() };
    },
  };
}

test('single removal changes only overview membership and keeps summary, todos, source and search', async t => {
  const app = await fixture(t);
  const before = app.repo.get('message', 'm1');
  const result = await app.request({ accountId: 'a1', messageIds: ['m1'], hidden: true });
  assert.equal(result.status, 200); assert.deepEqual(result.body.messageIds, ['m1']);
  assert.deepEqual(app.repo.get('message', 'm1'), { ...before, summaryHidden: true });
  assert.deepEqual(app.repo.get('message', 'm1').summary, summary);
  await app.repo.searchIndex.drain();
  assert.ok(app.repo.search('确认排期').some(message => message.id === 'm1'));
  assert.equal(app.repo.list('mutation').length, 0);
  assert.equal(app.repo.get('message', 'm2').summaryHidden, undefined);
});

test('multi-select removal deduplicates and rejects cross-account or stale selections atomically', async t => {
  const app = await fixture(t);
  for (const messageIds of [['m1', 'm3'], ['m1', 'missing'], ['m1', 'plain']]) {
    assert.equal((await app.request({ accountId: 'a1', messageIds, hidden: true })).status, 409);
    assert.equal(app.repo.get('message', 'm1').summaryHidden, undefined);
  }
  const result = await app.request({ accountId: 'a1', messageIds: ['m1', 'm2', 'm1'], hidden: true });
  assert.equal(result.status, 200); assert.deepEqual(result.body.messageIds, ['m1', 'm2']);
  assert.deepEqual(app.repo.get('message', 'm2').summary, summary);
});

test('clear and restore affect only the current account overview, not trash or unsummarized mail', async t => {
  const app = await fixture(t);
  const clear = await app.request({ accountId: 'a1', all: true, hidden: true });
  assert.deepEqual(clear.body.messageIds, ['m1', 'm2']);
  for (const id of ['m3', 'plain', 'trash']) assert.equal(app.repo.get('message', id).summaryHidden, undefined);
  assert.deepEqual((await app.request({ accountId: 'a1', all: true, hidden: true })).body.messageIds, []);
  const restore = await app.request({ accountId: 'a1', messageIds: clear.body.messageIds, hidden: false });
  assert.equal(restore.status, 200);
  assert.equal(app.repo.get('message', 'm1').summaryHidden, false);
  assert.deepEqual(app.repo.get('message', 'm1').summary, summary);
});

test('removed entries remain removed after restart and can be restored individually', async t => {
  const app = await fixture(t);
  await app.request({ accountId: 'a1', messageIds: ['m1', 'm2'], hidden: true });
  await app.restart();
  assert.equal(app.repo.get('message', 'm1').summaryHidden, true);
  assert.equal(app.repo.messageHeaders().find(message => message.id === 'm1').summaryHidden, true);
  assert.equal((await app.request({ accountId: 'a1', messageIds: ['m1'], hidden: false })).status, 200);
  assert.equal(app.repo.get('message', 'm1').summaryHidden, false);
  assert.equal(app.repo.get('message', 'm2').summaryHidden, true);
});

test('membership follows pending folder reconciliation without changing the original summary', async t => {
  const app = await fixture(t);
  for (const kind of ['relocation', 'recovery']) app.repo.put(kind, { id: kind, original: mail('m1'), remotePath: 'Archive' });
  await app.request({ accountId: 'a1', messageIds: ['m1'], hidden: true });
  for (const kind of ['relocation', 'recovery']) {
    assert.equal(app.repo.get(kind, kind).original.summaryHidden, true);
    assert.deepEqual(app.repo.get(kind, kind).original.summary, summary);
  }
});

test('malformed overview operations never change mail records', async t => {
  const app = await fixture(t);
  for (const body of [
    { accountId: 'a1', messageIds: [], hidden: true },
    { accountId: 'a1', messageIds: ['m1'], hidden: 'yes' },
    { accountId: 'a1', all: 'true', hidden: true },
    { accountId: 'a1', all: true, messageIds: ['m1'], hidden: true },
    { accountId: 'missing', all: true, hidden: true },
  ]) assert.equal((await app.request(body)).status, 400);
  assert.equal(app.repo.get('message', 'm1').summaryHidden, undefined);
});
