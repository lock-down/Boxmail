import { responsesWire } from './helpers/ai-streams.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { categoryCatalog, editCategory } from '../src/categories.js';
import { Organizer } from '../src/organizer.js';
import { approveClassification } from '../src/agent.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { contactSuggestions } from '../src/contacts.js';
import { conversation } from '../src/threads.js';
import { parseSearch } from '../src/search-query.js';
import { startServer } from '../src/server.js';
import http from 'node:http';

const base = { accountId: 'a', folder: 'inbox', sender: '张三', senderEmail: 'zhang@example.com',
  to: '我 <me@example.com>', cc: '', bcc: '', subject: '合同进展', body: '请核对本季度付款发票和 FY2026 合同',
  date: '2026-10-21T09:00:00Z', preview: '付款发票与合同', category: '未分类', attachmentIds: [], unread: true, starred: false };
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-priority-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('account', { id: 'a', name: '工作', email: 'me@example.com', aliases: ['alias@example.com'] });
  repo.put('account', { id: 'b', name: '个人', email: 'other@example.com' });
  repo.put('message', { ...base, id: 'm' });
  return { repo, directory };
}

test('custom categories persist, reject duplicates, rename mail and history, and delete into unclassified', async t => {
  const { repo, directory } = await fixture(t);
  const result = editCategory(repo, null, { name: ' 合同审批 ', description: '合同、补充协议与审批进度' });
  const category = result.categories.find(item => item.name === '合同审批');
  assert.ok(category);
  assert.throws(() => editCategory(repo, null, { name: '合同审批' }), /同名/);
  assert.throws(() => editCategory(repo, null, { name: '\n' }), /1 至 32/);
  repo.put('message', { ...repo.get('message', 'm'), category: category.name });
  repo.put('job', { id: 'j', task: 'classify', status: 'applied', categories: categoryCatalog(repo), result: {
    items: [{ id: 'm', category: category.name }], previous: [{ id: 'm', category: category.name }],
  } });
  editCategory(repo, category.id, { name: '项目合同' });
  assert.equal(repo.get('message', 'm').category, '项目合同');
  assert.equal(repo.get('job', 'j').result.previous[0].category, '项目合同');
  editCategory(repo, category.id, {}, true);
  assert.equal(repo.get('message', 'm').category, '未分类');
  assert.equal(repo.get('job', 'j').result.items[0].category, '未分类');
  assert.ok(!repo.get('job', 'j').categories.some(item => item.id === category.id));
  assert.throws(() => editCategory(repo, 'unclassified', {}, true), /不能修改或删除/);
  const defaultCategory = categoryCatalog(repo).find(item => item.name === '订阅资讯');
  editCategory(repo, defaultCategory.id, {}, true);
  const reopened = new Repository(directory);
  assert.ok(!categoryCatalog(reopened).some(item => item.name === '订阅资讯'));
  reopened.close();
});

test('AI organization accepts configured category descriptions, rejects invented labels, and confirms and undoes', async t => {
  const { repo } = await fixture(t);
  editCategory(repo, null, { name: '合同审批', description: '只收审批中的合同' });
  const manager = new Organizer(repo, { complete: async (config, key, task, context, images, options) => {
    assert.ok(options.categories.some(item => item.name === '合同审批' && item.description === '只收审批中的合同'));
    return { items: [{ id: 'm', category: '合同审批', reason: '审批合同' }, { id: 'foreign', category: '合同审批' }] };
  } });
  t.after(() => manager.close());
  const job = manager.start({ accountId: 'a', config: { ...DEFAULT_AI, baseURL: 'http://localhost:12345' } });
  await manager.workers.get(job.id).promise;
  assert.equal(repo.get('message', 'm').category, '未分类');
  approveClassification(repo, job.id);
  assert.equal(repo.get('message', 'm').category, '合同审批');
  approveClassification(repo, job.id, true);
  assert.equal(repo.get('message', 'm').category, '未分类');
});

test('full text index finds Chinese two-character and sentence-internal terms, filenames, AI text and mixed words', async t => {
  const { repo } = await fixture(t);
  repo.put('attachment', { id: 'f', messageId: 'm', name: '深圳采购合同.xlsx', text: '隐含成本与履约条款', analysis: '付款上限为300万元' });
  repo.put('message', { ...repo.get('message', 'm'), attachmentIds: ['f'], summary: { overview: '审批事项' }, translation: 'translation needle' });
  repo.put('job', { id: 'reply', messageId: 'm', result: { body: '已收到审阅意见' } });
  for (const query of ['发票', '季度付款', 'FY2026', '采购合同', '隐含成本', '上限', '300万', '审批', '审阅意见', 'translation'])
    assert.deepEqual(repo.messagePage({ query }).messages.map(m => m.id), ['m'], query);
  assert.deepEqual(repo.messagePage({ query: '付款 FY2026' }).messages.map(m => m.id), ['m']);
  assert.deepEqual(repo.messagePage({ query: '不存在的内容' }).messages, []);
  const snippet = repo.messagePage({ query: '发票' }).messages[0].searchSnippet;
  assert.equal(snippet, '请核对本季度付款发票和 fy2026 合同');
  assert.ok(!repo.messagePage({ query: '审批' }).messages[0].searchSnippet.includes('overview'));
});

test('index updates after attachment understanding, message moves, deletes, rollback, restart and explicit rebuild', async t => {
  const { repo, directory } = await fixture(t);
  repo.put('attachment', { id: 'f', messageId: 'm', name: '文件', text: '', analysis: '' });
  assert.equal(repo.search('新理解').length, 0);
  repo.put('attachment', { ...repo.get('attachment', 'f'), analysis: '新理解结论' });
  assert.equal(repo.search('新理解').length, 1);
  assert.throws(() => repo.transaction(() => { repo.put('message', { ...repo.get('message', 'm'), body: '不该保留' }); throw new Error('rollback'); }));
  assert.equal(repo.search('不该保留').length, 0);
  repo.put('message', { ...repo.get('message', 'm'), folder: 'archive' });
  assert.equal(repo.search('folder:archive 合同').length, 1);
  const reopened = new Repository(directory);
  assert.equal(reopened.search('新理解').length, 1);
  reopened.rebuildSearch();
  assert.equal(reopened.search('新理解').length, 1);
  reopened.close();
  repo.remove('message', 'm');
  assert.equal(repo.search('新理解').length, 0);
});

test('combined search conditions agree with pagination and preserve account, folder, recipient and exact identity', async t => {
  const { repo } = await fixture(t);
  for (let i = 0; i < 5; i++) repo.put('message', { ...base, id: `b${i}`, accountId: 'b', folder: 'sent',
    bcc: 'audit@example.com', attachmentIds: ['f'], date: `2026-10-${20 + (i % 2)}T10:00:00Z` });
  const query = '合同 from:zhang to:audit after:2026-10-20 before:2026-10-22 is:unread has:attachment account:other@example.com folder:sent';
  const first = repo.messagePage({ accountId: 'a', query, limit: 2 });
  const second = repo.messagePage({ accountId: 'a', query, offset: first.nextOffset, limit: 2 });
  const last = repo.messagePage({ accountId: 'a', query, offset: second.nextOffset, limit: 2 });
  assert.equal(first.total, 5);
  assert.equal(last.nextOffset, null);
  const items = [...first.messages, ...second.messages, ...last.messages];
  assert.equal(new Set(items.map(m => m.id)).size, 5);
  assert.ok(items.every(m => m.accountId === 'b' && m.folder === 'sent'));
  assert.equal(repo.search('before:2026-10-21 account:个人').length, 3);
  assert.equal(repo.search('from:"张三" is:read').length, 0);
  for (const invalid of ['is:whatever', 'has:pdf', 'after:2026-02-30', 'after:2026-10-22 before:2026-10-21', 'folder:whatever', 'from:', 'unknown:test', '"未闭合'])
    assert.throws(() => parseSearch(invalid), undefined, invalid);
});

test('search dates follow the local calendar day rather than UTC midnight', async t => {
  const previous = process.env.TZ;
  process.env.TZ = 'Asia/Shanghai';
  t.after(() => { if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous; });
  const { repo } = await fixture(t);
  repo.put('message', { ...base, id: 'night', date: '2026-10-20T18:00:00Z' });
  assert.ok(repo.search('after:2026-10-21').some(m => m.id === 'night'));
  assert.ok(!repo.search('before:2026-10-21').some(m => m.id === 'night'));
});

test('draft status searches local unsent drafts with account, date, recipient, attachment and pagination conditions', async t => {
  const { repo } = await fixture(t);
  const draft = { id: 'd', accountId: 'a', subject: '采购合同', body: '请复核履约条款', to: 'finance@example.com',
    cc: '', bcc: 'audit@example.com', status: 'draft', updatedAt: '2026-10-21T09:00:00Z', attachmentIds: ['df'] };
  repo.put('attachment', { id: 'df', name: '审批清单.txt', text: '预算上限为三百万元', analysis: '' });
  repo.put('draft', draft);
  repo.put('draft', { ...draft, id: 'older', updatedAt: '2026-10-20T09:00:00Z' });
  repo.put('draft', { ...draft, id: 'foreign-draft', accountId: 'b' });
  repo.put('draft', { ...draft, id: 'already-sent', status: 'sent' });
  const page = repo.messagePage({ accountId: 'a', query: 'folder:drafts 合同 to:audit has:attachment', limit: 1 });
  assert.equal(page.total, 2);
  assert.equal(page.messages[0].id, 'draft:d');
  assert.equal(page.messages[0].draftId, 'd');
  assert.equal(page.messages[0].bodyLoaded, true);
  assert.equal(page.messages[0].senderEmail, 'me@example.com');
  assert.equal(page.nextOffset, 1);
  assert.equal(repo.messagePage({ accountId: 'a', query: 'folder:drafts 合同', offset: 1, limit: 1 }).messages[0].draftId, 'older');
  assert.equal(repo.search('folder:草稿箱 预算 after:2026-10-21 before:2026-10-22', 'a').length, 1);
  assert.equal(repo.search('folder:drafts account:other@example.com', 'a')[0].draftId, 'foreign-draft');
  assert.equal(repo.search('folder:drafts is:unread', 'a').length, 0);
  repo.put('draft', { ...draft, body: '修改后的草稿正文' });
  assert.equal(repo.search('folder:drafts 修改后的', 'a')[0].draftId, 'd');
  repo.remove('draft', 'd');
  assert.equal(repo.search('folder:drafts 修改后的', 'a').length, 0);
});

test('reference chains join replies and missing ancestors across folders without subject or cross-account merging', async t => {
  const { repo } = await fixture(t);
  repo.put('message', { ...base, id: 'm', messageId: '<root@local>' });
  repo.put('message', { ...base, id: 'sent', folder: 'sent', messageId: '<reply@local>', references: ['<root@local>'], date: '2026-10-22T00:00:00Z' });
  repo.put('message', { ...base, id: 'next', folder: 'archive', inReplyTo: '<reply@local>', messageId: '<next@local>', date: '2026-10-23T00:00:00Z' });
  repo.put('message', { ...base, id: 'same-subject', messageId: '<other@local>' });
  repo.put('message', { ...base, id: 'foreign', accountId: 'b', references: ['<root@local>'] });
  assert.deepEqual(conversation(repo, 'm').messages.map(m => m.id), ['m', 'next', 'sent']);
  assert.equal(conversation(repo, 'same-subject').total, 1);
  assert.equal(conversation(repo, 'foreign').total, 1);
  repo.remove('message', 'm');
  repo.put('message', { ...base, id: 'branch', references: ['<root@local>'] });
  assert.equal(conversation(repo, 'next').total, 3);
  const page = conversation(repo, 'next', { limit: 2 });
  assert.equal(page.nextOffset, 2);
  assert.equal(conversation(repo, 'next', { offset: 2, limit: 2 }).messages.length, 1);
});

test('local contact suggestions match display names and addresses, rank frequency then recency, and keep accounts isolated', async t => {
  const { repo } = await fixture(t);
  repo.put('message', { ...base, id: 'c1', to: '"Last, First" <first@example.com>, alias@example.com', cc: 'FIRST@example.com' });
  repo.put('message', { ...base, id: 'c2', senderEmail: 'new@example.com', sender: '新联系人', to: 'first@example.com', date: '2026-10-22T00:00:00Z' });
  repo.put('message', { ...base, id: 'foreign', accountId: 'b', senderEmail: 'secret@example.com' });
  const contacts = contactSuggestions(repo, 'a').contacts;
  assert.ok(!contacts.some(c => ['me@example.com', 'alias@example.com', 'secret@example.com'].includes(c.email)));
  assert.equal(contactSuggestions(repo, 'a', 'Last, First').contacts[0].email, 'first@example.com');
  assert.equal(contactSuggestions(repo, 'a', 'first@').contacts[0].frequency, 2);
  assert.equal(contactSuggestions(repo, 'a', '新联系人').contacts[0].email, 'new@example.com');
});

test('contact suggestions keep the most recent known name when newer mail has only an address', async t => {
  const { repo } = await fixture(t);
  for (const [id, sender, date] of [
    ['contact-a', '旧名字', '2026-10-20T00:00:00Z'],
    ['contact-b', '', '2026-10-23T00:00:00Z'],
    ['contact-c', '新名字', '2026-10-22T00:00:00Z'],
  ]) repo.put('message', { ...base, id, sender, senderEmail: 'contact@example.com', date });
  assert.equal(contactSuggestions(repo, 'a', 'contact@example.com').contacts[0].name, '新名字');
});

test('API exposes dynamic categories, reference conversations, structured search, contacts and index maintenance', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-priority-api-'));
  const token = 'priority-api-test-session-token-0123';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('account', { id: 'a', name: '测试', email: 'me@example.com', username: 'me@example.com',
    imapHost: '', smtpHost: '', imapPort: 993, smtpPort: 465, imapTLS: true, smtpTLS: true, isDemo: true });
  app.repo.put('message', { ...base, id: 'm' });
  const request = async (route, body, method = body ? 'POST' : 'GET') => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method, headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    return { status: response.status, data: await response.json() };
  };
  assert.equal((await request('/categories', { name: '审批' })).status, 200);
  assert.ok((await request('/state?compact=1')).data.categories.some(item => item.name === '审批'));
  assert.equal((await request('/messages/m/thread')).data.accountId, 'a');
  assert.equal((await request('/contacts?accountId=a&q=zhang')).data.contacts[0].email, 'zhang@example.com');
  assert.equal((await request('/messages?q=folder%3Ainbox%20%E5%90%88%E5%90%8C')).data.total, 1);
  assert.equal((await request('/messages?q=is%3Abad')).status, 400);
  const saved = await request('/drafts', { accountId: 'a', subject: '本机草稿检索', body: '草稿正文', to: 'finance@example.com', attachmentIds: [] });
  assert.equal(saved.status, 200);
  const drafts = await request('/messages?accountId=a&q=folder%3Adrafts');
  assert.equal(drafts.data.total, 1);
  const draftMail = await request('/messages/' + drafts.data.messages[0].id);
  assert.equal(draftMail.data.draftId, saved.data.id);
  assert.equal(draftMail.data.body, '草稿正文');
  assert.equal((await request('/search/rebuild', {})).data.indexed, 1);
  const backup = path.join(directory, 'manual.zip');
  assert.equal((await request('/backups/create', { path: backup })).status, 200);
  const inspected = await request('/backups/inspect', { path: backup });
  assert.equal(inspected.data.counts.message, 1);
  assert.equal((await request('/backups/restore', { path: backup })).status, 403);
  assert.equal((await request('/backups/restore', { path: backup, approved: true, sha256: 'bad' })).status, 409);
  assert.equal((await request('/backups/restore', { path: backup, approved: true, sha256: inspected.data.sha256 })).status, 200);
});

test('data maintenance rejects concurrent edits and releases its lock after completing', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-maintenance-'));
  const token = 'priority-maintenance-token-012345';
  const entered = Promise.withResolvers(), finish = Promise.withResolvers();
  const app = await startServer({ directory, token, demo: false, backupCreate: async () => {
    entered.resolve(); await finish.promise; return { ok: true };
  } });
  t.after(async () => { finish.resolve(); await app.close(); await rm(directory, { recursive: true, force: true }); });
  const request = (route, body) => fetch(`http://127.0.0.1:${app.port}${route}`, {
    method: body ? 'POST' : 'GET', headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const pending = request('/backups/create', { path: '/unused-test-path.zip' });
  await entered.promise;
  assert.equal((await request('/categories', { name: '并发分类' })).status, 409);
  assert.equal((await request('/drafts', { accountId: 'a', body: '并发写入' })).status, 409);
  assert.equal((await request('/configuration/import', {})).status, 409);
  assert.equal((await request('/state?compact=1')).status, 200);
  finish.resolve();
  assert.equal((await pending).status, 200);
  assert.equal((await request('/categories', { name: '完成后分类' })).status, 200);
});

test('actual Responses request uses custom classification names and descriptions without requiring fixed labels', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-custom-model-'));
  let instructions;
  const model = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const input = JSON.parse(Buffer.concat(chunks).toString());
    instructions = input.instructions;
    res.setHeader('Content-Type', 'text/event-stream');
    res.end(responsesWire({ status: 'completed', output: [{ type: 'message', role: 'assistant', content: [
      { type: 'output_text', text: JSON.stringify({ items: [{ id: 'm', category: '合同审批', reason: '审批合同' }] }) },
    ] }] }));
  });
  await new Promise(resolve => model.listen(0, '127.0.0.1', resolve));
  const repo = new Repository(directory);
  repo.put('account', { id: 'a' }); repo.put('message', { ...base, id: 'm' });
  editCategory(repo, null, { name: '合同审批', description: '需要财务复核的合同' });
  const manager = new Organizer(repo);
  t.after(async () => { await manager.close(); repo.close(); await new Promise(resolve => model.close(resolve)); await rm(directory, { recursive: true, force: true }); });
  const job = manager.start({ accountId: 'a', config: { ...DEFAULT_AI, baseURL: `http://127.0.0.1:${model.address().port}/v1` } });
  await manager.workers.get(job.id).promise;
  assert.match(instructions, /合同审批/);
  assert.match(instructions, /需要财务复核的合同/);
  assert.equal(repo.get('job', job.id).result.items[0].category, '合同审批');
  assert.equal(repo.get('message', 'm').category, '未分类');
});
