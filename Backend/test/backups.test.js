import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, readdir } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import JSZip from 'jszip';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { Repository } from '../src/database.js';
import { createBackup, inspectBackup, restoreBackup } from '../src/backups.js';
import { startServer } from '../src/server.js';
import { aiConfig } from '../src/validation.js';

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-backup-test-'));
  const repo = new Repository(path.join(directory, 'data'));
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  await seedRecords(repo);
  return { repo, directory, backup: path.join(directory, 'backup.zip') };
}

async function seedRecords(repo) {
  repo.put('account', { id: 'a', name: '测试', email: 'me@example.com', username: 'me@example.com',
    imapHost: 'imap.example.com', smtpHost: 'smtp.example.com', imapPort: 993, smtpPort: 465, imapTLS: true, smtpTLS: true, isDemo: true });
  repo.put('message', { id: 'm', accountId: 'a', folder: 'archive', sender: '测试', senderEmail: 'sender@example.com',
    to: 'me@example.com', cc: '', preview: '正文', date: '2026-10-21T01:00:00Z', category: '未分类', unread: false, starred: false,
    subject: '合同', body: '正文', attachmentIds: ['f'], archivedFromFolder: 'sent', summary: { points: [], todos: [], keyInfo: [], overview: 'AI 结果' } });
  repo.put('draft', { id: 'd', accountId: 'a', to: '', cc: '', bcc: '', subject: '草稿', body: '未发草稿', status: 'draft', updatedAt: '2026-10-21T01:00:00Z', attachmentIds: ['f'] });
  repo.put('job', { id: 'j', accountId: 'a', task: 'classify', status: 'paused', createdAt: '2026-10-21T01:00:00Z', completedIds: ['m'], result: { items: [] } });
  repo.put('mutation', { id: 'mu', accountId: 'a', target: 'archive', uid: 9 });
  repo.put('settings', { id: 'settings', ai: { ...DEFAULT_AI, model: 'test' }, preferences: {
    signature: '签名', language: '简体中文', syncMinutes: 5, fontSize: 14, markRead: true, launchAtLogin: false,
    notifications: false, blockRemoteImages: true, spamFilter: true } });
  await mkdir(path.join(repo.directory, 'attachments'));
  const attachment = path.join(repo.directory, 'attachments', 'original.txt');
  await writeFile(attachment, '附件原始字节');
  repo.put('attachment', { id: 'f', messageId: 'm', name: '合同.txt', contentType: 'text/plain', date: '2026-10-21T01:00:00Z',
    size: Buffer.byteLength('附件原始字节'), parseError: '', path: attachment, text: '提取文本', analysis: '理解结果' });
  repo.event('test', '历史活动');
}

test('complete backup restores records, attachment bytes, jobs, drafts and queued mutations with a rollback backup', async t => {
  const { repo, directory, backup } = await fixture(t);
  repo.put('message', { ...repo.get('message', 'm'), summaryHidden: true });
  const saved = await createBackup(repo, backup);
  assert.equal(saved.counts.message, 1);
  assert.equal(saved.credentialsIncluded, false);
  assert.equal((await inspectBackup(backup)).counts.attachment, 1);
  repo.put('message', { ...repo.get('message', 'm'), id: 'new', subject: '恢复前新邮件' });
  repo.put('draft', { ...repo.get('draft', 'd'), body: '恢复前修改' });
  const result = await restoreBackup(repo, backup, true);
  assert.equal(repo.get('message', 'new'), null);
  assert.equal(repo.get('message', 'm').archivedFromFolder, 'sent');
  assert.equal(repo.get('message', 'm').summaryHidden, true);
  assert.equal(repo.get('draft', 'd').body, '未发草稿');
  assert.equal(repo.get('job', 'j').status, 'paused');
  assert.equal(repo.get('mutation', 'mu').uid, 9);
  const attachment = repo.get('attachment', 'f');
  assert.ok(attachment.path.startsWith(path.join(directory, 'data', 'attachments', 'restored-')));
  assert.equal(await readFile(attachment.path, 'utf8'), '附件原始字节');
  assert.equal(attachment.analysis, '理解结果');
  assert.equal(repo.get('settings', 'settings').preferences.signature, '签名');
  assert.equal((await inspectBackup(result.previousBackup)).counts.message, 2);
  assert.ok(repo.events().some(event => event.detail === '历史活动'));
  await restoreBackup(repo, result.previousBackup, true);
  assert.equal(repo.get('message', 'new').subject, '恢复前新邮件');
  assert.equal(repo.get('draft', 'd').body, '恢复前修改');
});

test('restore requires confirmation and a corrupted checksum leaves current data unchanged', async t => {
  const { repo, backup } = await fixture(t);
  await createBackup(repo, backup);
  await assert.rejects(restoreBackup(repo, backup, false), /明确确认/);
  const zip = await JSZip.loadAsync(await readFile(backup));
  const name = Object.keys(zip.files).find(name => name.endsWith('.bin'));
  zip.file(name, '被篡改');
  await writeFile(backup, await zip.generateAsync({ type: 'nodebuffer' }));
  await assert.rejects(restoreBackup(repo, backup, true), /校验失败|大小/);
  assert.equal(repo.get('draft', 'd').body, '未发草稿');
  assert.equal((await readdir(repo.directory)).includes('backups'), false);
});

test('valid checksums cannot hide malformed message fields or missing attachment references', async t => {
  const { repo, directory, backup } = await fixture(t);
  await createBackup(repo, backup);
  const original = await readFile(backup);
  for (const [name, change] of [
    ['missing-field', value => { delete value.preview; }],
    ['missing-reference', value => { value.attachmentIds = ['missing-attachment']; }],
    ['invalid-translation', value => { value.translation = {}; }],
    ['invalid-translation-html', value => { value.translationHTML = []; }],
    ['invalid-summary-membership', value => { value.summaryHidden = 'true'; }],
  ]) {
    const zip = await JSZip.loadAsync(original);
    const manifest = JSON.parse(await zip.file('manifest.json').async('string'));
    const database = path.join(directory, `${name}.sqlite`);
    await writeFile(database, await zip.file('boxmail.sqlite').async('nodebuffer'));
    const db = new DatabaseSync(database);
    try {
      const value = JSON.parse(db.prepare("SELECT data FROM records WHERE kind='message' AND id='m'").get().data);
      change(value);
      db.prepare("UPDATE records SET data=? WHERE kind='message' AND id='m'").run(JSON.stringify(value));
    } finally { db.close(); }
    const bytes = await readFile(database);
    const entry = manifest.files.find(file => file.path === 'boxmail.sqlite');
    entry.size = bytes.length;
    entry.sha256 = createHash('sha256').update(bytes).digest('hex');
    zip.file('boxmail.sqlite', bytes);
    zip.file('manifest.json', JSON.stringify(manifest));
    const damaged = path.join(directory, `${name}.zip`);
    await writeFile(damaged, await zip.generateAsync({ type: 'nodebuffer' }));
    await assert.rejects(inspectBackup(damaged), /记录字段或附件关联/);
    await assert.rejects(restoreBackup(repo, damaged, true), /记录字段或附件关联/);
    assert.equal(repo.get('message', 'm').preview, '正文');
    assert.deepEqual(repo.get('message', 'm').attachmentIds, ['f']);
    assert.equal((await readdir(repo.directory)).includes('backups'), false);
  }
});

test('failure before restore commit retains records and files and removes staged attachments', async t => {
  const { repo, backup } = await fixture(t);
  await createBackup(repo, backup);
  const originalPath = repo.get('attachment', 'f').path;
  await assert.rejects(restoreBackup(repo, backup, true, { beforeCommit() { throw new Error('disk failure'); } }));
  assert.equal(repo.get('attachment', 'f').path, originalPath);
  assert.equal(await readFile(originalPath, 'utf8'), '附件原始字节');
  assert.deepEqual(await readdir(path.join(repo.directory, 'attachments')), ['original.txt']);
  assert.equal((await readdir(path.join(repo.directory, 'backups'))).length, 1);
});

test('missing attachments refuse incomplete export without replacing a prior backup', async t => {
  const { repo, backup } = await fixture(t);
  await writeFile(backup, 'previous backup');
  await rm(repo.get('attachment', 'f').path);
  await assert.rejects(createBackup(repo, backup), /缺失/);
  assert.equal(await readFile(backup, 'utf8'), 'previous backup');
});

test('ZIP path traversal, unknown files and future backup versions are rejected before restore', async t => {
  const { repo, directory, backup } = await fixture(t);
  await createBackup(repo, backup);
  const original = await readFile(backup);
  for (const [name, edit] of [
    ['traversal', zip => zip.file('../outside.txt', 'bad')],
    ['extra', zip => zip.file('unexpected.txt', 'bad')],
    ['future', async zip => { const m = JSON.parse(await zip.file('manifest.json').async('string')); m.version = 10; zip.file('manifest.json', JSON.stringify(m)); }],
  ]) {
    const zip = await JSZip.loadAsync(original);
    await edit(zip);
    const file = path.join(directory, `${name}.zip`);
    await writeFile(file, await zip.generateAsync({ type: 'nodebuffer' }));
    await assert.rejects(restoreBackup(repo, file, true));
    assert.equal(repo.get('draft', 'd').body, '未发草稿');
  }
});

test('interrupted sends and running tasks restore into safe recoverable states', async t => {
  const { repo, backup } = await fixture(t);
  repo.put('draft', { ...repo.get('draft', 'd'), status: 'sending' });
  repo.put('job', { ...repo.get('job', 'j'), task: 'attachmentBatch', status: 'running', attachmentItems: [{ id: 'f', name: '合同.txt', status: 'running' }] });
  repo.put('sync', { id: 'a-inbox', accountId: 'a', folder: 'inbox', status: 'running' });
  await createBackup(repo, backup);
  await restoreBackup(repo, backup, true);
  assert.equal(repo.get('draft', 'd').status, 'uncertain');
  assert.equal(repo.get('job', 'j').status, 'paused');
  assert.equal(repo.get('job', 'j').attachmentItems[0].status, 'pending');
  assert.equal(repo.get('sync', 'a-inbox').status, 'paused');
});

test('HTTP full backup transfers all record kinds and attachment bytes to another directory, survives restart and rolls back', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-backup-wire-'));
  const token = 'backup-wire-session-0123456789';
  let source = await startServer({ directory: path.join(directory, 'source'), token, demo: false });
  let target = await startServer({ directory: path.join(directory, 'target'), token, demo: false });
  t.after(async () => {
    await source?.close(); await target?.close();
    await rm(directory, { recursive: true, force: true });
  });
  async function request(app, route, body) {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: body ? 'POST' : 'GET', headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, body: await response.json() };
  }
  await seedRecords(source.repo); await seedRecords(target.repo);
  target.repo.put('message', { ...target.repo.get('message', 'm'), id: 'target-only', subject: '目标目录原有邮件' });
  target.repo.put('draft', { ...target.repo.get('draft', 'd'), body: '目标目录原有草稿' });
  const settings = source.repo.get('settings', 'settings');
  settings.ai = aiConfig({ ...DEFAULT_AI, providerId: 'work', providers: [{ id: 'work', name: '工作模型',
    baseURL: 'https://gateway.example.test/v1', apiProtocol: 'openai-completions', model: 'work-model',
    models: [{ id: 'work-model', name: '工作', contextWindow: 256000, maxTokens: 32000,
      input: ['text', 'image'], reasoningEfforts: { off: null, high: 'max' } }] }] });
  settings.preferences.signature = '备份签名\n第二行';
  settings.credentialReferences = { 'ai-provider-work': 'configuration-synthetic-reference' };
  source.repo.put('settings', settings);
  const original = { ...source.repo.get('message', 'm'), summaryHidden: true,
    html: '<table><tr><td><a href="https://example.test">Original</a></td></tr></table><pre>run example</pre>',
    translation: '译文\nrun example',
    translationHTML: '<table><tr><td><a href="https://example.test">译文</a></td></tr></table><pre>run example</pre>',
    summary: { overview: '完整总结', points: ['核对合同'], todos: [{ id: 'todo', title: '确认排期', due: '2026-10-31', done: true }],
      keyInfo: [{ label: '预算', value: '128,000 元' }], nextSteps: [{ action: 'reply', title: '回复', prompt: '确认排期' }] },
    attachmentIds: ['f', 'binary'] };
  source.repo.put('message', original);
  source.repo.put('account', { ...source.repo.get('account', 'a'), id: 'other', email: 'other@example.test', username: 'other@example.test' });
  source.repo.put('message', { ...original, id: 'other-mail', accountId: 'other', folder: 'inbox', attachmentIds: [], summaryHidden: false });
  const bytes = Buffer.from([0, 1, 127, 128, 255, 10, 13, 0, 45]);
  const binary = path.join(source.repo.directory, 'attachments', 'original.bin');
  await writeFile(binary, bytes);
  source.repo.put('attachment', { ...source.repo.get('attachment', 'f'), id: 'binary', name: '原始数据.bin',
    contentType: 'application/octet-stream', path: binary, size: bytes.length, text: '', analysis: null });
  source.repo.put('draft', { ...source.repo.get('draft', 'd'), status: 'sending' });
  for (const kind of ['relocation', 'recovery']) source.repo.put(kind, { id: kind, original, remotePath: 'Archive' });
  source.repo.put('sync', { id: 'a-inbox', accountId: 'a', folder: 'inbox', status: 'running', nextUID: 37 });
  const job = source.repo.get('job', 'j');
  source.repo.put('job', { ...job, id: 'completed', task: 'summary', status: 'completed', result: original.summary });
  source.repo.put('job', { ...job, id: 'translation', task: 'translate', status: 'running', result: null });
  source.repo.put('job', { ...job, id: 'classification', status: 'running', messageIds: ['m'],
    result: { items: [{ id: 'm', category: '工作项目', reason: '合同评审' }] } });
  source.repo.put('job', { ...job, id: 'batch', task: 'attachmentBatch', status: 'running', messageId: 'm',
    attachmentItems: [{ id: 'f', name: '合同.txt', status: 'completed' }, { id: 'binary', name: '原始数据.bin', status: 'running' }] });
  const records = source.repo.db.prepare('SELECT kind,id,data FROM records ORDER BY kind,id').all();
  const events = source.repo.events();
  const backup = path.join(directory, '完整备份.zip');
  const saved = await request(source, '/backups/create', { path: backup });
  assert.equal(saved.status, 200, JSON.stringify(saved.body));
  assert.deepEqual(saved.body.counts, { account: 2, message: 2, draft: 1, attachment: 2, job: 5, mutation: 1 });
  const inspected = await request(target, '/backups/inspect', { path: backup });
  assert.equal(inspected.status, 200); assert.equal(inspected.body.sha256, saved.body.sha256);
  assert.equal((await request(target, '/backups/restore', { path: backup, approved: false })).status, 403);
  assert.notEqual((await request(target, '/backups/restore', { path: backup, approved: true, sha256: '0'.repeat(64) })).status, 200);
  assert.ok(target.repo.get('message', 'target-only'));
  const restored = await request(target, '/backups/restore', { path: backup, approved: true, sha256: inspected.body.sha256 });
  assert.equal(restored.status, 200, JSON.stringify(restored.body));
  assert.equal(target.repo.get('message', 'target-only'), null);
  // Verify every persisted record, allowing only the documented safe task states and rebased file paths.
  assert.equal(target.repo.db.prepare('SELECT count(*) AS count FROM records').get().count, records.length);
  for (const row of records) {
    const expected = JSON.parse(row.data), actual = target.repo.get(row.kind, row.id);
    if (row.kind === 'attachment') {
      assert.ok(actual.path.startsWith(path.join(target.repo.directory, 'attachments', 'restored-')));
      assert.deepEqual(await readFile(actual.path), await readFile(expected.path));
      expected.path = actual.path;
    }
    if (row.kind === 'draft' && expected.status === 'sending') expected.status = 'uncertain';
    if (row.kind === 'sync' && expected.status === 'running') expected.status = 'paused';
    if (row.kind === 'job' && expected.status === 'running') {
      expected.status = ['classify', 'attachmentBatch'].includes(expected.task) ? 'paused' : 'failed';
      expected.error = '备份恢复了未完成任务，请检查后继续。';
      for (const item of expected.attachmentItems || []) if (item.status === 'running') item.status = 'pending';
    }
    assert.deepEqual(actual, expected, `${row.kind}/${row.id}`);
  }
  for (const event of events) assert.ok(target.repo.events().some(value => value.id === event.id));
  // Remove the original directory: reading the restored attachments must be independent of it.
  await source.close(); source = null;
  await rm(path.join(directory, 'source'), { recursive: true, force: true });
  await target.close(); target = null;
  target = await startServer({ directory: path.join(directory, 'target'), token, demo: false });
  const detail = await request(target, '/messages/m');
  assert.equal(detail.body.translationHTML, original.translationHTML);
  assert.deepEqual(detail.body.summary, original.summary); assert.equal(detail.body.summaryHidden, true);
  const state = await request(target, '/state?compact=1');
  assert.equal(state.body.messages.filter(value => value.summary && value.summaryHidden !== true).length, 1);
  assert.deepEqual(state.body.settings.ai, settings.ai);
  assert.equal(state.body.settings.preferences.signature, settings.preferences.signature);
  assert.equal(state.body.jobs.find(value => value.id === 'batch').status, 'paused');
  assert.equal(state.body.pendingMutations, 1);
  assert.deepEqual(Buffer.from((await request(target, '/attachments/binary')).body.content, 'base64'), bytes);
  assert.ok((await request(target, '/search?q=' + encodeURIComponent('确认排期'))).body.messages.some(value => value.id === 'm'));
  // The automatic before-restore archive can put the target's previous data back as well.
  const rollback = await request(target, '/backups/inspect', { path: restored.body.previousBackup });
  assert.equal((await request(target, '/backups/restore', { path: restored.body.previousBackup,
    sha256: rollback.body.sha256, approved: true })).status, 200);
  assert.equal(target.repo.get('message', 'target-only').subject, '目标目录原有邮件');
  assert.equal(target.repo.get('draft', 'd').body, '目标目录原有草稿');
  assert.equal((await request(target, '/attachments/f')).body.content, Buffer.from('附件原始字节').toString('base64'));
});
