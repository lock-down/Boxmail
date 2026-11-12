import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-organization-page-'));
  const token = 'organization-pagination-synthetic-token';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  for (const id of ['a', 'b']) app.repo.put('account', { id, isDemo: true });
  const put = (id, changes = {}) => app.repo.put('message', { id, accountId: 'a', folder: 'inbox',
    sender: '发件人', senderEmail: 'sender@example.test', to: '', cc: '', subject: id, body: '正文'.repeat(2000),
    html: '<p>完整正文</p>', preview: 'preview', date: '2026-11-11T08:00:00Z', category: '工作项目',
    unread: true, starred: false, attachmentIds: [], summary: { overview: '分析'.repeat(2000) }, ...changes });
  const get = async (query, authorized = true) => {
    const response = await fetch(`http://127.0.0.1:${app.port}/organization/messages?${query}`, {
      headers: authorized ? { 'X-Boxmail-Token': token } : {},
    });
    return { status: response.status, body: await response.json() };
  };
  return { ...app, put, get };
}

test('organization pages are bounded, globally ordered and keep full category counts without loading bodies', async t => {
  const { repo, put, get } = await fixture(t);
  repo.transaction(() => {
    for (let i = 0; i < 1105; i++) put(`m${String(i).padStart(4, '0')}`, { category: i % 2 ? '工作项目' : '未分类' });
    put('other-account', { accountId: 'b' }); put('sent', { folder: 'sent' });
  });
  const list = repo.list.bind(repo), read = repo.get.bind(repo);
  repo.list = (kind, ...args) => { assert.notEqual(kind, 'message'); return list(kind, ...args); };
  repo.get = (kind, ...args) => { assert.notEqual(kind, 'message'); return read(kind, ...args); };
  const first = (await get('accountId=a')).body;
  const second = (await get('accountId=a&offset=50')).body;
  assert.equal(first.accountTotal, 1105); assert.equal(first.total, 1105);
  assert.equal(first.items.length, 50); assert.equal(first.items[0].id, 'm0000');
  assert.equal(second.items.length, 50); assert.equal(second.items[0].id, 'm0050');
  assert.equal(new Set([...first.items, ...second.items].map(item => item.id)).size, 100);
  assert.equal(first.categoryCounts.find(row => row.name === '未分类').count, 553);
  assert.equal(first.categoryCounts.find(row => row.name === '工作项目').count, 552);
  assert.ok(first.items.every(item => item.body === '' && item.bodyLoaded === false && !item.html && !item.summary));
  assert.equal(typeof first.items[0].unread, 'boolean'); assert.equal(typeof first.items[0].starred, 'boolean');
  assert.ok(Buffer.byteLength(JSON.stringify(first)) < 50000);
});

test('organization filters the full inbox before paging and adjusts stale offsets after deletions', async t => {
  const { repo, put, get } = await fixture(t);
  for (let i = 0; i < 105; i++) put(`work${i}`);
  put('uncategorized', { category: '' }); put('null-category', { category: null });
  put('default-category', { category: '未分类' }); put('foreign', { accountId: 'b' });
  let page = (await get(`accountId=a&category=${encodeURIComponent('工作项目')}&offset=100`)).body;
  assert.equal(page.total, 105); assert.equal(page.items.length, 5); assert.equal(page.offset, 100);
  assert.equal(page.accountTotal, 108);
  for (let i = 5; i < 105; i++) repo.remove('message', `work${i}`);
  page = (await get(`accountId=a&category=${encodeURIComponent('工作项目')}&offset=100`)).body;
  assert.equal(page.offset, 0); assert.equal(page.items.length, 5);
  const uncategorized = (await get(`accountId=a&category=${encodeURIComponent('未分类')}`)).body;
  assert.equal(uncategorized.total, 3);
  assert.deepEqual(uncategorized.items.map(item => item.id), ['default-category', 'null-category', 'uncategorized']);
  assert.ok(uncategorized.items.every(item => item.category === '未分类'));
  assert.equal(uncategorized.categoryCounts.find(row => row.name === '未分类').count, 3);
  assert.equal((await get('accountId=b')).body.total, 1);
  const empty = (await get('accountId=a&category=missing')).body;
  assert.equal(empty.total, 0); assert.equal(empty.offset, 0); assert.deepEqual(empty.items, []);
});

test('organization pages authenticate and reject invalid paging without leaking another account', async t => {
  const { put, get } = await fixture(t); put('mail');
  assert.equal((await get('accountId=a', false)).status, 403);
  for (const query of ['offset=-1', 'offset=1.5', 'offset=NaN', 'limit=101', 'limit=-1', 'limit=1.5', `category=${'x'.repeat(201)}`])
    assert.equal((await get(`accountId=a&${query}`)).status, 400, query);
  assert.equal((await get('')).body.total, 0);
});
