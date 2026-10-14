import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { simpleParser } from 'mailparser';
import { Repository } from '../src/database.js';
import { mailBody } from '../src/mail-body.js';
import { syncAccount } from '../src/mail.js';

test('image-only HTML retains the image and table layout instead of becoming empty text', async () => {
  const parsed = await simpleParser(Buffer.from([
    'From: service@example.com', 'Subject: Image mail', 'MIME-Version: 1.0',
    'Content-Type: text/html; charset=utf-8', '',
    '<table cellpadding="0"><tr><td style="padding:20px;background-color:#fff"><img src="https://example.com/body.png" width="600"></td></tr></table>',
  ].join('\r\n')), { skipHtmlToText: true });
  const content = mailBody(parsed);
  assert.equal(content.body.trim(), '');
  assert.match(content.html, /<table cellpadding="0">/);
  assert.match(content.html, /padding:20px/);
  assert.match(content.html, /<img src="https:\/\/example.com\/body.png"/);
  assert.equal(content.hasRemoteImages, true);
  assert.equal(content.preview, '图片邮件');
});

test('CID images decode locally and do not require a remote request', async () => {
  const source = [
    'MIME-Version: 1.0', 'Content-Type: multipart/related; boundary="related"', '',
    '--related', 'Content-Type: text/html; charset=utf-8', '',
    '<p>内嵌图片</p><img src="cid:picture">',
    '--related', 'Content-Type: image/png', 'Content-ID: <picture>',
    'Content-Transfer-Encoding: base64', 'Content-Disposition: inline; filename="picture.png"', '',
    'iVBORw0KGgo=', '--related--', '',
  ].join('\r\n');
  const content = mailBody(await simpleParser(Buffer.from(source)));
  assert.match(content.html, /src="data:image\/png;base64,iVBORw0KGgo="/);
  assert.match(content.body, /内嵌图片/);
  assert.equal(content.hasRemoteImages, false);
});

test('HTML removes scripts, forms, frames, unsafe destinations and active CSS', () => {
  const content = mailBody({ text: 'Readable text', html: `
    <script>alert(1)</script><iframe src="https://evil.test"></iframe>
    <meta http-equiv="refresh" content="0;https://evil.test"><base href="https://evil.test">
    <form action="https://evil.test"><input name="secret"></form>
    <p onclick="alert(1)" style="position:fixed;background:url(https://evil.test);width:expression(alert(1));color:red">正文</p>
    <a href="javascript:alert(1)">坏链接</a><a href="https://example.com">好链接</a>
    <img src="file:///private/file"><img src="data:image/svg+xml;base64,PHN2Zz4=" onerror="alert(1)">
    <img src="//example.com/image.png">
  ` });
  assert.doesNotMatch(content.html, /script|iframe|<meta|<base|<form|<input|onclick|onerror|javascript:|file:|svg\+xml|position:|url\(|expression\(/i);
  assert.match(content.html, /color:red/);
  assert.match(content.html, /href="https:\/\/example.com"/);
  assert.match(content.html, /src="https:\/\/example.com\/image.png"/);
});

test('legacy cache repairs HTML once while retaining summaries, labels and attachment identity', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-body-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a1', email: 'me@example.com', folders: {} };
  const source = Buffer.from([
    'From: sender@example.com', 'Subject: HTML mail', 'Message-ID: <same@example.com>',
    'MIME-Version: 1.0', 'Content-Type: text/html; charset=utf-8', '',
    '<h1>正文标题</h1><img src="https://example.com/body.png">',
  ].join('\r\n'));
  let downloads = 0, olderWindow = false;
  const client = {
    mailbox: {}, async connect() {}, async logout() {},
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock() { this.mailbox = { uidValidity: '100', exists: olderWindow ? 201 : 1 }; return { release() {} }; },
    async *fetch() { yield { uid: olderWindow ? 8 : 7, size: source.length, flags: new Set(['\\Seen']), internalDate: new Date() }; },
    async fetchOne(uid, query) {
      if (!query.source) return { uid, size: source.length, flags: new Set(['\\Seen']), internalDate: new Date() };
      downloads++; return { source };
    },
  };
  await syncAccount(repo, account, 'test', { clientFactory: () => client });
  const first = repo.list('message')[0];
  assert.match(first.html, /正文标题/);
  assert.equal(first.bodyVersion, 1);
  const summary = { points: ['本机摘要'], todos: [], keyInfo: [] };
  repo.put('message', { ...first, body: '', html: undefined, bodyVersion: undefined,
    summary, category: '账单票据', attachmentIds: ['original-attachment'] });
  await syncAccount(repo, account, 'test', { clientFactory: () => client });
  const restored = repo.get('message', first.id);
  assert.equal(downloads, 2);
  assert.match(restored.html, /正文标题/);
  assert.match(restored.body, /正文标题/);
  assert.deepEqual(restored.summary, summary);
  assert.equal(restored.category, '账单票据');
  assert.deepEqual(restored.attachmentIds, ['original-attachment']);
  await syncAccount(repo, account, 'test', { clientFactory: () => client });
  assert.equal(downloads, 2);
  assert.equal(repo.list('message').length, 1);
  olderWindow = true;
  repo.put('message', { ...restored, html: undefined, bodyVersion: undefined });
  const result = await syncAccount(repo, account, 'test', { clientFactory: () => client });
  assert.equal(result.repaired, 1);
  assert.match(repo.get('message', first.id).html, /正文标题/);
  assert.deepEqual(repo.get('message', first.id).summary, summary);
  assert.equal(repo.list('message').length, 2);
  assert.equal(downloads, 4);
});
