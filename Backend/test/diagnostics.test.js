import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Diagnostics, accountReference, diagnosticRoute, errorDiagnostic } from '../src/diagnostics.js';
import { unicodeJSON } from '../src/unicode.js';

test('runtime records rotate within their size budget and omit payloads, addresses and raw errors', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-diagnostics-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diagnostics = new Diagnostics(directory, { maxBytes: 700 });
  for (let i = 0; i < 40; i++) diagnostics.record('api.failed', {
    account: accountReference('private@example.test'), route: diagnosticRoute('/messages/private@example.test?apiKey=SECRET'),
    ...errorDiagnostic(Object.assign(new Error('SECRET response body'), { code: 'ECONNRESET' })),
    body: 'SECRET mail body', password: 'SECRET', apiKey: 'SECRET', durationMs: i,
  });
  await diagnostics.flush();
  const files = await readdir(path.join(directory, 'logs'));
  assert.equal(files.length, 3);
  for (const name of files) {
    const file = path.join(directory, 'logs', name), info = await stat(file), log = await readFile(file, 'utf8');
    assert.ok(info.size <= 700); assert.equal(info.mode & 0o777, 0o600);
    assert.equal(log.includes('SECRET'), false); assert.equal(log.includes('private@'), false);
    for (const line of log.trim().split('\n')) {
      const entry = JSON.parse(line); assert.equal(entry.code, 'ECONNRESET'); assert.equal(entry.route, '/messages/:id');
    }
  }
});

test('a log symlink cannot append diagnostics into credentials', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-diagnostics-link-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const file = path.join(directory, '.env'); await writeFile(file, 'SECRET');
  const diagnostics = new Diagnostics(directory);
  diagnostics.record('service.started'); await diagnostics.flush();
  await rm(diagnostics.file); await symlink(file, diagnostics.file);
  diagnostics.record('service.stopped'); await diagnostics.flush();
  assert.equal(await readFile(file, 'utf8'), 'SECRET');
});

test('repeated field repairs retain exact counts while coalescing duplicate records', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-diagnostics-coalesced-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diagnostics = new Diagnostics(directory);
  for (let i = 0; i < 100; i++) diagnostics.recordCoalesced('data.unicode.repaired', {
    phase: 'response', route: '/state', field: '$.messages[0].subject', record: accountReference('synthetic'),
    requestID: `synthetic-${i}`, expectedType: 'unicode_string', actualType: 'unpaired_surrogate',
    body: 'SECRET',
  });
  await diagnostics.flush();
  const raw = await readFile(diagnostics.file, 'utf8');
  const entries = raw.trim().split('\n').map(JSON.parse);
  assert.equal(entries.length, 2);
  assert.equal(entries.reduce((sum, item) => sum + item.count, 0), 100);
  assert.equal(raw.includes('SECRET'), false);
});

test('field diagnostics never expose private dictionary keys or record values', () => {
  const issues = [];
  unicodeJSON({ messages: [{ id: 'private-mail-id', accountId: 'private-account-id',
    properties: { 'private@example.test': 'PRIVATE VALUE\uD800' } }] }, { onInvalid: issue => issues.push(issue) });
  assert.equal(issues.length, 1);
  assert.ok(issues[0].field.startsWith('$.messages[0].'));
  assert.ok(issues[0].field.endsWith('.:key'));
  assert.equal(issues[0].record, accountReference('private-mail-id'));
  const evidence = JSON.stringify(issues);
  for (const secret of ['private@example.test', 'private-mail-id', 'private-account-id', 'PRIVATE VALUE'])
    assert.equal(evidence.includes(secret), false);
});

test('bounded logging reports dropped entries instead of hiding evidence gaps', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-diagnostics-pressure-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const diagnostics = new Diagnostics(directory);
  for (let i = 0; i < 300; i++) diagnostics.record('api.failed', { status: 502 });
  await diagnostics.flush();
  const entries = (await readFile(diagnostics.file, 'utf8')).trim().split('\n').map(JSON.parse);
  assert.equal(entries.filter(item => item.event === 'api.failed').length, 256);
  assert.equal(entries.find(item => item.event === 'diagnostics.dropped').count, 44);
});
