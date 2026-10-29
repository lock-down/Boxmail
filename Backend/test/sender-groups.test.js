import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';

const base = { accountId: 'a', folder: 'inbox', sender: 'LINUX DO', senderEmail: 'digest@example.test',
  to: 'reader@example.test', cc: '', subject: '摘要', body: '本周社区更新与合同说明', preview: '社区更新',
  date: '2026-10-26T09:00:00Z', category: '未分类', unread: true, starred: false, attachmentIds: [] };
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-sender-groups-'));
  const repo = new Repository(directory);
  repo.put('account', { id: 'a', name: '工作', email: 'reader@example.test' });
  repo.put('account', { id: 'b', name: '个人', email: 'other@example.test' });
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return { repo, directory };
}

test('sender aggregation paginates senders over the entire mailbox and projects only visible headers', async t => {
  const { repo } = await fixture(t);
  for (let i = 0; i < 250; i++) repo.put('message', { ...base, id: `digest-${String(i).padStart(3, '0')}`,
    date: new Date(Date.parse(base.date) - i * 86400000).toISOString(), unread: i < 7 });
  repo.put('message', { ...base, id: 'other', senderEmail: 'someone@example.test', date: '2026-10-25T09:00:00Z' });
  let projections = 0;
  const original = repo.messageHeader.bind(repo);
  repo.messageHeader = (...args) => { projections++; return original(...args); };
  const first = repo.messagePage({ accountId: 'a', folder: 'inbox', groupBy: 'sender', limit: 1 });
  assert.equal(first.total, 251);
  assert.equal(first.groupTotal, 2);
  assert.equal(first.nextOffset, 1);
  assert.equal(first.senderGroups[0].count, 250);
  assert.equal(first.senderGroups[0].unreadCount, 7);
  assert.equal(projections, 1);
  assert.equal(first.messages[0].body, '');
  assert.equal(first.messages[0].bodyLoaded, false);
  assert.equal(first.messages[0].html, undefined);
  const next = repo.messagePage({ accountId: 'a', folder: 'inbox', groupBy: 'sender', limit: 1, offset: 1 });
  assert.equal(next.messages[0].id, 'other');
  assert.equal(next.nextOffset, null);
  const group = first.senderGroups[0].id;
  const pages = [0, 100, 200].map(offset => repo.messagePage({ accountId: 'a', folder: 'inbox', senderGroup: group, offset, limit: 100 }));
  assert.deepEqual(pages.map(page => page.messages.length), [100, 100, 50]);
  assert.deepEqual(pages.map(page => page.nextOffset), [100, 200, null]);
  assert.equal(new Set(pages.flatMap(page => page.messages.map(message => message.id))).size, 250);
  assert.equal(pages[2].messages.at(-1).id, 'digest-249');
});

test('sender identities normalize address case and whitespace while preserving account and unknown-sender boundaries', async t => {
  const { repo } = await fixture(t);
  for (const message of [
    { id: 'one', senderEmail: ' Digest@Example.Test ', sender: 'First name' },
    { id: 'two', senderEmail: 'digest@example.test', sender: 'Renamed sender' },
    { id: 'foreign', senderEmail: 'digest@example.test', accountId: 'b' },
    { id: 'different-address', senderEmail: 'alerts@example.test', sender: 'First name' },
    { id: 'unknown-one', senderEmail: '' }, { id: 'unknown-two', senderEmail: '' },
    { id: 'unicode-one', senderEmail: 'Ä@example.test' }, { id: 'unicode-two', senderEmail: 'ä@example.test' },
  ]) repo.put('message', { ...base, ...message });
  const page = repo.messagePage({ groupBy: 'sender' });
  assert.equal(page.total, 8);
  assert.equal(page.groupTotal, 6);
  assert.equal(page.senderGroups.find(group => group.accountId === 'a' && group.senderEmail === 'digest@example.test').count, 2);
  assert.equal(page.senderGroups.find(group => group.senderEmail === 'ä@example.test').count, 2);
  assert.equal(page.senderGroups.filter(group => group.senderEmail === '').length, 2);
});

test('group and member order use actual timestamps and stable ids when dates tie', async t => {
  const { repo } = await fixture(t);
  for (const message of [
    { id: 'a', date: '2026-10-26T03:00:00-07:00' },
    { id: 'b', date: '2026-10-26T10:00:00Z' },
    { id: 'c', date: '2026-10-26T11:00:00+02:00' },
    { id: 'other', date: '2026-10-26T09:30:00Z', senderEmail: 'other@example.test' },
  ]) repo.put('message', { ...base, ...message });
  const page = repo.messagePage({ groupBy: 'sender' });
  assert.deepEqual(page.messages.map(message => message.id), ['a', 'other']);
  assert.deepEqual(repo.messagePage({ senderGroup: page.senderGroups[0].id }).messages.map(message => message.id), ['a', 'b', 'c']);
});

test('aggregation and expansion retain search, folder, unread and attachment filters with correct snippets', async t => {
  const { repo } = await fixture(t);
  repo.put('message', { ...base, id: 'match', folder: 'archive', attachmentIds: ['file'] });
  repo.put('message', { ...base, id: 'read', folder: 'archive', unread: false, attachmentIds: ['file'] });
  repo.put('message', { ...base, id: 'other-folder', attachmentIds: ['file'] });
  repo.put('message', { ...base, id: 'no-attachment', folder: 'archive' });
  const options = { accountId: 'a', folder: 'inbox', query: 'folder:archive 合同 has:attachment', filter: '未读' };
  await repo.searchIndex.drain();
  const page = repo.messagePage({ ...options, groupBy: 'sender' });
  assert.equal(page.total, 1);
  assert.equal(page.senderGroups[0].count, 1);
  const children = repo.messagePage({ ...options, senderGroup: page.senderGroups[0].id });
  assert.deepEqual(children.messages.map(message => message.id), ['match']);
  assert.ok(children.messages[0].searchSnippet.includes('合同'));
});

test('revealing an older mail includes its sender outside the first sender page without leaking filtered mail', async t => {
  const { repo } = await fixture(t);
  repo.put('message', { ...base, id: 'first', senderEmail: 'first@example.test' });
  repo.put('message', { ...base, id: 'old-head', date: '2026-09-01T00:00:00Z' });
  repo.put('message', { ...base, id: 'target', date: '2026-08-01T00:00:00Z' });
  repo.put('message', { ...base, id: 'deleted', folder: 'trash' });
  const page = repo.messagePage({ accountId: 'a', folder: 'inbox', groupBy: 'sender', limit: 1, revealId: 'target' });
  assert.deepEqual(page.messages.map(message => message.id), ['first', 'old-head']);
  assert.equal(page.revealedMessage.id, 'target');
  assert.equal(page.groupTotal, 2);
  assert.equal(page.nextOffset, 1);
  const filtered = repo.messagePage({ accountId: 'a', folder: 'inbox', groupBy: 'sender', limit: 1, revealId: 'deleted' });
  assert.equal(filtered.messages.length, 1);
  assert.equal(filtered.revealedMessage, null);
});

test('draft search remains an individual chronological list when sender grouping is requested', async t => {
  const { repo } = await fixture(t);
  repo.put('draft', { id: 'draft', accountId: 'a', to: 'someone@example.test', cc: '', bcc: '', subject: '草稿',
    body: '尚未发送', status: 'draft', updatedAt: base.date, attachmentIds: [] });
  const page = repo.messagePage({ accountId: 'a', query: 'folder:drafts', groupBy: 'sender' });
  assert.equal(page.messages[0].draftId, 'draft');
  assert.equal(page.senderGroups, undefined);
});

test('grouped pagination reflects writes, direct SQL, rollback and changed search filters', async t => {
  const { repo } = await fixture(t);
  const options = { accountId: 'a', folder: 'inbox', groupBy: 'sender', limit: 1 };
  repo.put('message', { ...base, id: 'first' });
  const initial = repo.messagePage(options);
  const id = initial.senderGroups[0].id;
  repo.put('message', { ...base, id: 'second' });
  assert.equal(repo.messagePage({ ...options, senderGroup: id }).total, 2);
  repo.db.prepare("UPDATE records SET data=json_set(data,'$.unread',json('false')) WHERE kind='message' AND id=?").run('first');
  assert.equal(repo.messagePage(options).senderGroups[0].unreadCount, 1);
  assert.throws(() => repo.transaction(() => {
    repo.remove('message', 'first');
    assert.equal(repo.messagePage(options).total, 1);
    throw new Error('rollback fixture');
  }), /rollback fixture/);
  assert.equal(repo.messagePage(options).total, 2);
  assert.equal(repo.messagePage({ ...options, filter: '未读' }).total, 1);
  assert.equal(repo.messagePage(options).total, 2);
  repo.remove('message', 'second');
  assert.equal(repo.messagePage({ ...options, senderGroup: id }).total, 1);
});

test('HTTP grouping contract encodes sender ids and rejects invalid options', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-sender-http-'));
  const token = 'sender-groups-http-test-token-012345';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('message', { ...base, id: 'new', senderEmail: 'a+b@example.test', folder: 'archive' });
  app.repo.put('message', { ...base, id: 'old', senderEmail: 'a+b@example.test', folder: 'archive', date: '2026-09-01T00:00:00Z' });
  const get = async query => {
    const response = await fetch(`http://127.0.0.1:${app.port}/messages?${query}`, { headers: { 'X-Boxmail-Token': token } });
    return { status: response.status, body: await response.json() };
  };
  const page = await get('groupBy=sender&folder=archive');
  assert.equal(page.status, 200);
  assert.equal(page.body.senderGroups[0].count, 2);
  assert.equal(page.body.messages[0].unarchiveFolder, 'inbox');
  const members = await get(new URLSearchParams({ senderGroup: page.body.senderGroups[0].id, folder: 'archive' }));
  assert.deepEqual(members.body.messages.map(message => message.id), ['new', 'old']);
  assert.equal((await get('groupBy=subject')).status, 400);
  assert.equal((await get('groupBy=sender&limit=201')).status, 400);
});
