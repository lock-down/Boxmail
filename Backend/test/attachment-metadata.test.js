import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { saveAttachment, extractText, copyBorrowedAttachments } from '../src/attachments.js';
import { parseMailContent } from '../src/mail-content-worker.js';
import { startServer } from '../src/server.js';
import { accountReference } from '../src/diagnostics.js';
import { createBackup, inspectBackup } from '../src/backups.js';

const fallback = 'application/octet-stream';
const malformedMail = Buffer.from([
  'From: sender@example.test', 'Subject: Synthetic attachment metadata', 'MIME-Version: 1.0',
  'Content-Type: multipart/mixed; boundary="metadata"', '', '--metadata', 'Content-Type: text/plain', '',
  'Readable original body', '--metadata', 'Content-Type:',
  'Content-Disposition: attachment; filename="original.txt"', '', 'Original attachment bytes', '--metadata--', '',
].join('\r\n'));

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-attachment-metadata-'));
  const app = await startServer({ directory, token: 'synthetic-attachment-metadata-session', demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  return { ...app, directory, async get(route) {
    const res = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': 'synthetic-attachment-metadata-session' } });
    assert.equal(res.status, 200);
    return res.json();
  } };
}

test('empty Content-Type MIME headers cannot persist boolean attachment metadata', async t => {
  const { repo } = await fixture(t);
  const parsed = await parseMailContent('mime', malformedMail);
  assert.equal(parsed.parsed.attachments[0].contentType, false); // Actual mailparser contract for this malformed header.
  assert.equal(parsed.content.body, 'Readable original body');
  const part = parsed.parsed.attachments[0];
  const attachment = await saveAttachment(repo, 'owner', part.filename, part.content, part.contentType);
  assert.equal(attachment.contentType, fallback);
  assert.equal(attachment.text, 'Original attachment bytes');
  assert.equal(attachment.parseError, '');
  assert.deepEqual(await readFile(attachment.path), part.content);
  assert.equal(repo.get('attachment', attachment.id).contentType, fallback);
});

test('legacy cached MIME types cannot break full, compact, metadata or copied attachment reads', async t => {
  const { repo, get } = await fixture(t);
  const original = await saveAttachment(repo, 'owner', 'original.txt', Buffer.from('Original bytes'), 'text/plain');
  for (const [index, value] of [false, true, null, 12, {}, [], '', 'false'].entries()) {
    const record = { ...original, id: 'legacy-' + index, contentType: value, analysis: 'Existing AI result' };
    repo.db.prepare('INSERT INTO records VALUES(?,?,?)').run('attachment', record.id, JSON.stringify(record));
  }
  for (const route of ['/state', '/state?compact=1&previews=0']) {
    const state = await get(route);
    const legacy = state.attachments.filter(a => a.id.startsWith('legacy-'));
    assert.equal(legacy.length, 8);
    assert.ok(legacy.every(a => a.contentType === fallback));
    assert.ok(legacy.every(a => a.name === original.name && a.size === original.size));
  }
  const full = await get('/attachments/legacy-0/metadata');
  assert.equal(full.contentType, fallback); assert.equal(full.analysis, 'Existing AI result');
  assert.equal(full.text, original.text);
  assert.deepEqual(Buffer.from((await get('/attachments/legacy-0')).content, 'base64'), await readFile(original.path));
  const [copyId] = await copyBorrowedAttachments(repo, ['legacy-0'], 'forward-draft');
  const copied = repo.get('attachment', copyId);
  assert.equal(copied.contentType, fallback); assert.equal(copied.analysis, full.analysis);
  assert.deepEqual(await readFile(copied.path), await readFile(original.path));
  repo.put('attachment', { ...original, id: 'new-record', contentType: false });
  assert.equal(JSON.parse(repo.db.prepare("SELECT data FROM records WHERE kind='attachment' AND id='new-record'").get().data).contentType, fallback);
  await repo.diagnostics.flush();
  const log = await readFile(path.join(repo.directory, 'logs/backend.jsonl'), 'utf8');
  const entries = log.trim().split('\n').map(JSON.parse).filter(row => row.event === 'data.attachment.repaired');
  assert.ok(entries.some(row => row.field === '$.contentType' && row.actualType === 'boolean'
    && row.record === accountReference('legacy-0') && row.expectedType === 'string'));
  assert.equal(log.includes('Existing AI result'), false); assert.equal(log.includes('Original bytes'), false);
});

test('reopening repairs only invalid cached MIME metadata and permits a complete backup', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-legacy-metadata-'));
  let repo = new Repository(directory);
  t.after(async () => { repo?.close(); await rm(directory, { recursive: true, force: true }); });
  const attachment = await saveAttachment(repo, 'owner', 'original.txt', Buffer.from('Original bytes'), 'text/plain');
  const legacy = { ...attachment, contentType: false, analysis: 'Existing AI result', text: 'Original legacy text \uD800' };
  repo.db.prepare("UPDATE records SET data=? WHERE kind='attachment' AND id=?").run(JSON.stringify(legacy), legacy.id);
  repo.close(); repo = null;
  const app = await startServer({ directory, token: 'synthetic-metadata-restart-token', demo: false });
  try {
    const raw = JSON.parse(app.repo.db.prepare("SELECT data FROM records WHERE kind='attachment' AND id=?").get(legacy.id).data);
    assert.deepEqual(raw, { ...legacy, contentType: fallback });
    assert.deepEqual(await readFile(attachment.path), Buffer.from('Original bytes'));
    const archive = path.join(directory, 'metadata-backup.zip');
    await createBackup(app.repo, archive);
    assert.equal((await inspectBackup(archive)).counts.attachment, 1);
  } finally { await app.close(); }
});

test('attachment extraction accepts an unknown MIME value without calling string methods on a boolean', async () => {
  assert.equal(await extractText(Buffer.from('Original bytes'), 'unknown.bin', false), '');
});
