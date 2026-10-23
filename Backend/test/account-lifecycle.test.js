import test from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { saveAttachment } from '../src/attachments.js';

const token = 'boxmail-account-lifecycle-0123456789';
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-account-lifecycle-'));
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('account', { id: 'a', email: 'a@example.com', isDemo: false });
  return { ...app, remove: async () => {
    const response = await fetch(`http://127.0.0.1:${app.port}/accounts/a`, {
      method: 'DELETE', headers: { 'X-Boxmail-Token': token },
    });
    return { status: response.status, body: await response.json() };
  } };
}

test('account removal waits for a sending draft and preserves its local data', async t => {
  const { repo, remove } = await fixture(t);
  const draft = { id: 'd', accountId: 'a', status: 'sending', attachmentIds: [] };
  repo.put('draft', draft);
  assert.equal((await remove()).status, 409);
  assert.ok(repo.get('account', 'a'));
  assert.deepEqual(repo.get('draft', 'd'), draft);
  repo.put('draft', { ...draft, status: 'draft' });
  assert.equal((await remove()).status, 200);
  assert.equal(repo.get('account', 'a'), null);
  assert.equal(repo.get('draft', 'd'), null);
});

test('account removal cleans retained-mail attachments and preserves references from other accounts', async t => {
  const { repo, remove } = await fixture(t);
  repo.put('account', { id: 'b', email: 'b@example.com', isDemo: false });
  const recoveryFile = await saveAttachment(repo, 'old', 'recovery.txt', Buffer.from('恢复记录附件'));
  const relocationFile = await saveAttachment(repo, 'moving', 'relocation.txt', Buffer.from('移动记录附件'));
  const sharedFile = await saveAttachment(repo, 'shared', 'shared.txt', Buffer.from('其他账户仍引用'));
  for (const [kind, id, file] of [['recovery', 'old', recoveryFile], ['relocation', 'moving', relocationFile]]) {
    repo.put(kind, { id, accountId: 'a', original: { id, accountId: 'a', attachmentIds: [file.id] } });
  }
  repo.put('message', { id: 'shared', accountId: 'a', attachmentIds: [sharedFile.id] });
  repo.put('recovery', { id: 'other', accountId: 'b',
    original: { id: 'other', accountId: 'b', attachmentIds: [sharedFile.id] } });
  assert.equal((await remove()).status, 200);
  for (const file of [recoveryFile, relocationFile]) {
    assert.equal(repo.get('attachment', file.id), null);
    await assert.rejects(access(file.path));
  }
  assert.ok(repo.get('attachment', sharedFile.id));
  await access(sharedFile.path);
  assert.ok(repo.get('recovery', 'other'));
});
