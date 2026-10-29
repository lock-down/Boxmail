import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { conversation } from '../src/threads.js';
import { mailPreview } from '../src/mail-preview.js';
import { DatabaseSync } from 'node:sqlite';
import { startServer } from '../src/server.js';

test('list previews favor readable text while link-only mail and original bodies remain intact', () => {
  const message = { body: 'https://click.example.test/track?token=abc 尊敬的客户，请核对账单。 [https://example.test/bill]' };
  const original = structuredClone(message);
  assert.equal(mailPreview(message), '尊敬的客户，请核对账单。');
  assert.deepEqual(message, original);
  assert.equal(mailPreview({ body: 'https://example.test/only-link' }), 'https://example.test/only-link');
  assert.equal(mailPreview({ body: '点击查看https://example.test/track您的账单。' }), '点击查看您的账单。');
});

test('a standard signature is excluded while the following historical quotation is preserved', () => {
  const body = '已确认。\r\n-- \r\n我的签名\r\nmail@example.com\r\n\r\nOn Tuesday, someone wrote:\r\n> 历史引用内容';
  assert.equal(mailPreview({ body }), '已确认。 On Tuesday, someone wrote: > 历史引用内容');
});

test('long company signature separators stay out of previews without hiding forwarded history', () => {
  const body = '222222\n----------------------------------------------------------\n示例网络科技股份有限公司\n张三\n电话：010-12345678\n-----原始邮件-----\n发件人：李四\n这是应保留的历史正文。';
  const preview = mailPreview({ body });
  assert.equal(preview, '222222 -----原始邮件----- 发件人：李四 这是应保留的历史正文。');
});

test('quoted signatures are excluded while quoted prose remains visible', () => {
  const body = '本次回复\nOn Tuesday, someone wrote:\n> 历史正文\n> -- \n> 历史签名\n> old@example.com';
  assert.equal(mailPreview({ body }), '本次回复 On Tuesday, someone wrote: > 历史正文');
});

test('ordinary contact details and separators in prose are retained', () => {
  const body = '请联系项目负责人：person@example.com\n----------------\n下一步：核对合同和交付时间。';
  assert.equal(mailPreview({ body }), '请联系项目负责人：person@example.com ---------------- 下一步：核对合同和交付时间。');
});

test('HTML signature containers are removed without removing blockquote history or changing the source', () => {
  const message = { body: '本次回复 签名 历史引用内容 历史签名',
    html: '<p>本次回复</p><div class="gmail_signature">我的签名</div><blockquote><p>历史引用内容</p><div class="moz-signature">历史签名</div></blockquote>' };
  const original = structuredClone(message), preview = mailPreview(message);
  assert.match(preview, /本次回复/);
  assert.match(preview, /历史引用内容/);
  assert.doesNotMatch(preview, /签名/);
  assert.deepEqual(message, original);
});

test('mobile footers stop at the next Chinese quotation header', () => {
  const body = '收到。\n发自我的 iPhone\n在 2026 年 10 月 23 日，李四写道：\n> 原邮件内容';
  assert.equal(mailPreview({ body }), '收到。 在 2026 年 10 月 23 日，李四写道： > 原邮件内容');
});

test('a recognized signoff only hides the matching sender signature', () => {
  assert.equal(mailPreview({ sender: '张三', body: '合同已确认。\n祝好\n张三\n电话：010-12345678' }), '合同已确认。');
  assert.equal(mailPreview({ sender: '张三', body: '合同已确认。\n祝好\n请继续核对预算' }), '合同已确认。 祝好 请继续核对预算');
});

test('signature-only previews do not fall back to the original signature', () => {
  assert.equal(mailPreview({ body: '-- \n张三\nmail@example.com', preview: '张三 mail@example.com' }), '');
  assert.equal(mailPreview({ body: '', html: '<div class="gmail_signature"><img src="https://example.com/logo.png">签名</div>' }), '');
  assert.equal(mailPreview({ body: '', html: '<img src="https://example.com/picture.png">' }), '图片邮件');
});

test('truncation happens after signature removal and still includes historical prose', () => {
  const preview = mailPreview({ body: `回复\n-- \n${'签名'.repeat(200)}\nOn Tuesday, someone wrote:\n> ${'历史正文'.repeat(80)}` });
  assert.equal(preview.length, 140);
  assert.match(preview, /历史正文/);
  assert.doesNotMatch(preview, /签名/);
});

test('Unicode line separators do not break list previews or signature boundaries', () => {
  assert.equal(mailPreview({ body: '正文\u2028-- \u2029签名\u2028On Tuesday, someone wrote:\u2029> 历史引用' }),
    '正文 On Tuesday, someone wrote: > 历史引用');
});

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-conversation-display-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const base = { accountId: 'a1', folder: 'inbox', sender: '张三', body: '正文\n-- \n签名',
    preview: '过时预览 -- 签名', messageId: '<root@example.com>', date: '2026-10-20T00:00:00Z' };
  for (const [id, date] of [['selected', '2026-10-20'], ['newest', '2026-10-23'], ['tie-a', '2026-10-22'], ['tie-b', '2026-10-22']])
    repo.put('message', { ...base, id, date: `${date}T00:00:00Z`,
      messageId: `<${id}@example.com>`, references: ['<root@example.com>'] });
  return repo;
}

test('the selected older message stays first and the remaining thread pages run newest to oldest', async t => {
  const repo = await fixture(t);
  const first = conversation(repo, 'selected', { limit: 2 });
  const second = conversation(repo, 'selected', { offset: first.nextOffset, limit: 2 });
  assert.deepEqual(first.messages.map(m => m.id), ['selected', 'newest']);
  assert.deepEqual(second.messages.map(m => m.id), ['tie-a', 'tie-b']);
  assert.equal(second.nextOffset, null);
  assert.equal(first.total, 4);
  assert.equal(new Set([...first.messages, ...second.messages].map(m => m.id)).size, 4);
});

test('cached conversation previews are refreshed without resyncing or modifying full bodies and persisted previews', async t => {
  const repo = await fixture(t), original = repo.list('message');
  const thread = conversation(repo, 'selected');
  assert.ok(thread.messages.every(m => m.preview === '正文' && m.body === '' && m.html === undefined));
  assert.deepEqual(repo.list('message'), original);
});

test('message pages and compact headers share signature-free previews without rewriting stored mail or search indexes', async t => {
  const repo = await fixture(t), original = repo.list('message');
  repo.searchIndex.flush();
  const before = repo.db.prepare('SELECT total_changes() AS n').get().n;
  assert.ok(repo.messageHeaders().every(m => m.preview === '正文'));
  assert.ok(repo.messagePage({ accountId: 'a1' }).messages.every(m => m.preview === '正文'));
  assert.equal(repo.searchIndex.status().pending, 0);
  assert.equal(repo.db.prepare('SELECT total_changes() AS n').get().n, before);
  assert.deepEqual(repo.list('message'), original);
});

test('repeated list refreshes reuse previews, and changed bodies invalidate them', async t => {
  const repo = await fixture(t), get = repo.get.bind(repo);
  let bodyReads = 0;
  repo.get = (kind, id) => { if (kind === 'message') bodyReads++; return get(kind, id); };
  repo.messageHeaders();
  const warmed = bodyReads;
  const message = get('message', 'selected');
  repo.put('message', message);
  repo.messageHeaders(); repo.messagePage({ accountId: 'a1' });
  assert.equal(bodyReads, warmed);
  repo.put('message', { ...message, body: '新的正文\n-- \n新的签名' });
  assert.equal(repo.messageHeaders().find(m => m.id === 'selected').preview, '新的正文');
  assert.equal(bodyReads, warmed + 1);
});

test('a rolled-back body edit cannot leak its preview into later lists', async t => {
  const repo = await fixture(t), original = repo.get('message', 'selected');
  repo.messageHeaders();
  assert.throws(() => repo.transaction(() => {
    repo.put('message', { ...original, body: '未提交的正文' });
    assert.equal(repo.messageHeaders().find(m => m.id === original.id).preview, '未提交的正文');
    throw new Error('rollback');
  }), /rollback/);
  assert.equal(repo.messageHeaders().find(m => m.id === original.id).preview, '正文');
});

test('reopening a restored database discards previews from the previous handle', async t => {
  const repo = await fixture(t);
  repo.messageHeaders();
  repo.close();
  const replacement = new Repository(repo.directory);
  replacement.put('message', { ...replacement.get('message', 'selected'), body: '恢复后的正文\n-- \n签名' });
  replacement.close();
  repo.db = new DatabaseSync(path.join(repo.directory, 'boxmail.sqlite'));
  assert.equal(repo.messageHeaders().find(m => m.id === 'selected').preview, '恢复后的正文');
});

test('draft list previews exclude signatures and preserve quoted history', async t => {
  const repo = await fixture(t);
  repo.put('account', { id: 'a1', name: '张三', email: 'me@example.com' });
  repo.put('draft', { id: 'draft', accountId: 'a1', status: 'draft', updatedAt: '2026-10-23T00:00:00Z',
    subject: '草稿', body: '草稿正文\n-- \n我的签名\nOn Tuesday, someone wrote:\n> 历史引用' });
  const page = repo.messagePage({ accountId: 'a1', folder: 'drafts' });
  assert.equal(page.messages[0].preview, '草稿正文 On Tuesday, someone wrote: > 历史引用');
  assert.equal(page.messages[0].bodyLoaded, false);
  assert.match(repo.get('draft', 'draft').body, /我的签名/);
});

test('draft cards in full and compact snapshots receive clean previews without changing editable bodies', async t => {
  const repo = await fixture(t), token = 'synthetic-draft-preview-session-123456';
  repo.put('account', { id: 'a1', name: '张三', email: 'me@example.com' });
  const signature = '----------------------------------------------------------\n示例网络科技股份有限公司\n张三\n电话：010-12345678';
  const bodies = { signatureOnly: '\n\n' + signature,
    reply: '请核对合同。\n' + signature + '\n-----原始邮件-----\n发件人：李四\n历史正文',
    empty: '', ordinary: '请联系 person@example.com\n----------------\n下一步：核对合同。' };
  for (const [id, body] of Object.entries(bodies)) repo.put('draft', { id, accountId: 'a1', status: 'draft',
    subject: '', body, updatedAt: '2026-10-23T00:00:00Z', preview: '不应使用的旧预览' });
  const app = await startServer({ directory: repo.directory, token, demo: false });
  t.after(() => app.close());
  for (const route of ['/state', '/state?compact=1']) {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': token } });
    assert.equal(response.status, 200);
    const drafts = new Map((await response.json()).drafts.map(draft => [draft.id, draft]));
    assert.equal(drafts.get('signatureOnly').preview, '');
    assert.equal(drafts.get('empty').preview, '');
    assert.equal(drafts.get('reply').preview, '请核对合同。 -----原始邮件----- 发件人：李四 历史正文');
    assert.equal(drafts.get('ordinary').preview, '请联系 person@example.com ---------------- 下一步：核对合同。');
    for (const [id, body] of Object.entries(bodies)) {
      assert.equal(drafts.get(id).body, '');
      assert.equal(drafts.get(id).bodyLoaded, false);
      assert.equal(repo.get('draft', id).body, body);
      assert.equal(repo.get('draft', id).preview, '不应使用的旧预览');
    }
  }
  const body = '新增正文\n' + signature;
  const response = await fetch(`http://127.0.0.1:${app.port}/drafts`, { method: 'POST',
    headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: 'signatureOnly', accountId: 'a1', body, preview: '客户端过时预览' }) });
  assert.equal(response.status, 200);
  const saved = await response.json();
  assert.equal(saved.preview, '新增正文');
  assert.equal(saved.body, body);
  assert.equal(repo.get('draft', saved.id).body, body);
  assert.equal(Object.hasOwn(repo.get('draft', saved.id), 'preview'), false);
});

test('HTTP lists, snapshots and conversations filter previews while full mail retains signatures and quotes', async t => {
  const repo = await fixture(t), token = 'synthetic-conversation-session-123456';
  const original = repo.get('message', 'selected');
  repo.put('message', { ...original, body: '正文\n-- \n我的签名\nOn Tuesday, someone wrote:\n> 历史引用' });
  const app = await startServer({ directory: repo.directory, token, demo: false });
  t.after(() => app.close());
  const request = async route => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': token } });
    assert.equal(response.status, 200);
    return response.json();
  };
  const expected = '正文 On Tuesday, someone wrote: > 历史引用';
  for (const response of [await request('/messages?accountId=a1'), await request('/state?compact=1'), await request('/messages/selected/thread')]) {
    assert.equal(response.messages.find(m => m.id === 'selected').preview, expected);
  }
  const full = await request('/messages/selected');
  assert.match(full.body, /我的签名/); assert.match(full.body, /历史引用/);
});

test('search still matches original signatures but never puts them back into list snippets', async t => {
  const repo = await fixture(t), original = repo.get('message', 'selected');
  repo.put('message', { ...original, body: '正文\n-- \n独特签名公司\nOn Tuesday, someone wrote:\n> 历史引用关键词' });
  await repo.searchIndex.drain();
  const signature = repo.messagePage({ query: '独特签名公司' }).messages[0];
  assert.equal(signature.id, original.id);
  assert.equal(signature.searchSnippet, undefined);
  assert.doesNotMatch(signature.preview, /独特签名公司/);
  const history = repo.messagePage({ query: '历史引用关键词' }).messages[0];
  assert.match(history.searchSnippet, /历史引用关键词/);
});

test('draft search snippets retain quoted matches and fall back to the clean preview for signature matches', async t => {
  const repo = await fixture(t);
  repo.put('account', { id: 'a1', name: '张三', email: 'me@example.com' });
  repo.put('draft', { id: 'draft', accountId: 'a1', status: 'draft', updatedAt: '2026-10-23T00:00:00Z',
    subject: '草稿', body: '草稿正文\n-- \n独特签名公司\nOn Tuesday, someone wrote:\n> 历史引用关键词' });
  const signature = repo.messagePage({ query: 'folder:drafts 独特签名公司' }).messages[0];
  assert.equal(signature.id, 'draft:draft');
  assert.equal(signature.searchSnippet, undefined);
  const history = repo.messagePage({ query: 'folder:drafts 历史引用关键词' }).messages[0];
  assert.match(history.searchSnippet, /历史引用关键词/);
  const subject = repo.messagePage({ query: 'folder:drafts 草稿' }).messages[0];
  assert.match(subject.searchSnippet, /草稿/);
  assert.doesNotMatch(subject.searchSnippet, /独特签名公司/);
});
