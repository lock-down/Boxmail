import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import os from 'node:os';
import path from 'node:path';
import { mailBody } from '../src/mail-body.js';
import { mailPreview } from '../src/mail-preview.js';
import { startServer } from '../src/server.js';
import { parseMailContent } from '../src/mail-content-worker.js';
import { Repository } from '../src/database.js';
import { saveAttachment } from '../src/attachments.js';
import { AIProgress } from '../src/ai-progress.js';

const astral = String.fromCodePoint(0x20bb7);
test('mail previews never publish half of an astral character at the length boundary', () => {
  const body = 'a'.repeat(139) + astral + ' preserved body';
  const content = mailBody({ text: body });
  assert.equal(content.body, body);
  assert.ok(content.preview.isWellFormed());
  assert.ok(mailPreview({ body }).isWellFormed());
  assert.ok(content.preview.length <= 140);
});

test('text extraction keeps complete characters at its limit and preserves original attachment bytes', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-unicode-attachment-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const bytes = Buffer.from('a'.repeat(199999) + astral + ' original attachment tail');
  const attachment = await saveAttachment(repo, 'synthetic', 'synthetic.txt', bytes);
  assert.ok(attachment.text.isWellFormed());
  assert.ok(attachment.text.length <= 200000);
  assert.deepEqual(await readFile(attachment.path), bytes);
  repo.put('message', { id: 'new', subject: '\uD800', body: 'valid ' + astral });
  assert.equal(repo.get('message', 'new').subject, '\uFFFD');
  assert.equal(repo.get('message', 'new').body, 'valid ' + astral);
});

test('streamed partial output repairs incomplete Unicode while preserving literal backslash sequences', t => {
  const progress = new AIProgress(), chunks = [];
  const response = Object.assign(new EventEmitter(), {
    writableLength: 0,
    writeHead() {}, write(value) { chunks.push(value); }, destroy() { this.emit('close'); },
  });
  t.after(() => progress.close());
  progress.subscribe(response);
  progress.publish({ id: 'synthetic', status: 'running', text: 'partial \uD83D', stage: String.raw`literal \ud800` });
  const event = JSON.parse(chunks.at(-1).slice(6));
  assert.equal(event.output.text, 'partial \uFFFD');
  assert.equal(event.output.stage, String.raw`literal \ud800`);
});

test('legacy malformed MIME headers cannot poison startup snapshots, details or settings refresh', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-unicode-wire-'));
  const token = 'synthetic-content-unicode-session-token';
  const parsed = await parseMailContent('mime', Buffer.from('From: Synthetic <sender@example.test>\r\n'
    + 'Subject: =?UTF-16LE?B?ANg=?=\r\n\r\nOriginal body remains readable'));
  assert.equal(parsed.parsed.subject.isWellFormed(), false);
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const message = { id: 'legacy', accountId: 'a', folder: 'inbox', sender: 'Synthetic',
    senderEmail: 'sender@example.test', to: 'reader@example.test', cc: '', subject: parsed.parsed.subject,
    ...parsed.content, date: '2026-10-28T00:00:00Z', category: '未分类', unread: false,
    starred: false, attachmentIds: [] };
  // Bypass current writes to represent an already-cached message from an older build.
  app.repo.db.prepare('INSERT INTO records VALUES(?,?,?)').run('message', message.id, JSON.stringify(message));
  const get = async route => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': token } });
    assert.equal(response.status, 200);
    return response.json();
  };
  for (const route of ['/state?compact=1&previews=0', '/state', '/messages/legacy', '/messages?groupBy=sender']) {
    const response = await get(route);
    const value = response.messages?.[0] ?? response;
    assert.ok(value.subject.isWellFormed(), route);
    if (!route.includes('compact') && !route.includes('groupBy')) assert.equal(value.body, message.body);
  }
  assert.equal(app.repo.get('message', 'legacy').body, message.body);
});
