import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { buildReplyDraft } from '../src/reply.js';

const token = 'boxmail-startup-contract-session-20261024';
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-startup-test-'));
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a', name: '测试', email: 'reader@example.test', isDemo: true };
  app.repo.put('account', account);
  for (let i = 0; i < 20; i++) app.repo.put('message', {
    id: `m${i}`, accountId: 'a', folder: 'inbox', sender: '测试发件人', senderEmail: 'sender@example.test',
    to: account.email, cc: '', subject: `项目 ${i}`, body: '可读正文\n--\n测试签名',
    html: '<p>可读正文</p><div class="signature">测试签名</div>', preview: '过时预览',
    date: `2026-10-24T08:00:${String(i).padStart(2, '0')}Z`, category: '未分类',
    unread: false, starred: false, attachmentIds: [], messageId: `<m${i}@example.test>`,
  });
  const reads = [];
  const get = app.repo.get.bind(app.repo);
  app.repo.get = (kind, id) => { if (kind === 'message') reads.push(id); return get(kind, id); };
  return { ...app, account, reads, get,
    async request(route) {
      const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': token } });
      assert.equal(response.status, 200);
      return response.json();
    } };
}

test('startup metadata defers body previews while the first page and legacy snapshot keep filtered previews', async t => {
  const { request, reads, repo } = await fixture(t);
  const state = await request('/state?compact=1&previews=0');
  assert.equal(state.messages.length, 20);
  assert.equal(reads.length, 0);
  assert.ok(state.messages.every(message => message.bodyLoaded === false && message.body === '' && message.preview === ''));
  const page = await request('/messages?accountId=a&folder=inbox&limit=5');
  assert.equal(page.total, 20);
  assert.equal(reads.length, 5);
  assert.ok(page.messages.every(message => message.preview === '可读正文'));
  const next = await request('/state?compact=1&previews=0');
  assert.equal(reads.length, 5);
  assert.equal(next.messages.filter(message => message.preview === '可读正文').length, 5);
  const legacy = await request('/state?compact=1');
  assert.ok(legacy.messages.every(message => message.preview === '可读正文'));
  assert.equal(repo.get('message', 'm0').preview, '过时预览');
});

test('conversation graph reads only the bodies needed for the returned thread page', async t => {
  const { repo, request, reads, get } = await fixture(t);
  repo.put('message', { ...get('message', 'm1'), references: ['<m0@example.test>'] });
  const thread = await request('/messages/m0/thread?limit=1');
  assert.equal(thread.total, 2);
  assert.equal(thread.messages[0].id, 'm0');
  assert.equal(thread.messages[0].preview, '可读正文');
  assert.deepEqual(new Set(reads), new Set(['m0']));
  reads.length = 0;
  const next = await request('/messages/m0/thread?limit=1&offset=1');
  assert.equal(next.messages[0].id, 'm1');
  assert.deepEqual(new Set(reads), new Set(['m0', 'm1']));
});

test('snapshot skips source bodies for replies and forwards that already have a saved quotation', async t => {
  const { repo, account, get, reads, request } = await fixture(t);
  const source = get('message', 'm0');
  repo.put('draft', buildReplyDraft(source, account));
  repo.put('draft', buildReplyDraft(source, account, { forward: true }));
  reads.length = 0;
  const state = await request('/state?compact=1&previews=0');
  assert.equal(state.drafts.length, 2);
  assert.ok(state.drafts.every(draft => !draft.bodyLoaded && draft.body === '' && draft.forwardedHTML === undefined));
  assert.equal(reads.length, 0);
});

test('initial category catalog preserves custom names without materializing every mail body', async t => {
  const { repo, request, get } = await fixture(t);
  repo.put('message', { ...get('message', 'm0'), category: '已有自定义分类' });
  repo.remove('categoryCatalog', 'categories');
  const list = repo.list.bind(repo);
  repo.list = (kind, options) => {
    assert.notEqual(kind, 'message', 'metadata initialization must not read every body');
    return list(kind, options);
  };
  const state = await request('/state?compact=1&previews=0');
  assert.ok(state.categories.some(category => category.name === '已有自定义分类'));
  assert.ok(state.categories.some(category => category.name === '未分类'));
});

test('state responses bound large forward drafts and full edit and reading endpoints preserve complete content', async t => {
  const { repo, request } = await fixture(t);
  const forwardedText = 'Original forwarded text ' + 'x'.repeat(20 * 1024 * 1024);
  const draft = { id: 'large-forward', accountId: 'a', to: 'recipient@example.test', cc: '', bcc: '',
    subject: 'Large forward', body: 'Editable notes', forwardedText, forwardedHTML: '', attachmentIds: [],
    updatedAt: '2026-10-28T00:00:00Z', status: 'draft' };
  repo.put('draft', draft);
  repo.activeDrafts = () => { throw new Error('state must not materialize full drafts'); };
  for (const route of ['/state?compact=1&previews=0', '/state?compact=1', '/state']) {
    const state = await request(route);
    assert.ok(Buffer.byteLength(JSON.stringify(state)) < 64000, route);
    assert.equal(state.drafts[0].bodyLoaded, false);
    assert.equal(state.drafts[0].body, '');
    assert.equal(state.drafts[0].forwardedText, undefined);
    assert.equal(state.drafts[0].forwardedHTML, undefined);
    assert.match(state.drafts[0].preview, /Editable notes/);
  }
  const editable = await request('/drafts/large-forward');
  assert.equal(editable.bodyLoaded, true);
  assert.equal(editable.body, draft.body);
  assert.equal(editable.forwardedText, forwardedText);
  const readable = await request('/messages/draft:large-forward');
  assert.equal(readable.body, draft.body + '\n\n' + forwardedText);
  assert.deepEqual(repo.get('draft', draft.id), draft);
});

test('saving a light draft header is rejected before it can replace the complete stored draft', async t => {
  const { repo, request, port } = await fixture(t);
  const draft = buildReplyDraft(repo.get('message', 'm0'), {}, { forward: true });
  repo.put('draft', draft);
  const state = await request('/state?compact=1');
  const response = await fetch(`http://127.0.0.1:${port}/drafts`, { method: 'POST',
    headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify(state.drafts[0]) });
  assert.equal(response.status, 409);
  assert.deepEqual(repo.get('draft', draft.id), draft);
});
