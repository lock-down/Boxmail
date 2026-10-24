import test from 'node:test';
import assert from 'node:assert/strict';
import { access, mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { saveAttachment } from '../src/attachments.js';

test('deleting a draft releases its unused files and keeps borrowed and retained-mail references', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-draft-lifecycle-'));
  const token = 'boxmail-draft-lifecycle-session-20261024';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const { repo } = app;
  const file = async (owner, name) => saveAttachment(repo, owner, name, Buffer.from(name), 'text/plain');
  const own = await file('d1', 'own.txt');
  const removed = await file('d1', 'removed-before-save.txt');
  const borrowed = await file('mail', 'borrowed.txt');
  const shared = await file('d1', 'shared.txt');
  const retained = await file('d1', 'retained.txt');
  repo.put('draft', { id: 'd1', status: 'draft', attachmentIds: [own.id, borrowed.id, shared.id, retained.id] });
  repo.put('draft', { id: 'd2', status: 'draft', attachmentIds: [shared.id] });
  repo.put('message', { id: 'mail', attachmentIds: [borrowed.id] });
  repo.put('recovery', { id: 'recovery', original: { id: 'moving', attachmentIds: [retained.id] } });
  const remove = async id => {
    const response = await fetch(`http://127.0.0.1:${app.port}/drafts/${id}`, {
      method: 'DELETE', headers: { 'X-Boxmail-Token': token },
    });
    assert.equal(response.status, 200);
  };
  await remove('d1');
  for (const item of [own, removed]) {
    assert.equal(repo.get('attachment', item.id), null);
    await assert.rejects(access(item.path));
  }
  for (const item of [borrowed, shared, retained]) {
    assert.ok(repo.get('attachment', item.id));
    await access(item.path);
  }
  await remove('d2');
  assert.equal(repo.get('attachment', shared.id), null);
  await assert.rejects(access(shared.path));
  for (const item of [borrowed, retained]) await access(item.path);
});
