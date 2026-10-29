import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildReplyDraft } from '../src/reply.js';
import { draftContent, inlineForwardImages, savedForwardFields, upgradeForwardDraft } from '../src/forward-content.js';
import { startServer } from '../src/server.js';
import { validateBackupRecords } from '../src/backup-validation.js';

const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==';
const account = { id: 'a1', name: '测试发件人', email: 'me@example.test', username: 'me@example.test',
  imapHost: '', imapPort: 993, imapTLS: true, smtpHost: '', smtpPort: 465, smtpTLS: true, isDemo: true };
const message = { id: 'm1', accountId: 'a1', folder: 'inbox', sender: '客户 <甲>', senderEmail: 'sender@example.test',
  to: account.email, cc: '', subject: '原始排版与合同', body: '原文合同说明与交付期限。', preview: '原文合同说明',
  date: '2026-10-24T01:00:00Z', category: '未分类', unread: false, starred: false, attachmentIds: [],
  messageId: '<original@example.test>',
  html: `<table width="600" cellpadding="0"><tr><td style="padding:24px;background-color:#edf3ff"><h1 style="color:#234567">原文标题</h1>`
    + `<p>原文合同说明与交付期限。</p><a href="https://example.test/contract?ref=source" style="color:#3567af">查看合同</a>`
    + `<img src="data:image/png;base64,${png}" width="48"><img src="https://example.test/banner.png" width="600"></td></tr></table>` };
const token = 'boxmail-forward-test-session-0123456789';

test('backup validation requires both parts of a formatted forward and accepts legacy plain drafts', async t => {
  const app = await fixture(t);
  const draft = buildReplyDraft(message, account, { forward: true });
  app.repo.put('draft', draft);
  const records = () => app.repo.db.prepare('SELECT kind,id,data FROM records').all();
  assert.doesNotThrow(() => validateBackupRecords(records()));
  for (const field of ['forwardedHTML', 'forwardedText']) {
    const broken = { ...draft };
    delete broken[field];
    app.repo.put('draft', broken);
    assert.throws(() => validateBackupRecords(records()), /记录字段或附件关联/);
  }
  const legacy = { ...draft };
  delete legacy.forwardedHTML; delete legacy.forwardedText;
  app.repo.put('draft', legacy);
  assert.doesNotThrow(() => validateBackupRecords(records()));
});

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-forward-'));
  let app = await startServer({ directory, token, demo: false });
  app.repo.put('account', account); app.repo.put('message', message);
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  return { get repo() { return app.repo; },
    async restart() { await app.close(); app = await startServer({ directory, token, demo: false }); },
    async request(route, body) {
      const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
      return { status: response.status, body: await response.json() };
    } };
}

test('HTML forwards retain layout and original destinations while editable notes stay separate', () => {
  const original = structuredClone(message);
  const draft = buildReplyDraft(message, { ...account, signature: '测试签名' }, { forward: true });
  assert.equal(draft.body, '\n\n测试签名');
  assert.match(draft.forwardedHTML, /<table width="600" cellpadding="0">/);
  assert.match(draft.forwardedHTML, /padding:24px;background-color:#edf3ff/);
  assert.match(draft.forwardedHTML, /客户 &lt;甲&gt;/);
  assert.match(draft.forwardedHTML, /https:\/\/example.test\/contract\?ref=source/);
  assert.match(draft.forwardedText, /原文合同说明与交付期限/);
  assert.equal(draft.to, ''); assert.equal(draft.inReplyTo, ''); assert.deepEqual(draft.references, []);
  const content = draftContent({ ...draft, body: '转发说明 <不要作为 HTML>\n测试签名' });
  assert.match(content.html, /转发说明 &lt;不要作为 HTML&gt;/);
  assert.match(content.text, /转发说明.*\n测试签名\n\n---------- 转发邮件 ----------/);
  assert.equal(content.html.match(/<table/g).length, 1);
  assert.deepEqual(message, original);
});

test('formatted drafts survive save, restart and source removal and remain searchable', async t => {
  const app = await fixture(t);
  const created = await app.request('/messages/m1/reply-draft', { forward: true });
  assert.equal(created.status, 200);
  const edited = { ...created.body, body: '请审核这份合同。\n签名' };
  const saved = await app.request('/drafts', edited);
  assert.equal(saved.status, 200);
  assert.equal(saved.body.forwardedText, created.body.forwardedText);
  assert.match(saved.body.forwardedHTML, /<table/);
  app.repo.remove('message', message.id);
  await app.restart();
  const state = await app.request('/state?compact=1');
  assert.equal(state.body.drafts[0].bodyLoaded, false);
  assert.equal(state.body.drafts[0].body, '');
  assert.equal(state.body.drafts[0].forwardedHTML, undefined);
  const reopened = await app.request('/drafts/' + created.body.id);
  assert.equal(reopened.body.body, edited.body);
  assert.match(reopened.body.forwardedHTML, /background-color:#edf3ff/);
  const search = await app.request('/messages?accountId=a1&folder=drafts&q=' + encodeURIComponent('folder:drafts 交付期限'));
  assert.equal(search.body.total, 1);
  assert.equal(search.body.messages[0].bodyLoaded, false);
  const detail = await app.request('/messages/' + search.body.messages[0].id);
  assert.match(detail.body.body, /请审核这份合同/);
  assert.match(detail.body.html, /<table/);
});

test('intact legacy forward quotations recover HTML without discarding notes or rewriting storage on read', async t => {
  const app = await fixture(t);
  const legacy = buildReplyDraft({ ...message, html: undefined }, account, { forward: true });
  legacy.body = '原有转发说明。\n\n' + legacy.forwardedText;
  delete legacy.forwardedText; delete legacy.forwardedHTML;
  app.repo.put('draft', legacy);
  const header = (await app.request('/state?compact=1')).body.drafts[0];
  assert.equal(header.bodyLoaded, false);
  const projected = (await app.request('/drafts/' + legacy.id)).body;
  assert.equal(projected.body, '原有转发说明。');
  assert.match(projected.forwardedHTML, /<table/);
  const detail = await app.request('/messages/draft:' + legacy.id);
  assert.match(detail.body.html, /<table/);
  assert.equal(app.repo.get('draft', legacy.id).forwardedHTML, undefined);
  const edited = { ...legacy, body: legacy.body.replace('原文合同说明', '用户改过的引用') };
  assert.deepEqual(upgradeForwardDraft(edited, message), edited);
});

test('draft saves sanitize original HTML, preserve snapshots for older callers, and reject malformed fields', async t => {
  const app = await fixture(t);
  const created = (await app.request('/messages/m1/reply-draft', { forward: true })).body;
  const saved = await app.request('/drafts', { ...created,
    forwardedHTML: created.forwardedHTML + '<script>bad()</script><iframe src="https://example.test"></iframe>' });
  assert.equal(saved.status, 200); assert.doesNotMatch(saved.body.forwardedHTML, /script|iframe/);
  assert.match(savedForwardFields({}, saved.body).forwardedHTML, /<table/);
  const rejected = await app.request('/drafts', { ...created, forwardedHTML: [] });
  assert.equal(rejected.status, 400);
  assert.equal(app.repo.get('draft', created.id).forwardedHTML, saved.body.forwardedHTML);
});

test('inline images become reusable MIME CID parts without fetching external images', () => {
  const files = [{ filename: 'original.png', contentType: 'image/png', content: Buffer.from(png, 'base64') }];
  const html = inlineForwardImages(message.html + `<img src="data:image/png;base64,${png}">`, files);
  assert.equal(files.length, 1);
  assert.equal(files[0].filename, 'original.png');
  assert.equal(files[0].contentDisposition, 'inline');
  assert.equal(html.match(/src="cid:/g).length, 2);
  assert.doesNotMatch(html, /data:image/);
  assert.match(html, /https:\/\/example.test\/banner.png/);
});
