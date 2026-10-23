import { responsesWire } from './helpers/ai-streams.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { Repository } from '../src/database.js';
import { AttachmentBatch } from '../src/attachment-batch.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { saveAttachment } from '../src/attachments.js';
import { startServer } from '../src/server.js';
import { ServiceError } from '../src/validation.js';

const config = { ...DEFAULT_AI, baseURL: 'http://127.0.0.1:12345/v1' };
const token = 'test-attachment-batch-session-0123456789';
async function seed(repo, count = 8) {
  repo.put('account', { id: 'a1' });
  repo.put('account', { id: 'a2' });
  const files = [];
  for (let index = 0; index < count; index++) {
    files.push(await saveAttachment(repo, 'm1', `附件${index + 1}.txt`, Buffer.from(`正文 ${index + 1}`), 'text/plain'));
  }
  repo.put('message', { id: 'm1', accountId: 'a1', attachmentIds: files.map(file => file.id),
    subject: '本封邮件的项目资料', sender: '测试发件人', body: '请处理这批附件', folder: 'inbox', date: '2026-10-19T00:00:00Z' });
  return files;
}
function succeed(repo, input) {
  const file = repo.get('attachment', input.attachmentId);
  repo.put('attachment', { ...file, analysis: `## 理解结果\n${file.name}` });
}
async function fixture(t, run, count) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-attachment-batch-'));
  const repo = new Repository(directory);
  const files = await seed(repo, count);
  const manager = new AttachmentBatch(repo, { run });
  t.after(async () => { await manager.close(); repo.close(); await rm(directory, { recursive: true, force: true }); });
  return { directory, repo, manager, files };
}
const waitForAbort = signal => new Promise((resolve, reject) => {
  if (signal.aborted) reject(signal.reason);
  else signal.addEventListener('abort', () => reject(signal.reason), { once: true });
});

test('one click queues all eight files in email order, reuses results and deduplicates repeated clicks', async t => {
  const gate = Promise.withResolvers();
  const requests = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => {
    requests.push(input);
    await gate.promise;
    succeed(repo, input);
  });
  for (const file of files.slice(0, 3)) repo.put('attachment', { ...file, analysis: '已有结果' });
  const job = manager.start({ messageId: 'm1', accountId: 'a1', config, apiKey: 'secret-test-key' });
  const pending = manager.workers.get(job.id).promise;
  assert.equal(job.status, 'running');
  assert.equal(job.progress.total, 8);
  assert.equal(job.progress.completed, 3);
  assert.equal(manager.start({ messageId: 'm1', config }).id, job.id);
  await Promise.resolve();
  assert.equal(repo.get('job', job.id).attachmentItems[3].status, 'running');
  assert.equal(requests.length, 1);
  gate.resolve();
  await pending;
  assert.deepEqual(requests.map(input => input.attachmentId), files.slice(3).map(file => file.id));
  assert.ok(requests.every(input => input.messageId === 'm1' && input.accountId === 'a1' && input.parentJobId === job.id));
  assert.equal(repo.get('job', job.id).status, 'completed');
  assert.equal(repo.get('job', job.id).progress.completed, 8);
  assert.equal(repo.get('attachment', files[0].id).analysis, '已有结果');
  assert.equal(JSON.stringify(repo.list('job')).includes('secret-test-key'), false);
});

test('a failed file does not stop later files, and retry sends only failures', async t => {
  let fail = true;
  const calls = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => {
    calls.push(input.attachmentId);
    if (input.attachmentId === files[1].id && fail) throw new DOMException('deadline', 'TimeoutError');
    succeed(repo, input);
  }, 4);
  const job = manager.start({ messageId: 'm1', config });
  await manager.workers.get(job.id).promise;
  const partial = repo.get('job', job.id);
  assert.equal(partial.status, 'partial');
  assert.equal(partial.progress.completed, 3);
  assert.equal(partial.progress.failed, 1);
  assert.match(partial.attachmentItems[1].error, /超时/);
  assert.ok(repo.get('attachment', files[3].id).analysis);
  fail = false;
  calls.length = 0;
  manager.start({ config }, job.id);
  await manager.workers.get(job.id).promise;
  assert.deepEqual(calls, [files[1].id]);
  assert.equal(repo.get('job', job.id).status, 'completed');
  assert.equal(repo.get('job', job.id).error, null);
});

test('unsupported, missing and foreign files never reach AI; account scope is enforced', async t => {
  const calls = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => { calls.push(input.attachmentId); succeed(repo, input); }, 3);
  repo.put('attachment', { ...files[1], name: '归档.zip', text: '', contentType: 'application/zip' });
  repo.put('attachment', { ...files[2], messageId: 'other-mail' });
  repo.put('message', { ...repo.get('message', 'm1'), attachmentIds: [...files.map(file => file.id), 'missing', files[0].id] });
  assert.throws(() => manager.start({ messageId: 'm1', accountId: 'a2', config }), /不属于当前账户/);
  assert.throws(() => manager.start({ messageId: 'missing', config }), /邮件不存在/);
  const job = manager.start({ messageId: 'm1', config });
  await manager.workers.get(job.id).promise;
  assert.deepEqual(calls, [files[0].id]);
  assert.equal(repo.get('job', job.id).progress.total, 4);
  assert.deepEqual(repo.get('job', job.id).attachmentItems.map(item => item.status), ['completed', 'unsupported', 'failed', 'failed']);
  assert.equal(repo.get('attachment', files[2].id).analysis, null);
});

test('explicit reanalysis includes successful files, and failures retain the previous analysis', async t => {
  const { repo, manager, files } = await fixture(t, async () => { throw new ServiceError('模型暂不可用', 502); }, 2);
  for (const file of files) repo.put('attachment', { ...file, analysis: '保留的旧结果' });
  const job = manager.start({ messageId: 'm1', config, force: true });
  await manager.workers.get(job.id).promise;
  assert.equal(repo.get('job', job.id).status, 'failed');
  assert.equal(repo.get('job', job.id).progress.failed, 2);
  assert.ok(files.every(file => repo.get('attachment', file.id).analysis === '保留的旧结果'));
});

test('textless PPT and PPTX files participate in email batches, including MIME-only names', async t => {
  const calls = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => {
    calls.push(input.attachmentId); succeed(repo, input);
  }, 3);
  const formats = [
    ['slides.PPT', 'application/octet-stream'],
    ['slides.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'],
    ['slides', 'application/vnd.ms-powerpoint'],
  ];
  files.forEach((file, index) => repo.put('attachment', { ...file, name: formats[index][0], contentType: formats[index][1], text: '' }));
  const job = manager.start({ messageId: 'm1', config });
  await manager.workers.get(job.id).promise;
  assert.deepEqual(calls, files.map(file => file.id));
  assert.equal(repo.get('job', job.id).status, 'completed');
});

test('pause and shutdown abort active work, preserve successes, and resume only unfinished files', async t => {
  const second = Promise.withResolvers();
  let block = true;
  const calls = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => {
    calls.push(input.attachmentId);
    if (block && calls.length === 2) { second.resolve(); return waitForAbort(input.signal); }
    succeed(repo, input);
  }, 3);
  const job = manager.start({ messageId: 'm1', config });
  await second.promise;
  const paused = await manager.pause(job.id);
  assert.equal(paused.status, 'paused');
  assert.equal(paused.progress.completed, 1);
  assert.deepEqual(paused.attachmentItems.map(item => item.status), ['completed', 'pending', 'pending']);
  block = false;
  calls.length = 0;
  manager.start({ config }, job.id);
  await manager.workers.get(job.id).promise;
  assert.deepEqual(calls, files.slice(1).map(file => file.id));
  assert.equal(repo.get('job', job.id).status, 'completed');
  const other = new AttachmentBatch(repo, { run: (repo, input) => waitForAbort(input.signal) });
  const next = other.start({ messageId: 'm1', config, force: true });
  await Promise.resolve();
  await other.close();
  assert.equal(repo.get('job', next.id).status, 'paused');
});

test('file membership is checked again after the batch starts', async t => {
  const gate = Promise.withResolvers();
  const calls = [];
  const { repo, manager, files } = await fixture(t, async (repo, input) => {
    calls.push(input.attachmentId);
    await gate.promise;
    succeed(repo, input);
  }, 2);
  const job = manager.start({ messageId: 'm1', config });
  await Promise.resolve();
  repo.put('attachment', { ...files[1], messageId: 'other-mail' });
  gate.resolve();
  await manager.workers.get(job.id).promise;
  assert.deepEqual(calls, [files[0].id]);
  assert.equal(repo.get('job', job.id).attachmentItems[1].status, 'failed');
});

test('HTTP batch returns immediately, blocks conflicting changes, and recovers persisted progress after restart', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-attachment-batch-api-'));
  const started = Promise.withResolvers();
  let app = await startServer({ directory, token, demo: false, agentRun: async (repo, input) => {
    started.resolve();
    return waitForAbort(input.signal);
  } });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const files = await seed(app.repo, 2);
  app.repo.put('settings', { ...app.repo.get('settings', 'settings'), ai: config });
  const request = async (route, body, method = body ? 'POST' : 'GET') => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method, headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, value: await response.json() };
  };
  const { status, value: job } = await request('/messages/m1/attachments/analyze', {});
  assert.equal(status, 200);
  assert.equal(job.status, 'running');
  await started.promise;
  assert.equal((await request('/messages/m1/attachments/analyze', {})).value.id, job.id);
  assert.equal((await request('/agent', { task: 'attachment', attachmentId: files[0].id })).status, 409);
  assert.equal((await request('/accounts/a1', undefined, 'DELETE')).status, 409);
  assert.equal((await request(`/jobs/${job.id}`)).value.progress.total, 2);
  assert.equal((await request(`/jobs/${job.id}/pause`, {})).value.status, 'paused');
  const paused = app.repo.get('job', job.id);
  await app.close();
  // Mimic an interrupted process with one file fully saved and another in flight.
  const repo = new Repository(directory);
  succeed(repo, { attachmentId: files[0].id });
  repo.put('job', { ...paused, status: 'running', attachmentItems: paused.attachmentItems.map((item, i) =>
    ({ ...item, status: i === 0 ? 'completed' : 'running' })),
  progress: { total: 2, completed: 1, failed: 0, batchSize: 1, batch: 1 } });
  repo.close();
  const calls = [];
  app = await startServer({ directory, token, demo: false, agentRun: async (repo, input) => {
    calls.push(input.attachmentId); succeed(repo, input);
  } });
  const recovered = (await request(`/jobs/${job.id}`)).value;
  assert.equal(recovered.status, 'paused');
  assert.deepEqual(recovered.attachmentItems.map(item => item.status), ['completed', 'pending']);
  await request(`/jobs/${job.id}/retry`, {});
  for (let count = 0; count < 30; count++) {
    if ((await request(`/jobs/${job.id}`)).value.status !== 'running') break;
    await delay(5);
  }
  assert.equal((await request(`/jobs/${job.id}`)).value.status, 'completed');
  assert.deepEqual(calls, [files[1].id]);
});

test('real attachment agent sends each file with its email context and saves only complete nonempty results', async t => {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    const request = JSON.parse(raw);
    const context = JSON.parse(request.input[0].content[0].text);
    requests.push(context);
    const text = context.name === '附件2.txt' ? '  ' : '## 项目资料\n已理解全部内容';
    res.setHeader('Content-Type', 'text/event-stream');
    res.end(responsesWire({ status: 'completed', output: [{ type: 'message', role: 'assistant',
      content: [{ type: 'output_text', text: JSON.stringify({ text }) }] }] }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { repo, files } = await fixture(t, undefined, 3);
  const manager = new AttachmentBatch(repo);
  t.after(async () => { await manager.close(); await new Promise(resolve => server.close(resolve)); });
  const job = manager.start({ messageId: 'm1', config: { ...config, baseURL: `http://127.0.0.1:${server.address().port}/v1` } });
  await manager.workers.get(job.id).promise;
  assert.equal(requests.length, 3);
  assert.deepEqual(requests.map(request => request.name), files.map(file => file.name));
  assert.ok(requests.every(request => request.email.subject === '本封邮件的项目资料' && request.email.body === '请处理这批附件'));
  assert.equal(repo.get('job', job.id).status, 'partial');
  assert.equal(repo.get('attachment', files[1].id).analysis, null);
  assert.ok(repo.get('attachment', files[2].id).analysis);
});

test('pausing the real agent aborts its HTTP request without saving an incomplete analysis', async t => {
  const started = Promise.withResolvers();
  const server = http.createServer(async (req, res) => {
    for await (const chunk of req) { /* Drain the synthetic request. */ }
    started.resolve();
    res.setHeader('Content-Type', 'text/event-stream');
    res.write('data: {"type":"response.created"}\n\n');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { repo, files } = await fixture(t, undefined, 1);
  const manager = new AttachmentBatch(repo);
  t.after(async () => {
    await manager.close();
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  });
  const job = manager.start({ messageId: 'm1', config: { ...config, baseURL: `http://127.0.0.1:${server.address().port}/v1` } });
  await started.promise;
  const paused = await manager.pause(job.id);
  assert.equal(paused.status, 'paused');
  assert.equal(paused.attachmentItems[0].status, 'pending');
  assert.equal(repo.get('attachment', files[0].id).analysis, null);
  assert.equal(repo.list('job').find(child => child.parentJobId === job.id).status, 'failed');
});
