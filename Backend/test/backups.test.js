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

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-backup-test-'));
  const repo = new Repository(path.join(directory, 'data'));
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
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
  return { repo, directory, backup: path.join(directory, 'backup.zip') };
}

test('complete backup restores records, attachment bytes, jobs, drafts and queued mutations with a rollback backup', async t => {
  const { repo, directory, backup } = await fixture(t);
  const saved = await createBackup(repo, backup);
  assert.equal(saved.counts.message, 1);
  assert.equal(saved.credentialsIncluded, false);
  assert.equal((await inspectBackup(backup)).counts.attachment, 1);
  repo.put('message', { ...repo.get('message', 'm'), id: 'new', subject: '恢复前新邮件' });
  repo.put('draft', { ...repo.get('draft', 'd'), body: '恢复前修改' });
  const result = await restoreBackup(repo, backup, true);
  assert.equal(repo.get('message', 'new'), null);
  assert.equal(repo.get('message', 'm').archivedFromFolder, 'sent');
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
