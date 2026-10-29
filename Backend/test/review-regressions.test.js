import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { applyMailMutations, discoverMailFolders } from '../src/mail-folders.js';
import { syncAccount } from '../src/mail.js';
import { mailBody } from '../src/mail-body.js';
import { translationDocument } from '../src/translation.js';
import { buildReplyDraft } from '../src/reply.js';
import { draftContent } from '../src/forward-content.js';
import { saveAttachment } from '../src/attachments.js';
import { AttachmentBatch } from '../src/attachment-batch.js';
import { pruneMailRecovery, RECOVERY_TTL_MS, MAX_RETAINED_MAIL } from '../src/mail-recovery.js';
import { workbookPreview } from '../src/workbook-preview.js';
import { MAX_INDEX_TEXT } from '../src/search-index.js';
import { DRAFT_SEARCH_LIMIT } from '../src/draft-search.js';
import { importConfiguration, inspectConfiguration } from '../src/configuration.js';

const account = { id: 'a', name: '测试', email: 'reader@example.test', username: 'reader@example.test',
  imapHost: 'imap.example.test', smtpHost: 'smtp.example.test', imapPort: 993, smtpPort: 465,
  imapTLS: true, smtpTLS: true, isDemo: false };
const message = { id: 'm', accountId: 'a', folder: 'inbox', sender: '测试', senderEmail: 'sender@example.test',
  subject: '合同', body: '原始内容', to: account.email, cc: '', date: '2026-10-28T00:00:00Z',
  attachmentIds: [], category: '未分类', unread: false, starred: false };

async function fixture(t, server = false) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-review-'));
  const token = 'synthetic-review-regression-token';
  const app = server ? await startServer({ directory, token, demo: false }) : null;
  const repo = app?.repo ?? new Repository(directory);
  repo.put('account', account);
  repo.put('message', message);
  t.after(async () => { if (app) await app.close(); else repo.close(); await rm(directory, { recursive: true, force: true }); });
  return { repo, directory, async request(route, body) {
    const res = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: body === undefined ? 'GET' : 'POST',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: res.status, body: await res.json() };
  } };
}

test('missing mutation source is discarded, valid flags continue and every acquired lock is released', async t => {
  const { repo } = await fixture(t), changes = [], locks = [];
  const target = { ...account, folders: { inbox: 'INBOX' } };
  for (const [id, source] of [['missing', 'OldInbox'], ['valid', 'INBOX']]) repo.put('mutation', {
    id, accountId: account.id, path: source, uid: 1, uidValidity: '10', flag: '\\Flagged', value: true,
  });
  const client = { mailbox: { uidValidity: '10' }, async getMailboxLock(source) {
    if (source === 'OldInbox') throw new Error('Mailbox does not exist');
    return { release() { locks.push(source); } };
  }, async messageFlagsAdd(uid) { changes.push(uid); } };
  await applyMailMutations(repo, target, client);
  assert.deepEqual(repo.list('mutation'), []);
  assert.deepEqual(changes, [1]); assert.deepEqual(locks, ['INBOX']);
  assert.ok(repo.events().some(event => /失效/.test(event.detail)));
});

test('folder discovery removes deleted and unmarked special-use paths', () => {
  const target = { folders: { inbox: 'INBOX', archive: 'OldArchive', spam: 'OldJunk' } };
  discoverMailFolders(target, [{ path: 'INBOX' }, { path: 'OldArchive' }, { path: 'NewJunk', specialUse: '\\Junk' }]);
  assert.deepEqual(target.folders, { inbox: 'INBOX', spam: 'NewJunk' });
});

function remote(source, count = 3) {
  let selected;
  return { mailbox: {}, async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock(name) { selected = name; this.mailbox = { uidValidity: '10', exists: count }; return { release() {} }; },
    async status() { return { messages: count, uidValidity: '10', uidNext: count + 1 }; },
    async search() { return Array.from({ length: count }, (_, i) => i + 1); },
    async *fetch(uids) { for (const uid of uids) yield { uid, flags: new Set(), size: 10000 }; },
    async fetchOne(uid, query) {
      assert.equal(selected, 'INBOX');
      return query.envelope ? { uid, envelope: { from: [{ address: 'sender@example.test' }], subject: '保留邮件头', messageId: `<${uid}@test>` } }
        : { uid, source: Buffer.from(source) };
    } };
}

test('deep HTML degrades safely in body, forward, translation and sync without deferred retries', async t => {
  const html = '<div>'.repeat(5000) + '<script>private-script</script><p>合同原文</p>' + '</div>'.repeat(5000);
  const body = mailBody({ html });
  assert.match(body.body, /合同原文/); assert.equal(body.html, ''); assert.doesNotMatch(body.body, /private-script/);
  assert.match(buildReplyDraft({ ...message, html }, {}, { forward: true }).forwardedText, /原始内容/);
  assert.doesNotThrow(() => translationDocument({ ...message, html }));
  const { repo } = await fixture(t);
  const source = 'From: sender@example.test\r\nContent-Type: text/html; charset=utf-8\r\n\r\n' + html;
  const result = await syncAccount(repo, { ...account, folders: { archive: 'Gone' } }, 'synthetic', { clientFactory: () => remote(source) });
  assert.equal(result.count, 3); assert.equal(result.partial, false);
  assert.ok(repo.list('message').filter(value => value.uid).every(value => value.body.includes('合同原文')));
  assert.equal(repo.list('sync')[0].source.failedCount, 0);
  assert.equal(repo.get('account', 'a').folders.archive, undefined);
});

test('permanently invalid MIME keeps deletable headers and original bytes without repeated parsing', async t => {
  const { repo } = await fixture(t);
  const source = 'synthetic-invalid-MIME';
  let parses = 0;
  const options = { clientFactory: () => remote(source, 1), contentWorker: { async run() {
    parses++; throw Object.assign(new Error('invalid document'), { code: 'PARSER_INVALID_DOCUMENT' });
  } } };
  await syncAccount(repo, { ...account }, 'synthetic', options);
  await syncAccount(repo, repo.get('account', 'a'), 'synthetic', options);
  assert.equal(parses, 1);
  const saved = repo.list('message').find(value => value.uid);
  assert.equal(saved.subject, '保留邮件头');
  assert.match(saved.body, /原始邮件已保存/);
  const attachment = repo.get('attachment', saved.attachmentIds[0]);
  assert.equal(await readFile(attachment.path, 'utf8'), source);
});

test('large plain forwards round trip through HTTP and overlong editable notes fail without overwriting', async t => {
  const { repo, request } = await fixture(t, true);
  const original = '合同\n'.repeat(240000) + '原文尾部';
  repo.put('message', { ...message, body: original });
  const created = await request('/messages/m/reply-draft', { forward: true });
  assert.equal(created.status, 200); assert.equal(created.body.body, '');
  const saved = await request('/drafts', { ...created.body, body: '转发说明' });
  assert.equal(saved.status, 200); assert.ok(draftContent(saved.body).text.endsWith(original));
  repo.remove('message', 'm');
  const reopened = await request('/messages/draft:' + saved.body.id);
  assert.ok(reopened.body.body.endsWith(original));
  const rejected = await request('/drafts', { ...saved.body, body: 'x'.repeat(500001) });
  assert.equal(rejected.status, 400); assert.equal(repo.get('draft', saved.body.id).body, '转发说明');
});

test('attachment batch rejects oversized and legacy retries before scheduling requests and accepts a selected subset', async t => {
  const { repo } = await fixture(t);
  const ids = Array.from({ length: 101 }, (_, i) => 'attachment-' + i);
  repo.put('message', { ...message, attachmentIds: ids });
  let calls = 0;
  const manager = new AttachmentBatch(repo, { run: async (_, input) => {
    calls++; repo.put('attachment', { ...repo.get('attachment', input.attachmentId), analysis: '已理解' });
  } });
  t.after(() => manager.close());
  const input = { messageId: 'm', config: { ...DEFAULT_AI, baseURL: 'http://localhost:1234' } };
  assert.throws(() => manager.start(input), /最多理解 100/);
  assert.equal(calls, 0); assert.deepEqual(repo.list('job'), []);
  repo.put('attachment', { id: ids[0], messageId: 'm', text: '原文', name: 'a.txt', contentType: 'text/plain' });
  const job = manager.start({ ...input, attachmentIds: ids.slice(0, 1) });
  await manager.workers.get(job.id).promise;
  assert.equal(calls, 1); assert.equal(repo.get('job', job.id).status, 'completed');
  repo.put('job', { ...repo.get('job', job.id), status: 'paused', attachmentItems: [{ id: ids[0], name: 'a.txt', status: 'pending' }] });
  const retried = manager.start(input, job.id);
  await manager.workers.get(retried.id).promise;
  assert.equal(calls, 2);
  repo.put('job', { ...job, id: 'legacy', status: 'paused', attachmentItems: ids.map(id => ({ id, name: 'file', status: 'pending' })) });
  assert.throws(() => manager.start({ ...input, attachmentIds: [ids[0]] }, 'legacy'), /最多理解 100/);
});

test('draft keyword search reads only bounded referenced content and returns light pages with complete detail', async t => {
  const { repo, request } = await fixture(t, true);
  const large = '大'.repeat(2 * 1024 * 1024) + '末尾';
  for (let i = 0; i < 6; i++) repo.put('draft', { id: 'd' + i, accountId: 'a', to: '', cc: '', bcc: '', subject: '待发合同',
    body: '说明', forwardedText: '可搜索引用\n' + large, forwardedHTML: '<p>' + large + '</p>', attachmentIds: ['attached'], status: 'draft', updatedAt: message.date });
  repo.put('attachment', { id: 'unrelated', text: '不应搜索的附件', analysis: large, name: '无关附件' });
  repo.put('attachment', { id: 'attached', text: '预算上限', name: '清单' });
  const list = repo.list.bind(repo);
  repo.list = (kind, options) => { assert.notEqual(kind, 'attachment'); return list(kind, options); };
  const page = await request('/messages?folder=drafts&q=' + encodeURIComponent('合同 预算 可搜索引用'));
  assert.equal(page.body.total, 6); assert.ok(JSON.stringify(page.body).length < 20000);
  assert.ok(page.body.messages.every(value => !value.bodyLoaded && value.body === ''));
  const detail = await request('/messages/' + page.body.messages[0].id);
  assert.ok(detail.body.body.endsWith(large));
  assert.equal((await request('/messages?folder=drafts&q=不应搜索')).body.total, 0);
  assert.equal((await request('/messages?folder=drafts&q=' + encodeURIComponent('末尾'))).body.total, 0);
  assert.ok(DRAFT_SEARCH_LIMIT < large.length);
});

test('retained identity queries never load the whole history and expired files respect surviving references', async t => {
  const { repo } = await fixture(t);
  const file = await saveAttachment(repo, 'old', 'raw.txt', Buffer.from('原件'), 'text/plain');
  const shared = await saveAttachment(repo, 'm', 'shared.txt', Buffer.from('共享'), 'text/plain');
  repo.put('message', { ...message, attachmentIds: [shared.id] });
  const now = Date.now(), expired = new Date(now - RECOVERY_TTL_MS - 1).toISOString();
  repo.put('recovery', { id: 'expired', accountId: 'a', remotePath: 'Old', createdAt: expired,
    original: { ...message, id: 'old', messageId: '<expired@test>', attachmentIds: [file.id, shared.id] } });
  for (let i = 0; i < MAX_RETAINED_MAIL + 2; i++) repo.put('recovery', { id: 'old-' + i, accountId: 'a', remotePath: 'INBOX',
    createdAt: new Date(now).toISOString(), original: { ...message, messageId: `<${i}@test>` } });
  repo.list = () => { throw new Error('No full history reads'); };
  assert.equal(repo.retainedMail('a', 'INBOX', '1', 1, '<42@test>').value.id, 'old-42');
  await pruneMailRecovery(repo, 'a', { now });
  assert.equal(repo.get('recovery', 'expired'), null);
  assert.equal(repo.get('attachment', file.id), null);
  await assert.rejects(readFile(file.path), { code: 'ENOENT' });
  assert.equal(await readFile(shared.path, 'utf8'), '共享');
  assert.equal(repo.db.prepare("SELECT count(*) AS n FROM records WHERE kind='recovery'").get().n, MAX_RETAINED_MAIL);
});

test('search requests never flush dirty documents and background work bounds a multi-megabyte message', async t => {
  const { repo } = await fixture(t);
  repo.put('message', { ...message, body: '索引开头' + '大正文'.repeat(1700000) });
  const flush = repo.searchIndex.flush.bind(repo.searchIndex);
  repo.searchIndex.flush = () => { throw new Error('request flushed'); };
  assert.doesNotThrow(() => repo.search('索引开头'));
  repo.searchIndex.flush = flush;
  let serviced = false;
  setImmediate(() => { serviced = true; });
  await repo.searchIndex.drain();
  assert.equal(serviced, true);
  assert.equal(repo.search('索引开头')[0].id, 'm');
  assert.ok(repo.db.prepare('SELECT length(text) AS n FROM mail_fts').get().n <= MAX_INDEX_TEXT);
});

test('workbook previews run in the protected process and reject excessive cell text without affecting the backend', async t => {
  const { default: ExcelJS } = await import('exceljs');
  const book = new ExcelJS.Workbook();
  book.addWorksheet('合同').getCell('A1').value = '预算';
  const records = [];
  assert.match(await workbookPreview(Buffer.from(await book.xlsx.writeBuffer()), {
    diagnostics: { record(name) { records.push(name); } },
  }), /预算/);
  assert.ok(records.includes('parser.completed'));
  book.worksheets[0].getCell('A1').value = 'x'.repeat(32769);
  await assert.rejects(workbookPreview(Buffer.from(await book.xlsx.writeBuffer())), /单元格内容过长/);
  const { request } = await fixture(t, true);
  assert.equal((await request('/health')).status, 200);
});

test('configuration import may omit empty credentials and preserves the machine references', async t => {
  const { repo } = await fixture(t, true);
  const saved = repo.get('settings', 'settings');
  repo.put('settings', { ...saved, credentialReferences: { 'ai-key': 'local-key', 'mail-a': 'local-mail' } });
  const configuration = { accounts: [account], settings: saved };
  const plan = inspectConfiguration(repo, configuration);
  importConfiguration(repo, { configuration, ...plan, approved: true, credentialReferences: {} });
  assert.deepEqual(repo.get('settings', 'settings').credentialReferences, { 'ai-key': 'local-key', 'mail-a': 'local-mail' });
});

test('invalid saved AI settings recover to a disabled default and cannot bind the ambient logical key', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-invalid-ai-'));
  let app = await startServer({ directory, token: 'synthetic-settings-recovery-token', demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const saved = app.repo.get('settings', 'settings');
  for (const invalid of [{ ...saved.ai, effort: 'invalid' }, null, { ...saved.ai, providers: [] }]) {
    app.repo.put('settings', { ...saved, ai: invalid });
    await app.close();
    app = await startServer({ directory, token: 'synthetic-settings-recovery-token', demo: false });
    const recovered = app.repo.get('settings', 'settings');
    assert.equal(recovered.ai.enabled, false); assert.equal(recovered.ai.baseURL, DEFAULT_AI.baseURL);
    assert.match(recovered.credentialReferences['ai-key'], /^configuration-/);
    assert.ok(app.repo.events().some(event => /AI 设置无效/.test(event.detail)));
  }
});
