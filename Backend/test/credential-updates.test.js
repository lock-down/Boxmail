import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { startServer } from '../src/server.js';

const reference = () => 'configuration-' + randomUUID();
const account = { id: 'account', email: 'me@example.test', username: 'me@example.test',
  name: 'Original', imapHost: 'imap.example.test', smtpHost: 'smtp.example.test',
  imapPort: 993, smtpPort: 465, imapTLS: true, smtpTLS: true, isDemo: false };

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-credential-save-'));
  const token = 'synthetic-credential-update-test-token';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const post = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { method: 'POST',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  return { ...app, post };
}

test('account saves publish the account and its new credential binding together', async t => {
  const app = await fixture(t), key = reference();
  const saved = await app.post('/accounts', { account, credentialReferences: { 'mail-account': key } });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.account.email, account.email);
  assert.equal(saved.body.settings.credentialReferences['mail-account'], key);
  const before = app.repo.get('account', account.id);
  for (const credentialReferences of [{ 'mail-other': reference() }, { 'mail-account': 'mail-other' }, null]) {
    assert.equal((await app.post('/accounts', { account: { ...account, name: 'Changed' }, credentialReferences })).status, 400);
    assert.deepEqual(app.repo.get('account', account.id), before);
    assert.equal(app.repo.get('settings', 'settings').credentialReferences['mail-account'], key);
  }
});

test('a settings write failure rolls back the account edit and preserves its previous binding', async t => {
  const app = await fixture(t), old = reference();
  await app.post('/accounts', { account, credentialReferences: { 'mail-account': old } });
  const before = app.repo.get('account', account.id), put = app.repo.put.bind(app.repo);
  app.repo.put = (kind, value) => { if (kind === 'settings') throw new Error('Synthetic disk write failure'); return put(kind, value); };
  const result = await app.post('/accounts', { account: { ...account, name: 'Changed' },
    credentialReferences: { 'mail-account': reference() } });
  app.repo.put = put;
  assert.equal(result.status, 500);
  assert.deepEqual(app.repo.get('account', account.id), before);
  assert.equal(app.repo.get('settings', 'settings').credentialReferences['mail-account'], old);
});

test('AI settings bind only their own staged keys and preserve unrelated account credentials', async t => {
  const app = await fixture(t), mailKey = reference(), aiKey = reference();
  await app.post('/accounts', { account, credentialReferences: { 'mail-account': mailKey } });
  const saved = await app.post('/settings', { preferences: { signature: 'Saved' },
    credentialReferences: { 'ai-key': aiKey } });
  assert.equal(saved.status, 200);
  assert.deepEqual(saved.body.credentialReferences, { 'mail-account': mailKey, 'ai-key': aiKey });
  for (const credentialReferences of [{ 'mail-account': reference() }, { 'ai-key': 'invalid' }]) {
    assert.equal((await app.post('/settings', { preferences: { signature: 'Rejected' }, credentialReferences })).status, 400);
    assert.equal(app.repo.get('settings', 'settings').preferences.signature, 'Saved');
    assert.deepEqual(app.repo.get('settings', 'settings').credentialReferences, saved.body.credentialReferences);
  }
  await app.post('/settings', { preferences: { signature: 'Legacy client' } });
  await app.post('/accounts', { account: { ...account, name: 'Legacy edit' } });
  assert.deepEqual(app.repo.get('settings', 'settings').credentialReferences, saved.body.credentialReferences);
  assert.doesNotMatch(JSON.stringify(app.repo.list('settings')), /password|apiKey/);
});
