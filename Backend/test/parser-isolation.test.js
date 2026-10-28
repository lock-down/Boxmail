import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, access } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { ParserProcess } from '../src/parser-process.js';
import { MailContentWorker } from '../src/mail-content-worker.js';
import { Diagnostics } from '../src/diagnostics.js';
import { startServer } from '../src/server.js';
import { syncAccount } from '../src/mail.js';
import { spawn } from 'node:child_process';

const fixture = new URL('./helpers/parser-fault.js', import.meta.url);
async function temporary() {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-parser-test-'));
  return directory;
}

test('a native SIGABRT is classified in the isolated parser, excludes raw stderr, and allows the next file', async t => {
  const directory = await temporary(), diagnostics = new Diagnostics(directory);
  const parser = new ParserProcess({ executable: fixture, diagnostics });
  t.after(async () => { await parser.close(); await rm(directory, { recursive: true, force: true }); });
  await assert.rejects(parser.run('pdf', Buffer.from('SYNTHETIC_ABORT'), { format: 'pdf' }), error => {
    assert.equal(error.code, 'PARSER_CRASH');
    assert.equal(error.parserExit.signal, 'SIGABRT');
    assert.equal(error.parserExit.reason, 'native_assertion');
    return true;
  });
  assert.equal(parser.child, null);
  assert.equal((await parser.run('pdf', Buffer.from('next file'), { format: 'pdf' })).text, 'healthy synthetic attachment');
  await diagnostics.flush();
  const log = await readFile(path.join(directory, 'logs/backend.jsonl'), 'utf8');
  assert.match(log, /SIGABRT/); assert.match(log, /native_assertion/);
  assert.equal(log.includes('private-document-content'), false);
});

test('parser subprocesses do not inherit mailbox credentials, ambient API keys or Node preload flags', async t => {
  const keys = ['BOXMAIL_TOKEN', 'BOXMAIL_ENV_FILE', 'OPENAI_API_KEY', 'NODE_OPTIONS', 'NODE_PATH'];
  const previous = Object.fromEntries(keys.map(key => [key, process.env[key]]));
  for (const key of keys) process.env[key] = key === 'NODE_OPTIONS' ? '--require=/not-a-real-preload.js' : 'synthetic-private';
  const parser = new ParserProcess({ executable: fixture });
  try { assert.equal((await parser.run('docx', Buffer.from('SYNTHETIC_ENV'))).text, 'clean'); }
  finally {
    await parser.close();
    for (const key of keys) if (previous[key] === undefined) delete process.env[key]; else process.env[key] = previous[key];
  }
});

test('the independent RSS guard stops native allocations even while the parser event loop is blocked', { timeout: 10000 }, async t => {
  const parser = new ParserProcess({ executable: fixture, rssLimitBytes: 128 * 1024 * 1024 });
  t.after(() => parser.close());
  await assert.rejects(parser.run('pdf', Buffer.from('SYNTHETIC_NATIVE_MEMORY'), { format: 'pdf' }), error => {
    assert.equal(error.code, 'PARSER_MEMORY_LIMIT');
    assert.equal(error.parserExit.reason, 'memory_limit');
    return true;
  });
  assert.equal(parser.child, null);
});

test('cancellation terminates owned parser descendants and removes their private temporary directory', async t => {
  const directory = await temporary(), pidFile = path.join(directory, 'helper.pid');
  const controller = new AbortController(), parser = new ParserProcess({ executable: fixture, signal: controller.signal });
  t.after(async () => { await parser.close(); await rm(directory, { recursive: true, force: true }); });
  const pending = parser.run('docx', Buffer.from('SYNTHETIC_HANG'), { pidFile });
  const outcome = pending.catch(error => error);
  for (let i = 0; i < 200; i++) {
    if (await access(pidFile).then(() => true, () => false)) break;
    await delay(5);
  }
  const pid = Number(await readFile(pidFile, 'utf8')), privateDirectory = parser.directory;
  controller.abort(new Error('synthetic stop'));
  assert.match((await outcome).message, /synthetic stop/);
  for (let i = 0; i < 100; i++) {
    try { process.kill(pid, 0); } catch { break; }
    await delay(10);
  }
  assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' });
  await assert.rejects(access(privateDirectory), { code: 'ENOENT' });
});

function mail(uid, broken = false) {
  return Buffer.from(`From: sender@example.test\r\nSubject: Synthetic ${uid}\r\nMIME-Version: 1.0\r\n`
    + `Content-Type: multipart/mixed; boundary="fixture"\r\n\r\n--fixture\r\nContent-Type: text/plain\r\n\r\nBody\r\n`
    + '--fixture\r\nContent-Type: application/pdf\r\nContent-Disposition: attachment; filename="fixture.pdf"\r\n'
    + 'Content-Transfer-Encoding: base64\r\n\r\n' + Buffer.from(broken ? 'SYNTHETIC_ABORT' : 'healthy-file').toString('base64')
    + '\r\n--fixture--\r\n');
}

for (const fault of ['pdf', 'mime']) test(`a fatal ${fault} during two-account sync keeps HTTP, other mail and account checkpoints usable`, { timeout: 10000 }, async t => {
  const directory = await temporary(), token = 'synthetic-parser-regression-session';
  let broken = true;
  const app = await startServer({ directory, token, demo: false, mailSync: async (repo, account, password, options) => {
    const worker = new MailContentWorker({ signal: options.signal, executable: fixture,
      diagnostics: repo.diagnostics });
    try {
      return await syncAccount(repo, account, password, { ...options, contentWorker: worker,
        clientFactory: () => ({
          mailbox: { path: 'INBOX', uidValidity: '1' }, async connect() {}, async logout() {}, close() {},
          async list() { return [{ path: 'INBOX' }]; }, async getMailboxLock() { return { release() {} }; },
          async status() { return { messages: 3, uidValidity: '1', uidNext: 4 }; },
          async search() { return [1, 2, 3]; },
          async *fetch(page) { for (const uid of page) yield { uid, flags: new Set(), size: 500 }; },
          async fetchOne(uid) {
            const bad = broken && account.id === 'a1' && uid === 3;
            return { uid, source: bad && fault === 'mime' ? Buffer.from('SYNTHETIC_ABORT') : mail(uid, bad) };
          },
        }),
      });
    } finally { await worker.close(); }
  } });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      method: body ? 'POST' : 'GET', ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(1000),
    });
    assert.equal(response.status, 200); return response.json();
  };
  for (const id of ['a1', 'a2']) app.repo.put('account', { id, email: `${id}@example.test` });
  await Promise.all(['a1', 'a2'].map(accountId => request('/sync', { accountId, password: 'synthetic', background: true })));
  let snapshot;
  for (let i = 0; i < 600; i++) {
    snapshot = await request('/sync-status');
    if (!snapshot.runningAccounts.length) break;
    await delay(5);
  }
  assert.equal(snapshot.runningAccounts.length, 0);
  assert.equal(snapshot.results.find(result => result.accountId === 'a2').status, 'completed');
  assert.equal(snapshot.results.find(result => result.accountId === 'a1').status, fault === 'mime' ? 'paused' : 'completed');
  assert.equal(app.repo.list('message').length, fault === 'mime' ? 5 : 6);
  const attachments = app.repo.list('attachment');
  assert.equal(attachments.length, fault === 'mime' ? 5 : 6);
  const failed = attachments.filter(item => item.parseError);
  assert.equal(failed.length, fault === 'mime' ? 0 : 1);
  if (fault === 'pdf') assert.equal((await readFile(failed[0].path)).toString(), 'SYNTHETIC_ABORT');
  assert.equal(attachments.filter(item => item.text === 'healthy synthetic attachment').length, 5);
  await request('/health');
  broken = false;
  assert.equal((await request('/sync', { accountId: 'a1', password: 'synthetic', background: true })).ok, true);
  for (let i = 0; i < 600; i++) {
    snapshot = await request('/sync-status');
    if (!snapshot.runningAccounts.length) break;
    await delay(5);
  }
  assert.equal(snapshot.results.find(result => result.accountId === 'a1').status, 'completed');
  assert.equal(app.repo.list('message').length, 6);
});

test('a busy parser is terminated when its backend owner dies and removes its scratch directory', { timeout: 10000 }, async t => {
  const directory = await temporary(), readyFile = path.join(directory, 'ready');
  const manager = spawn(process.execPath, [new URL('./helpers/parser-owner-manager.js', import.meta.url).pathname, readyFile],
    { stdio: ['ignore', 'pipe', 'ignore'] });
  let output = '', parser;
  manager.stdout.on('data', bytes => { output += bytes.toString(); });
  t.after(async () => {
    manager.kill('SIGKILL');
    if (parser) try { process.kill(-parser.pid, 'SIGKILL'); } catch {}
    await rm(directory, { recursive: true, force: true });
  });
  for (let i = 0; i < 300; i++) {
    if (output.includes('\n') && await access(readyFile).then(() => true, () => false)) break;
    await delay(5);
  }
  parser = JSON.parse(output.trim());
  const closed = new Promise(resolve => manager.once('close', resolve));
  manager.kill('SIGKILL'); await closed;
  for (let i = 0; i < 200; i++) {
    try { process.kill(parser.pid, 0); } catch { break; }
    await delay(10);
  }
  assert.throws(() => process.kill(parser.pid, 0), { code: 'ESRCH' });
  await assert.rejects(access(parser.directory), { code: 'ENOENT' });
});
