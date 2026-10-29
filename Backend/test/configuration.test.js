import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { Repository } from '../src/database.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { exportConfiguration, inspectConfiguration, importConfiguration } from '../src/configuration.js';
import { startServer } from '../src/server.js';

const account = (id, email) => ({ id, email, name: email, username: email, imapHost: 'imap.example.test',
  smtpHost: 'smtp.example.test', imapPort: 993, smtpPort: 465, imapTLS: true, smtpTLS: true, isDemo: false });
const settings = () => ({ id: 'settings', ai: structuredClone(DEFAULT_AI), preferences: {
  syncMinutes: 5, fontSize: 14, markRead: true, launchAtLogin: false, notifications: false,
  blockRemoteImages: true, spamFilter: true, signature: '原签名', language: '简体中文' } });
const input = () => ({ accounts: [account('foreign', 'me@example.test'), account('new', 'new@example.test')],
  settings: { ...settings(), preferences: { ...settings().preferences, signature: '导入签名' } } });
const reference = () => 'configuration-' + randomUUID();
function body(repo, configuration = input()) {
  const plan = inspectConfiguration(repo, configuration);
  return { configuration, ...plan, approved: true, credentialReferences: Object.fromEntries(
    ['ai-key', ...plan.accounts.map(a => 'mail-' + a.accountId)].map(key => [key, reference()])) };
}
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-configuration-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('settings', settings());
  repo.put('account', { ...account('existing', 'ME@example.test'), lastSync: '2026-10-22T01:00:00Z' });
  repo.put('account', account('other', 'other@example.test'));
  return repo;
}

test('configuration export includes settings and real accounts without data or credential references', async t => {
  const repo = await fixture(t);
  repo.put('account', { ...account('demo', 'demo@example.test'), isDemo: true });
  repo.put('settings', { ...settings(), credentialReferences: { 'ai-key': reference() }, secret: 'not-exportable' });
  repo.put('message', { id: 'private-message', body: 'private message content' });
  const exported = exportConfiguration(repo);
  assert.equal(exported.accounts.length, 2);
  assert.equal(exported.accounts[0].lastSync, null);
  assert.equal(exported.settings.credentialReferences, undefined);
  assert.equal(exported.settings.secret, undefined);
  assert.doesNotMatch(JSON.stringify(exported), /private-message|private message content|configuration-/);
});

test('configuration import merges by email and preserves account IDs, sync history, mail and unrelated accounts', async t => {
  const repo = await fixture(t);
  const original = { id: 'message', accountId: 'existing', body: '已有正文', contentType: 'application/octet-stream' };
  for (const kind of ['message', 'attachment', 'draft', 'job', 'mutation']) repo.put(kind, original);
  const request = body(repo);
  assert.equal(request.accounts.find(a => a.sourceId === 'foreign').accountId, 'existing');
  importConfiguration(repo, request);
  assert.equal(repo.list('account').length, 3);
  assert.equal(repo.get('account', 'foreign'), null);
  assert.equal(repo.get('account', 'existing').lastSync, '2026-10-22T01:00:00Z');
  for (const kind of ['message', 'attachment', 'draft', 'job', 'mutation']) assert.deepEqual(repo.get(kind, 'message'), original);
  assert.equal(repo.get('settings', 'settings').preferences.signature, '导入签名');
  assert.equal(repo.get('settings', 'settings').credentialReferences['ai-key'], request.credentialReferences['ai-key']);
  assert.ok(repo.get('account', 'other'));
  for (const value of Object.values(request.credentialReferences)) assert.ok(!JSON.stringify(repo.events()).includes(value));
});

test('malformed preferences, remote HTTP providers, duplicate and ambiguous accounts cannot change settings', async t => {
  const repo = await fixture(t);
  const before = JSON.stringify(repo.list('account'));
  for (const change of [
    value => { value.settings.preferences.syncMinutes = 0; },
    value => { value.settings.preferences.signature = 'x'.repeat(4001); },
    value => { value.settings.ai.baseURL = 'http://unsafe.example.test'; },
    value => { value.accounts.push({ ...value.accounts[0], id: 'duplicate' }); },
    value => { value.accounts[0].imapTLS = 'false'; },
  ]) { const value = input(); change(value); assert.throws(() => inspectConfiguration(repo, value)); }
  repo.put('account', account('duplicate-current', 'me@example.test'));
  assert.throws(() => inspectConfiguration(repo, input()), /多个/);
  repo.remove('account', 'duplicate-current');
  assert.equal(JSON.stringify(repo.list('account')), before);
  assert.equal(repo.get('settings', 'settings').preferences.signature, '原签名');
});

test('approval, stale previews, ID collisions and invalid credential references are rejected without partial import', async t => {
  const repo = await fixture(t);
  for (const change of [
    value => { value.approved = false; },
    value => { value.revision = 'stale'; },
    value => { value.accounts.find(a => a.sourceId === 'new').accountId = 'other'; },
    value => { value.credentialReferences['ai-key'] = 'mail-other'; },
    value => { value.accounts.push(value.accounts[0]); },
  ]) { const value = body(repo); change(value); assert.throws(() => importConfiguration(repo, value)); }
  const stale = body(repo);
  repo.put('settings', { ...settings(), ai: { ...DEFAULT_AI, model: 'changed' } });
  assert.throws(() => importConfiguration(repo, stale), /已变化/);
  assert.equal(repo.list('account').length, 2);
  assert.equal(repo.get('settings', 'settings').preferences.signature, '原签名');
});

test('database write failure rolls back all account and credential reference changes', async t => {
  const repo = await fixture(t), request = body(repo);
  const before = repo.list('account');
  const put = repo.put.bind(repo);
  repo.put = (kind, value) => { if (kind === 'settings') throw new Error('disk write failed'); return put(kind, value); };
  assert.throws(() => importConfiguration(repo, request), /disk write failed/);
  repo.put = put;
  assert.deepEqual(repo.list('account'), before);
  assert.equal(repo.get('settings', 'settings').credentialReferences, undefined);
});

test('settings-only import preserves accounts and all routing not replaced by the configuration', async t => {
  const repo = await fixture(t), oldReference = reference();
  repo.put('settings', { ...settings(), credentialReferences: { 'mail-other': oldReference } });
  importConfiguration(repo, body(repo, { accounts: [], settings: settings() }));
  assert.equal(repo.list('account').length, 2);
  assert.equal(repo.get('settings', 'settings').credentialReferences['mail-other'], oldReference);
});

test('HTTP configuration routes persist references through ordinary settings saves and keep secrets outside SQLite', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-config-api-'));
  const token = 'configuration-api-session-token-0123';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { method: 'POST',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  };
  assert.equal((await request('/configuration/export', {})).data.accounts.length, 0);
  const configuration = input();
  const plan = (await request('/configuration/inspect', { configuration })).data;
  const references = Object.fromEntries(['ai-key', ...plan.accounts.map(a => 'mail-' + a.accountId)].map(key => [key, reference()]));
  const imported = await request('/configuration/import', { configuration, ...plan, credentialReferences: references, approved: true });
  assert.equal(imported.status, 200);
  assert.equal(imported.data.settings.preferences.signature, '导入签名');
  assert.equal(imported.data.accounts.length, 2);
  assert.deepEqual(imported.data.settings.credentialReferences, references);
  await request('/settings', { preferences: { signature: '再次保存' } });
  assert.deepEqual(app.repo.get('settings', 'settings').credentialReferences, references);
  assert.equal((await request('/configuration/export', {})).data.settings.credentialReferences, undefined);
  assert.doesNotMatch(JSON.stringify(app.repo.list('settings')), /mailPasswords|apiKey|password/);
});

test('custom-only configuration imports require exactly their provider keys and preserve unrelated credentials', async t => {
  const repo = await fixture(t), oldReference = reference();
  repo.put('settings', { ...settings(), credentialReferences: { 'ai-key': oldReference, 'mail-other': reference() } });
  const custom = settings();
  custom.ai = { providerId: 'work', providers: [{ id: 'work', name: '工作模型', baseURL: 'https://example.com/v1',
    apiProtocol: 'openai-completions', model: 'work-model', models: [{ id: 'work-model', name: '工作', contextWindow: 256000,
      maxTokens: 32000, input: ['text', 'image'], reasoningEfforts: { off: null, high: 'max' } }] }] };
  const configuration = { accounts: [], settings: custom }, plan = inspectConfiguration(repo, configuration);
  const request = { configuration, ...plan, approved: true, credentialReferences: { 'ai-provider-work': reference() } };
  assert.throws(() => importConfiguration(repo, { ...request,
    credentialReferences: { ...request.credentialReferences, 'ai-key': reference() } }), /凭证保存状态/);
  importConfiguration(repo, request);
  assert.equal(repo.get('settings', 'settings').credentialReferences['ai-key'], oldReference);
  assert.deepEqual(exportConfiguration(repo).settings.ai.providers[0].models, custom.ai.providers[0].models);
  assert.equal(exportConfiguration(repo).settings.credentialReferences, undefined);
});

test('configuration imports with empty credentials detach changed mail identities and AI endpoints', async t => {
  const repo = await fixture(t);
  const oldReferences = { 'ai-key': reference(), 'mail-existing': reference(), 'mail-other': reference() };
  for (const change of [
    value => { value.accounts[0].imapHost = 'imap.attacker.test'; },
    value => { value.accounts[0].smtpHost = 'smtp.attacker.test'; },
    value => { value.accounts[0].username = 'different@example.test'; },
    value => { value.accounts[0].imapPort = 1993; },
    value => { value.accounts[0].smtpTLS = false; },
    value => { value.settings.ai.baseURL = 'https://attacker.test/v1'; },
    value => { value.settings.ai.baseURL = DEFAULT_AI.baseURL + '/untrusted-path'; },
    value => { value.settings.ai.apiProtocol = 'anthropic-messages'; },
  ]) {
    repo.put('settings', { ...settings(), credentialReferences: oldReferences });
    repo.put('account', account('existing', 'me@example.test'));
    const configuration = { accounts: [account('foreign', 'me@example.test')], settings: settings() };
    change(configuration);
    const plan = inspectConfiguration(repo, configuration);
    assert.ok(plan.credentialsRequired.length > 0);
    const imported = importConfiguration(repo, { configuration, ...plan, approved: true, credentialReferences: {} });
    assert.deepEqual(imported.credentialsRequired, plan.credentialsRequired);
    for (const logical of imported.credentialsRequired) {
      assert.match(imported.settings.credentialReferences[logical], /^configuration-[0-9a-f-]{36}$/);
      assert.ok(!Object.values(oldReferences).includes(imported.settings.credentialReferences[logical]));
    }
    assert.equal(imported.settings.credentialReferences['mail-other'], oldReferences['mail-other']);
  }
});

test('configuration imports preserve unchanged local bindings and accept fresh credentials at changed endpoints', async t => {
  const repo = await fixture(t);
  const oldReferences = { 'ai-key': reference(), 'mail-existing': reference(), 'mail-other': reference() };
  repo.put('settings', { ...settings(), credentialReferences: oldReferences });
  const configuration = { accounts: [account('foreign', 'me@example.test')], settings: settings() };
  configuration.accounts[0].username = repo.get('account', 'existing').username;
  let plan = inspectConfiguration(repo, configuration);
  const preserved = importConfiguration(repo, { configuration, ...plan, approved: true, credentialReferences: {} });
  assert.deepEqual(preserved.credentialsRequired, []);
  assert.deepEqual(preserved.settings.credentialReferences, oldReferences);
  configuration.accounts[0].imapHost = 'imap.new-provider.test';
  configuration.settings.ai.baseURL = 'https://new-provider.test/v1';
  plan = inspectConfiguration(repo, configuration);
  const supplied = { 'ai-key': reference(), 'mail-existing': reference() };
  const replaced = importConfiguration(repo, { configuration, ...plan, approved: true, credentialReferences: supplied });
  assert.deepEqual(replaced.credentialsRequired, []);
  assert.deepEqual(replaced.settings.credentialReferences, { ...oldReferences, ...supplied });
});
