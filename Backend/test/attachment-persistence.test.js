import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { extractText, saveAttachment } from '../src/attachments.js';
import { syncAccount } from '../src/mail.js';

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-attachment-persistence-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a', email: 'reader@example.test', folders: { inbox: 'INBOX' } };
  repo.put('account', account);
  return { repo, account, files: () => readdir(path.join(directory, 'attachments')) };
}

function mailbox() {
  const source = Buffer.from([
    'From: sender@example.test', 'To: reader@example.test', 'Subject: With attachments',
    'Message-ID: <attachment-persistence@example.test>', 'MIME-Version: 1.0',
    'Content-Type: multipart/mixed; boundary="parts"', '', '--parts',
    'Content-Type: text/plain', '', 'Mail body', '--parts',
    'Content-Type: text/plain', 'Content-Disposition: attachment; filename="first.txt"', '', 'First file',
    '--parts', 'Content-Type: text/plain', 'Content-Disposition: attachment; filename="second.txt"', '', 'Second file', '--parts--', '',
  ].join('\r\n'));
  return {
    mailbox: { uidValidity: '10', exists: 1 },
    async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock() { return { release() {} }; },
    async status() { return { messages: 1, uidValidity: '10' }; },
    async search() { return [1]; },
    async *fetch() { yield { uid: 1, size: source.length, flags: new Set() }; },
    async fetchOne() { return { uid: 1, source }; },
  };
}

test('presentation text extraction propagates cancellation after preparation begins', async () => {
  const buffer = await readFile(new URL('fixtures/two-slides.pptx', import.meta.url));
  const controller = new AbortController();
  const reason = new Error('cancel presentation extraction');
  const extraction = extractText(buffer, 'two-slides.pptx', '', { signal: controller.signal });
  controller.abort(reason);
  await assert.rejects(extraction, error => error === reason);
});

test('failed attachment record writes remove the file created by that attempt', async t => {
  const { repo, files } = await fixture(t);
  repo.db.exec(`CREATE TRIGGER reject_attachment BEFORE INSERT ON records WHEN new.kind='attachment'
    BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END;`);
  await assert.rejects(saveAttachment(repo, 'draft', 'file.txt', Buffer.from('contents')), /simulated disk failure/);
  assert.deepEqual(repo.list('attachment'), []);
  assert.deepEqual(await files(), []);
});

test('a failed mail commit rolls back all attachment records and files and can retry cleanly', async t => {
  const { repo, account, files } = await fixture(t);
  repo.db.exec(`CREATE TRIGGER reject_mail BEFORE INSERT ON records WHEN new.kind='message'
    BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END;`);
  await assert.rejects(syncAccount(repo, { ...account }, 'synthetic', { clientFactory: mailbox }));
  assert.deepEqual(repo.list('message'), []);
  assert.deepEqual(repo.list('attachment'), []);
  assert.deepEqual(await files(), []);
  repo.db.exec('DROP TRIGGER reject_mail');
  assert.equal((await syncAccount(repo, { ...account }, 'synthetic', { clientFactory: mailbox })).count, 1);
  const message = repo.list('message')[0];
  assert.equal(message.attachmentIds.length, 2);
  assert.deepEqual(new Set(message.attachmentIds), new Set(repo.list('attachment').map(file => file.id)));
  assert.equal((await files()).length, 2);
  assert.equal(repo.db.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
});

test('a failed retained mail commit preserves its recovery, attachments, drafts and jobs', async t => {
  const { repo, account, files } = await fixture(t);
  const attachment = await saveAttachment(repo, 'old', 'retained.txt', Buffer.from('Retained file'));
  const original = { id: 'old', accountId: account.id, folder: 'inbox',
    messageId: '<attachment-persistence@example.test>', attachmentIds: [attachment.id], summary: { overview: 'Retained summary' } };
  repo.put('recovery', { id: 'old', accountId: account.id, remotePath: 'INBOX', original });
  repo.put('draft', { id: 'draft', accountId: account.id, sourceMessageId: 'old' });
  repo.put('job', { id: 'job', accountId: account.id, messageId: 'old' });
  repo.db.exec(`CREATE TRIGGER reject_mail BEFORE INSERT ON records WHEN new.kind='message'
    BEGIN SELECT RAISE(ABORT,'simulated disk failure'); END;`);
  await assert.rejects(syncAccount(repo, { ...account }, 'synthetic', { clientFactory: mailbox }));
  assert.deepEqual(repo.get('recovery', 'old').original, original);
  assert.deepEqual(repo.get('attachment', attachment.id), attachment);
  assert.equal(repo.get('draft', 'draft').sourceMessageId, 'old');
  assert.equal(repo.get('job', 'job').messageId, 'old');
  assert.equal((await files()).length, 1);
  repo.db.exec('DROP TRIGGER reject_mail');
  await syncAccount(repo, { ...account }, 'synthetic', { clientFactory: mailbox });
  const message = repo.list('message')[0];
  assert.equal(message.summary.overview, 'Retained summary');
  assert.equal(repo.get('recovery', 'old'), null);
  assert.equal(repo.get('attachment', attachment.id).messageId, message.id);
  assert.equal(repo.get('draft', 'draft').sourceMessageId, message.id);
  assert.equal(repo.get('job', 'job').messageId, message.id);
});
