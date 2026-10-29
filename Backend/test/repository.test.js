import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';

const message = { id: 'm1', accountId: 'a', folder: 'inbox', remotePath: 'INBOX', uid: 1,
  subject: '检索测试', body: '旧检索内容', html: '<p>正文</p>', translation: '译文', translationHTML: '<p>译文</p>',
  date: '2026-10-23T00:00:00Z', attachmentIds: [] };
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-repository-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('message', message);
  return repo;
}

test('identical writes leave a clean search index while real changes remain searchable', async t => {
  const repo = await fixture(t);
  repo.searchIndex.flush();
  repo.put('message', repo.get('message', 'm1'));
  assert.equal(repo.searchIndex.status().pending, 0);
  repo.put('message', { ...message, body: '新检索内容' });
  assert.equal(repo.searchIndex.status().pending, 1);
  await repo.searchIndex.drain();
  assert.deepEqual(repo.search('新检索内容').map(item => item.id), ['m1']);
  assert.deepEqual(repo.search('旧检索内容'), []);
});

test('background index failures skip one document and preserve successful neighbours', async t => {
  const repo = await fixture(t);
  repo.put('message', { ...message, id: 'm2' });
  repo.searchIndex.flush();
  for (const id of ['m1', 'm2']) repo.put('message', { ...message, id, body: '替换后的正文' });
  const update = repo.searchIndex.update.bind(repo.searchIndex);
  repo.searchIndex.update = id => { if (id === 'm2') throw new Error('模拟索引失败'); update(id); };
  await repo.searchIndex.drain();
  assert.equal(repo.searchIndex.status().pending, 0);
  assert.equal(repo.searchIndex.status().failed, 1);
  assert.equal(repo.db.prepare("SELECT count(*) AS n FROM mail_fts WHERE instr(text,'替换后的正文')>0").get().n, 1);
  assert.deepEqual(repo.search('替换后的正文').map(item => item.id), ['m1']);
  repo.searchIndex.update = update;
  repo.rebuildSearch(); await repo.searchIndex.drain();
  assert.deepEqual(repo.search('替换后的正文').map(item => item.id), ['m1', 'm2']);
});

test('search rebuild runs in bounded background tasks and isolates a failing document', async t => {
  const repo = await fixture(t);
  repo.put('message', { ...message, id: 'm2' });
  repo.searchIndex.flush();
  const update = repo.searchIndex.update.bind(repo.searchIndex);
  repo.searchIndex.update = id => { if (id === 'm2') throw new Error('模拟重建失败'); update(id); };
  repo.rebuildSearch();
  await repo.searchIndex.drain();
  assert.equal(repo.searchIndex.status().indexed, 1);
  assert.equal(repo.searchIndex.status().pending, 0);
  assert.equal(repo.searchIndex.status().failed, 1);
  repo.searchIndex.update = update;
  repo.rebuildSearch(); await repo.searchIndex.drain();
  assert.deepEqual(repo.search('旧检索内容').map(item => item.id), ['m1', 'm2']);
  repo.transaction(() => repo.rebuildSearch());
  await repo.searchIndex.drain();
  assert.equal(repo.searchIndex.status().indexed, 2);
});

test('scoped repository reads isolate accounts and mailboxes and keep headers lightweight', async t => {
  const repo = await fixture(t);
  repo.put('message', { ...message, id: 'sent', remotePath: 'Sent', folder: 'sent' });
  repo.put('message', { ...message, id: 'foreign', accountId: 'b' });
  assert.deepEqual(repo.list('message', { accountId: 'a', remotePath: 'INBOX' }).map(item => item.id), ['m1']);
  const headers = repo.messageHeaders('a');
  assert.deepEqual(headers.map(item => item.id), ['m1', 'sent']);
  assert.ok(headers.every(item => item.body === '' && item.bodyLoaded === false
    && item.html === undefined && item.translation === undefined && item.translationHTML === undefined));
  assert.equal(repo.messageHeaders().length, 3);
  assert.deepEqual(repo.messageHeaders('missing'), []);
});

test('nested transactions can roll back their own writes while the outer transaction continues', async t => {
  const repo = await fixture(t);
  repo.transaction(() => {
    repo.put('message', { ...message, body: '外层更新' });
    assert.throws(() => repo.transaction(() => {
      repo.put('message', { ...message, body: '内层失败' });
      repo.put('message', { ...message, id: 'inner' });
      throw new Error('内层回滚');
    }), /内层回滚/);
    assert.equal(repo.get('message', 'm1').body, '外层更新');
    assert.equal(repo.get('message', 'inner'), null);
    repo.put('message', { ...message, id: 'outer' });
  });
  assert.equal(repo.get('message', 'm1').body, '外层更新');
  assert.ok(repo.get('message', 'outer'));
  assert.equal(repo.db.isTransaction, false);
});

test('sent identity lookups isolate accounts and preserve complete cached content', async t => {
  const repo = await fixture(t);
  for (const value of [
    { ...message, id: 'sent-b', accountId: 'b', messageId: '<same@test>' },
    { ...message, id: 'inbox-copy', messageId: '<same@test>' },
    { ...message, id: 'sent-a', messageId: '<same@test>' },
  ]) repo.put('message', value);
  assert.equal(repo.localSentMessage('a', '<same@test>').id, 'sent-a');
  assert.equal(repo.localSentMessage('a', '<same@test>').body, message.body);
  assert.equal(repo.localSentMessage('missing', '<same@test>'), null);
  const sync = repo.syncMessageHeaders('a', 'INBOX');
  assert.ok(sync.every(value => !Object.hasOwn(value, 'body') && !Object.hasOwn(value, 'html')
    && !Object.hasOwn(value, 'translation') && !Object.hasOwn(value, 'translationHTML')));
  assert.equal(repo.get('message', 'sent-a').translationHTML, message.translationHTML);
});

test('compact jobs omit duplicate results while retaining reply previews and reviewable tasks', async t => {
  const repo = await fixture(t);
  for (const task of ['summary', 'translate', 'attachment', 'reply', 'classify', 'attachmentBatch'])
    repo.put('job', { id: task, task, status: 'completed', result: { text: '完整结果', body: '回复预览', items: [] } });
  for (const job of repo.jobHeaders()) {
    assert.equal(Object.hasOwn(job, 'result'), !['summary', 'translate', 'attachment'].includes(job.task));
    assert.ok(repo.get('job', job.id).result);
  }
});

test('an automatic disk-full rollback clears uncommitted previews and leaves the store usable', async t => {
  const repo = await fixture(t);
  repo.put('message', { ...message, html: null });
  const pages = repo.db.prepare('PRAGMA page_count').get().page_count;
  repo.db.exec(`PRAGMA max_page_count=${pages}`);
  assert.throws(() => repo.transaction(() => {
    repo.put('message', { ...message, html: null, body: '未提交的正文' });
    assert.equal(repo.messageHeaders()[0].preview, '未提交的正文');
    repo.put('message', { ...message, id: 'too-large', body: 'x'.repeat(1024 * 1024) });
  }), /database or disk is full/);
  assert.equal(repo.db.isTransaction, false);
  assert.equal(repo.get('message', 'm1').body, message.body);
  assert.equal(repo.messageHeaders()[0].preview, message.body);
  assert.equal(repo.get('message', 'too-large'), null);
  repo.put('message', { ...message, html: null, starred: true });
  assert.equal(repo.get('message', 'm1').starred, true);
  assert.equal(repo.db.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
});
