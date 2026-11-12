import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-attachment-page-'));
  const token = 'synthetic-attachment-pagination-session';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  for (const id of ['a', 'b']) {
    app.repo.put('account', { id, name: id, email: `${id}@example.test`, isDemo: true });
    app.repo.put('message', { id: id + '-mail', accountId: id, subject: id + ' subject', sender: id,
      date: id === 'a' ? '2026-11-10T12:00:00Z' : '2026-11-09T12:00:00Z', body: 'private mail body',
      folder: 'inbox', attachmentIds: [] });
  }
  const put = (id, extra = {}) => app.repo.put('attachment', { id, messageId: 'a-mail',
    name: `file ${id}.txt`, contentType: 'text/plain', size: 100, path: '/synthetic/file.txt',
    date: '2000-01-01', text: '', parseError: '', ...extra });
  async function get(query, authorized = true) {
    const res = await fetch(`http://127.0.0.1:${app.port}/attachments?${query}`,
      { headers: authorized ? { 'X-Boxmail-Token': token } : {} });
    return { status: res.status, value: await res.json() };
  }
  return { ...app, get, put };
}

test('a large account is globally sorted and returned as compact nonoverlapping pages', async t => {
  const { repo, get, put } = await fixture(t);
  const text = 'extracted content '.repeat(2000);
  repo.transaction(() => { for (let i = 0; i < 1005; i++) put(String(i), { text }); });
  // Pagination must never materialize all attachments or their parent mail bodies in JS.
  const list = repo.list.bind(repo), read = repo.get.bind(repo);
  repo.list = (kind, ...args) => { assert.notEqual(kind, 'attachment'); return list(kind, ...args); };
  repo.get = (kind, ...args) => { assert.notEqual(kind, 'message'); return read(kind, ...args); };
  const first = (await get('accountId=a&limit=50&sort=name&direction=asc')).value;
  const second = (await get('accountId=a&limit=50&sort=name&direction=asc&offset=50')).value;
  const last = (await get('accountId=a&limit=50&sort=name&direction=asc&offset=1000')).value;
  assert.equal(first.total, 1005);
  assert.equal(first.accountTotal, 1005);
  assert.equal(first.items.length, 50);
  assert.deepEqual(first.items.slice(0, 4).map(x => x.attachment.name), ['file 0.txt', 'file 1.txt', 'file 2.txt', 'file 3.txt']);
  assert.equal(second.items[0].attachment.name, 'file 50.txt');
  assert.equal(last.items.length, 5);
  assert.equal(last.items[4].attachment.name, 'file 1004.txt');
  assert.equal(new Set([...first.items, ...second.items, ...last.items].map(x => x.attachment.id)).size, 105);
  assert.ok(Buffer.byteLength(JSON.stringify(first)) < 65536);
  assert.ok(first.items.every(x => x.attachment.text === '' && x.attachment.hasExtractedText));
  assert.deepEqual(Object.keys(first.items[0].source).sort(), ['date', 'id', 'sender', 'subject']);
  assert.ok(first.items.every(item => !Object.hasOwn(item.attachment,'path')));
  assert.equal(first.items[0].source.date, '2026-11-10T12:00:00Z');
});

test('search and type filters run before paging and preserve ZIP status without archive payloads', async t => {
  const { get, put } = await fixture(t);
  for (let i = 0; i < 80; i++) put('pdf-' + i, { name: `report ${i}.pdf`, contentType: 'application/pdf', text: '共同词' });
  put('zip', { name: '资料包.ZIP', contentType: 'application/octet-stream', analysis: '整体整理',
    archive: { hash: 'a'.repeat(64), totalFiles: 2, omitted: 0, status: 'partial', entries: [
      {id:'0',status:'completed',path:'跨页唯一来源.txt',name:'跨页唯一来源.txt',size:1,contentType:'text/plain'},
      {id:'1',status:'unsupported',path:'other.bin',name:'other.bin',size:1,contentType:'application/octet-stream'}] } });
  const found = (await get('accountId=a&type=archive&q=' + encodeURIComponent('跨页唯一来源'))).value;
  assert.equal(found.total, 1);
  assert.equal(found.accountTotal, 81);
  assert.equal(found.analyzedTotal, 1);
  assert.equal(found.items[0].attachment.hasPartialAnalysis, true);
  assert.equal(found.items[0].attachment.archive, undefined);
  assert.equal(found.items[0].attachment.analysis, undefined);
  assert.equal((await get('accountId=a&type=pdf&q=' + encodeURIComponent('跨页唯一来源'))).value.total, 0);
  assert.equal((await get('accountId=a&type=pdf&q=' + encodeURIComponent('共同词') + '&offset=50')).value.items.length, 30);
});

test('paging isolates accounts, validates parameters and clamps a page after deletions', async t => {
  const { repo, get, put } = await fixture(t);
  put('a'); put('b', { messageId: 'b-mail' }); put('orphan', { messageId: 'deleted-mail' });
  assert.deepEqual((await get('accountId=a')).value.items.map(x => x.id ?? x.attachment.id), ['a']);
  assert.equal((await get('accountId=b')).value.accountTotal, 1);
  assert.equal((await get('')).value.total, 0);
  assert.equal((await get('accountId=a', false)).status, 403);
  for (const parameter of ['limit=101', 'limit=0', 'offset=-1', 'offset=1.2', 'sort=unknown', 'type=unknown', 'direction=unknown'])
    assert.equal((await get('accountId=a&' + parameter)).status, 400, parameter);
  const clamped = (await get('accountId=a&offset=1000')).value;
  assert.equal(clamped.offset, 0);
  repo.remove('attachment', 'a');
  const empty = (await get('accountId=a&offset=1000')).value;
  assert.equal(empty.offset, 0);
  assert.equal(empty.total, 0);
});

test('size and date sorting use global source metadata and deterministic ties', async t => {
  const { repo, get, put } = await fixture(t);
  repo.put('message', { id: 'older', accountId: 'a', subject: 'Older', sender: 'A', date: '2026-01-01' });
  put('small', { size: 10 }); put('large', { size: 900 }); put('old', { size: 500, messageId: 'older' });
  assert.equal((await get('accountId=a&sort=size&direction=desc&limit=1')).value.items[0].attachment.id, 'large');
  assert.equal((await get('accountId=a&sort=size&direction=asc&limit=1')).value.items[0].attachment.id, 'small');
  assert.equal((await get('accountId=a&sort=date&direction=asc&limit=1')).value.items[0].attachment.id, 'old');
});


test('known Office extensions override a ZIP MIME in attachment filters',async t=>{
  const {get,put}=await fixture(t);
  put('word',{name:'合同.docx',contentType:'application/zip'});
  put('slides',{name:'幻灯片.pptx',contentType:'application/zip'});
  assert.equal((await get('accountId=a&type=archive')).value.total,0);
  assert.deepEqual((await get('accountId=a&type=word')).value.items.map(item=>item.attachment.id),['word']);
  assert.deepEqual((await get('accountId=a&type=presentation')).value.items.map(item=>item.attachment.id),['slides']);
});
