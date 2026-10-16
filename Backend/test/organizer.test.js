import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { Repository } from '../src/database.js';
import { Organizer } from '../src/organizer.js';
import { approveClassification } from '../src/agent.js';
import { startServer } from '../src/server.js';
import { DEFAULT_AI } from '../src/ai-settings.js';

const config = { ...DEFAULT_AI, baseURL: 'http://127.0.0.1:12345/v1' };
const token = 'test-organizer-session-0123456789';
function seed(repo, count = 14) {
  repo.put('account', { id: 'a1' });
  repo.put('account', { id: 'a2' });
  for (let i = 0; i < count; i++) repo.put('message', {
    id: `m${i}`, accountId: 'a1', folder: 'inbox', category: '未分类',
    subject: `邮件 ${i}`, sender: '测试', body: 'https://tracker.example/long/url 项目进度 '.repeat(100),
    date: new Date(Date.UTC(2026, 9, i + 1)).toISOString(),
  });
  repo.put('message', { ...repo.get('message', 'm0'), id: 'foreign', accountId: 'a2' });
}
async function fixture(t, complete, count) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-organizer-'));
  const repo = new Repository(directory);
  seed(repo, count);
  const manager = new Organizer(repo, { complete });
  t.after(async () => { await manager.close(); repo.close(); await rm(directory, { recursive: true, force: true }); });
  return { repo, manager };
}
const classify = context => ({ items: context.map(m => ({ id: m.id, category: '工作项目', reason: '项目进展' })) });
const waitForAbort = signal => new Promise((resolve, reject) => {
  if (signal.aborted) reject(signal.reason);
  else signal.addEventListener('abort', () => reject(signal.reason), { once: true });
});

test('organization returns before the model, limits scope and never persists credentials', async t => {
  const gate = Promise.withResolvers();
  let received;
  const { repo, manager } = await fixture(t, async (cfg, key, task, context, images, options) => {
    received = { key, task, context, options };
    await gate.promise;
    return classify(context);
  });
  repo.put('message', { ...repo.get('message', 'm13'), category: '账单票据' });
  const job = manager.start({ accountId: 'a1', apiKey: 'secret-test-key', config, limit: 3 });
  assert.equal(job.status, 'running');
  assert.equal(job.progress.total, 3);
  assert.equal(manager.busy('a1'), true);
  assert.throws(() => manager.start({ accountId: 'a1', config }), /正在整理/);
  const pending = manager.workers.get(job.id).promise;
  await Promise.resolve();
  assert.deepEqual(received.context.map(m => m.id), ['m12', 'm11', 'm10']);
  assert.ok(received.context.every(m => m.body.length <= 600 && !m.body.includes('https://')));
  assert.equal(received.options.stream, true);
  assert.equal(JSON.stringify(repo.list('job')).includes('secret-test-key'), false);
  gate.resolve();
  await pending;
  assert.equal(repo.get('job', job.id).status, 'needsApproval');
});

test('batches persist progress, reject foreign ids and require confirmation before applying and undoing', async t => {
  const batches = [];
  const { repo, manager } = await fixture(t, async (cfg, key, task, context) => {
    batches.push(context);
    return { items: [...classify(context).items, { id: 'foreign', category: '工作项目' }] };
  });
  const job = manager.start({ accountId: 'a1', config });
  await manager.workers.get(job.id).promise;
  const stored = repo.get('job', job.id);
  assert.deepEqual(batches.map(b => b.length), [6, 6, 2]);
  assert.equal(stored.progress.completed, 14);
  assert.equal(stored.result.items.length, 14);
  assert.equal(repo.get('message', 'm1').category, '未分类');
  approveClassification(repo, job.id);
  assert.equal(repo.get('message', 'm1').category, '工作项目');
  assert.equal(repo.get('message', 'foreign').category, '未分类');
  approveClassification(repo, job.id, true);
  assert.equal(repo.get('message', 'm1').category, '未分类');
});

test('a timeout preserves finished suggestions and retry sends only unfinished emails', async t => {
  let fail = true, requests = [];
  const { repo, manager } = await fixture(t, async (cfg, key, task, context) => {
    requests.push(context.map(m => m.id));
    if (fail && requests.length === 2) throw new DOMException('deadline', 'TimeoutError');
    return classify(context);
  }, 10);
  const job = manager.start({ accountId: 'a1', config });
  await manager.workers.get(job.id).promise;
  const partial = repo.get('job', job.id);
  assert.equal(partial.status, 'partial');
  assert.equal(partial.progress.completed, 6);
  assert.equal(partial.progress.failed, 4);
  assert.match(partial.error, /超时/);
  fail = false;
  requests = [];
  manager.start({ accountId: 'a1', config }, job.id);
  await manager.workers.get(job.id).promise;
  assert.deepEqual(requests, [['m3', 'm2', 'm1', 'm0']]);
  assert.equal(repo.get('job', job.id).result.items.length, 10);
  assert.equal(repo.get('job', job.id).status, 'needsApproval');
});

test('pause aborts the active request and partial suggestions can still be applied and undone', async t => {
  const second = Promise.withResolvers();
  let calls = 0;
  const { repo, manager } = await fixture(t, async (cfg, key, task, context, images, { signal }) => {
    if (++calls === 1) return classify(context);
    second.resolve();
    return waitForAbort(signal);
  }, 10);
  const job = manager.start({ accountId: 'a1', config });
  await second.promise;
  assert.throws(() => approveClassification(repo, job.id), /不能执行/);
  const paused = await manager.pause(job.id);
  assert.equal(paused.status, 'paused');
  assert.equal(paused.result.items.length, 6);
  assert.equal(paused.progress.completed, 6);
  approveClassification(repo, job.id);
  assert.equal(repo.list('message').filter(m => m.category === '工作项目').length, 6);
  approveClassification(repo, job.id, true);
  assert.equal(repo.list('message').filter(m => m.category === '工作项目').length, 0);
});

test('invalid and duplicate model items cannot create false completed progress', async t => {
  const { repo, manager } = await fixture(t, async (cfg, key, task, context) => ({ items: [
    null, { id: context[0].id, category: '工作项目' }, { id: context[0].id, category: '工作项目' },
    { id: context[1].id, category: 'invalid' }, { id: 'foreign', category: '社交通知' },
  ] }), 2);
  const job = manager.start({ accountId: 'a1', config });
  await manager.workers.get(job.id).promise;
  const result = repo.get('job', job.id);
  assert.equal(result.status, 'partial');
  assert.equal(result.progress.completed, 1);
  assert.equal(result.result.items.length, 1);
  assert.equal(result.progress.failed, 1);
});

test('a broken provider fails once without discarding history or scheduling all remaining batches', async t => {
  let calls = 0;
  const { repo, manager } = await fixture(t, async () => { calls++; throw new Error('terminated'); });
  const job = manager.start({ accountId: 'a1', config });
  await manager.workers.get(job.id).promise;
  assert.equal(calls, 1);
  assert.equal(repo.get('job', job.id).status, 'failed');
  assert.equal(repo.get('job', job.id).progress.failed, 14);
  assert.match(repo.get('job', job.id).error, /连接中断/);
});

test('HTTP organization is asynchronous, supports progress and pause, and recovers after restart', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-organizer-api-'));
  const started = Promise.withResolvers();
  let app = await startServer({ directory, token, demo: false, organizerComplete: async (cfg, key, task, context, images, { signal }) => {
    started.resolve();
    return waitForAbort(signal);
  } });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  seed(app.repo, 3);
  app.repo.put('settings', { ...app.repo.get('settings', 'settings'), ai: config });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: body ? 'POST' : 'GET', headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, value: await response.json() };
  };
  const { value: job, status } = await request('/agent', { task: 'classify', accountId: 'a1' });
  assert.equal(status, 200);
  assert.equal(job.status, 'running');
  await started.promise;
  assert.equal((await request(`/jobs/${job.id}`)).value.progress.total, 3);
  assert.equal((await request('/state')).status, 200);
  assert.equal((await request('/organize', { accountId: 'a1' })).status, 409);
  assert.equal((await request(`/jobs/${job.id}/pause`, {})).value.status, 'paused');
  // Simulate an abrupt exit after a completed batch, without a graceful close.
  app.repo.put('job', { ...app.repo.get('job', job.id), status: 'running', completedIds: ['m2'],
    result: classify([{ id: 'm2' }]), progress: { total: 3, completed: 1, failed: 0, batchSize: 6, batch: 1 } });
  await app.close();
  const contexts = [];
  app = await startServer({ directory, token, demo: false, organizerComplete: async (cfg, key, task, context) => {
    contexts.push(context.map(m => m.id));
    return classify(context);
  } });
  assert.equal((await request(`/jobs/${job.id}`)).value.status, 'paused');
  await request(`/jobs/${job.id}/retry`, {});
  // Poll the public job resource; no full mailbox snapshots are needed.
  for (let i = 0; i < 10; i++) {
    if ((await request(`/jobs/${job.id}`)).value.status !== 'running') break;
  }
  assert.equal((await request(`/jobs/${job.id}`)).value.status, 'needsApproval');
  assert.deepEqual(contexts, [['m1', 'm0']]);
  assert.equal((await request(`/jobs/${job.id}/approve`, {})).value.status, 'applied');
  assert.equal((await request(`/jobs/${job.id}/undo`, {})).value.status, 'undone');
});
