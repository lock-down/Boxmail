import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import path from 'node:path';
import net from 'node:net';
import { ImapFlow } from 'imapflow';
import { Repository } from '../src/database.js';
import { syncAccount } from '../src/mail.js';
import { messageSource } from '../src/mail-sync.js';
import { syncSession } from '../src/sync-session.js';

const windowSize = 256 * 1024;
const source = Buffer.concat([Buffer.from('From: Sender <sender@example.test>\r\nSubject: Large fixture\r\n'
  + 'Message-ID: <large@example.test>\r\nContent-Type: text/plain\r\n\r\n'), Buffer.alloc(1024 * 1024 + 37, 97)]);
const remote = () => ({ uid: 7, size: source.length });
function response(uid, bytes, origin) {
  return { uid, source: bytes, ...(origin == null ? {} : { partialOrigins: new Map([['', origin]]) }) };
}

test('a server ignoring partial FETCH windows falls back to one complete source without duplicating bytes', async () => {
  const queries = [];
  const result = await messageSource({ async fetchOne(uid, query) {
    queries.push(query);
    return response(uid, source, typeof query.source === 'object' ? 0 : undefined);
  } }, remote(), {});
  assert.deepEqual(result, source);
  assert.equal(queries.length, 2);
  assert.equal(queries[1].source, true);
});

test('repeated or late partial offsets cannot be appended as the next body chunk', async () => {
  const queries = [];
  const result = await messageSource({ async fetchOne(uid, query) {
    queries.push(query);
    return query.source === true ? response(uid, source)
      : response(uid, source.subarray(0, windowSize), 0);
  } }, remote(), {});
  assert.deepEqual(result, source);
  assert.equal(queries.at(-1).source, true);
  assert.ok(queries.length <= 6);
});

for (const delta of [-2000, 2000]) test(`a size estimate off by ${delta} bytes is verified with a complete source`, async () => {
  let fullRequests = 0;
  const result = await messageSource({ async fetchOne(uid, query) {
    if (query.source === true) { fullRequests++; return response(uid, source); }
    const { start, maxLength } = query.source;
    return response(uid, source.subarray(start, start + maxLength), start);
  } }, { ...remote(), size: source.length + delta }, {});
  assert.deepEqual(result, source);
  assert.equal(fullRequests, 1);
});

test('an omitted source is retried on its own when a combined INTERNALDATE request returns no body', async () => {
  const queries = [], small = Buffer.from('Subject: Small fixture\r\n\r\nBody');
  const result = await messageSource({ async fetchOne(uid, query) {
    queries.push(query);
    return query.internalDate ? { uid, internalDate: new Date('2026-10-25T00:00:00Z') } : response(uid, small);
  } }, { uid: 7, size: small.length }, {});
  assert.deepEqual(result, small);
  assert.equal(queries.length, 2);
  assert.equal(queries[0].internalDate, true);
  assert.equal(queries[1].internalDate, undefined);
});

test('a foreign UID is never accepted as the requested message body', async () => {
  let calls = 0;
  const result = await messageSource({ async fetchOne(uid) {
    calls++;
    return response(calls === 1 ? 8 : uid, Buffer.from('Subject: Correct\r\n\r\nBody'));
  } }, { uid: 7, size: 100 }, {});
  assert.match(result.toString(), /Correct/);
  assert.equal(calls, 2);
  await assert.rejects(messageSource({ async fetchOne() { return response(8, source); } }, remote(), {}), /完整.*正文/);
});

test('a server rejecting partial FETCH still supports complete-source recovery', async () => {
  let requests = 0;
  const result = await messageSource({ async fetchOne(uid, query) {
    requests++;
    if (query.source !== true) throw Object.assign(new Error('synthetic unsupported range'), { responseStatus: 'BAD' });
    return response(uid, source);
  } }, remote(), {});
  assert.deepEqual(result, source);
  assert.equal(requests, 4);
});

test('an empty complete source for a nonempty message remains missing after bounded retries', async () => {
  let requests = 0;
  const result = await messageSource({ async fetchOne(uid) {
    requests++; return response(uid, Buffer.alloc(0));
  } }, { uid: 7, size: 100 }, {});
  assert.equal(result, undefined);
  assert.equal(requests, 3);
});

test('an exact multiple of the partial window confirms EOF without duplicating the last chunk', async () => {
  const bytes = Buffer.alloc(5 * windowSize, 97), queries = [];
  const result = await messageSource({ async fetchOne(uid, query) {
    queries.push(query);
    const { start, maxLength } = query.source;
    return response(uid, bytes.subarray(start, start + maxLength), start);
  } }, { uid: 7, size: bytes.length }, {});
  assert.deepEqual(result, bytes);
  assert.equal(queries.length, 6);
  assert.equal(queries.at(-1).source.start, bytes.length);
});

test('a source exceeding the download ceiling is rejected rather than cached as a complete body', async () => {
  const tooLarge = Buffer.alloc(25 * 1024 * 1024 + 1, 97);
  await assert.rejects(messageSource({ async fetchOne(uid) { return response(uid, tooLarge); } }, remote(), {}), /完整.*正文/);
});

test('a truncated transfer that cannot be recovered never becomes completed mail', async () => {
  let calls = 0;
  await assert.rejects(messageSource({ async fetchOne(uid) {
    return ++calls === 1 ? response(uid, source.subarray(0, windowSize), 0) : false;
  } }, remote(), {}), /完整.*正文/);
  assert.ok(calls <= 7);
});

test('cancellation stops empty-source retries immediately', async () => {
  const controller = new AbortController();
  let calls = 0;
  await assert.rejects(messageSource({ async fetchOne() {
    calls++; controller.abort(new Error('stop source recovery')); return false;
  } }, remote(), { signal: controller.signal }), /stop source recovery/);
  assert.equal(calls, 1);
});

test('each source attempt retains its deadline and closes a stalled connection', async () => {
  let closes = 0;
  await assert.rejects(messageSource({ fetchOne: () => new Promise(() => {}), close() { closes++; } },
    remote(), { timeoutMs: 20 }), /超时/);
  assert.equal(closes, 1);
});

const account = { id: 'a1', email: 'reader@example.test', imapHost: 'synthetic.example.test' };
async function fixture(t, boxes) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-source-recovery-'));
  const repo = new Repository(directory);
  repo.put('account', account);
  const state = { attempts: new Map(), unavailable: new Set(), transient: new Map(), sourceDownloads: [],
    connections: 0, validityChange: false, bodyDelay: 0, downloadBudgetMs: undefined };
  const clientFactory = () => {
    let selected;
    return {
      mailbox: {}, async connect() { state.connections++; }, async logout() {}, close() {},
      async list() { return Object.keys(boxes).map(folder => ({ path: folder,
        ...(folder === 'Sent' ? { specialUse: '\\Sent' } : {}) })); },
      async getMailboxLock(folder) {
        selected = folder;
        this.mailbox = { path: folder, uidValidity: state.validityChange && state.connections > 1 ? '11' : '10', exists: boxes[folder] };
        return { release() {} };
      },
      async status(folder) { return { messages: boxes[folder], uidValidity: '10' }; },
      async search() { return Array.from({ length: boxes[selected] }, (_, i) => i + 1); },
      async *fetch(page) {
        for (const uid of page) yield { uid, flags: new Set(),
          size: uid === boxes[selected] - (selected === 'INBOX' ? 69 : 2) ? source.length + 200 : 200 };
      },
      async fetchOne(uid, query) {
        if (state.bodyDelay) await delay(state.bodyDelay);
        const key = `${selected}:${uid}`;
        state.attempts.set(key, (state.attempts.get(key) || 0) + 1);
        if (state.unavailable.has(key) || state.attempts.get(key) <= (state.transient.get(key) || 0)) return false;
        if (uid === boxes[selected] - (selected === 'INBOX' ? 69 : 2)) return response(uid, source);
        state.sourceDownloads.push(key);
        return response(uid, Buffer.from(`From: Sender <sender@example.test>\r\nSubject: Mail ${uid}\r\n`
          + `Message-ID: <${selected}-${uid}@example.test>\r\n\r\nBody`));
      },
    };
  };
  const run = () => syncSession(repo, { ...account }, 'synthetic-password', {
    syncBatch: (repo, account, password, options) => syncAccount(repo, account, password,
      { ...options, clientFactory, downloadBudgetMs: state.downloadBudgetMs }),
  });
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return { repo, state, run };
}

test('one session passes the 69-mail and 2-mail barriers and completes 12073 inbox plus 543 sent messages', { timeout: 60000 }, async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 12073, Sent: 543 });
  const result = await run();
  assert.equal(result.partial, false);
  assert.equal(repo.syncMessageHeaders('a1', 'INBOX').length, 12073);
  assert.equal(repo.syncMessageHeaders('a1', 'Sent').length, 543);
  assert.ok(repo.list('sync').every(progress => progress.status === 'completed' && !progress.hasMore));
  assert.equal(new Set(state.sourceDownloads).size, 12614);
  assert.equal(state.sourceDownloads.length, 12614);
});

test('one unavailable body does not block older history or another folder and is retried on the next session', async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 605, Sent: 5 });
  state.unavailable.add('INBOX:603');
  const result = await run();
  assert.equal(result.partial, true);
  assert.equal(repo.list('message').length, 609);
  const progress = repo.list('sync').find(progress => progress.folder === 'inbox');
  assert.equal(progress.status, 'paused');
  assert.equal(progress.remaining, 1);
  assert.equal(progress.hasMore, true);
  assert.match(progress.lastError, /1.*正文/);
  assert.ok(state.attempts.get('INBOX:603') <= 6);
  assert.ok(state.connections > 1);
  state.unavailable.clear();
  assert.equal((await run()).partial, false);
  assert.equal(repo.list('message').length, 610);
  assert.equal(new Set(state.sourceDownloads).size, 608);
  assert.equal(state.sourceDownloads.length, 608);
});

test('a temporarily missing body is automatically recovered after healthy history finishes', async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 405 });
  state.transient.set('INBOX:403', 3);
  assert.equal((await run()).partial, false);
  assert.equal(repo.list('message').length, 405);
  assert.equal(state.attempts.get('INBOX:403'), 4);
  assert.equal(state.sourceDownloads.at(-1), 'INBOX:403');
});

test('repeated unavailable bodies stop at a finite failure budget while another folder still completes', async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 405, Sent: 5 });
  state.bodyDelay = 2; state.downloadBudgetMs = 1;
  for (const uid of [405, 404, 403]) state.unavailable.add(`INBOX:${uid}`);
  assert.equal((await run()).partial, true);
  assert.equal(repo.list('message').length, 5);
  assert.equal(state.attempts.get('INBOX:402'), undefined);
  assert.ok([...state.attempts.values()].every(attempts => attempts <= 3));
  const progress = repo.list('sync').find(progress => progress.folder === 'inbox');
  assert.equal(progress.remaining, 405);
  assert.equal(progress.source.failedCount, 3);
  assert.equal(progress.source.deferredOnly, false);
  assert.equal(progress.source.consecutiveFailures, 3);
});

test('a single failed body consuming the pass budget still yields to older healthy mail', async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 5 });
  state.bodyDelay = 2; state.downloadBudgetMs = 1;
  state.unavailable.add('INBOX:5');
  assert.equal((await run()).partial, true);
  assert.equal(repo.list('message').length, 4);
  assert.ok(repo.list('message').every(message => message.uid < 5));
  assert.equal(state.attempts.get('INBOX:5'), 6);
  assert.equal(repo.list('sync')[0].remaining, 1);
});

test('a UIDVALIDITY change on body recovery cannot mix two folder identities', async t => {
  const { repo, state, run } = await fixture(t, { INBOX: 10 });
  state.unavailable.add('INBOX:8'); state.validityChange = true;
  await assert.rejects(run(), /文件夹身份已变化/);
  const messages = repo.list('message');
  assert.equal(messages.length, 2);
  assert.ok(messages.every(message => message.uidValidity === '10'));
  assert.equal(state.attempts.get('INBOX:7'), undefined);
});

test('a real ImapFlow exchange tolerates a server ignoring BODY.PEEK byte ranges', { timeout: 10000 }, async t => {
  const sockets = new Set(), commands = [];
  const server = net.createServer(socket => {
    sockets.add(socket); socket.on('close', () => sockets.delete(socket));
    let input = '';
    socket.write('* OK [CAPABILITY IMAP4rev1] synthetic server\r\n');
    socket.on('data', data => {
      input += data.toString();
      while (input.includes('\r\n')) {
        const end = input.indexOf('\r\n'), line = input.slice(0, end); input = input.slice(end + 2);
        const [, tag, raw] = line.match(/^(\S+) (.*)$/) || [];
        if (!tag) continue;
        const command = raw.toUpperCase(); commands.push(command.replace(/^LOGIN .*/, 'LOGIN [synthetic]'));
        const done = () => socket.write(`${tag} OK completed\r\n`);
        if (command === 'CAPABILITY') { socket.write('* CAPABILITY IMAP4rev1\r\n'); done(); }
        else if (command.startsWith('LOGIN ')) done();
        else if (command.startsWith('LIST ') || command.startsWith('LSUB ')) {
          socket.write('* LIST () "/" "INBOX"\r\n'); done();
        } else if (command.startsWith('EXAMINE ')) {
          socket.write('* 1 EXISTS\r\n* FLAGS (\\Seen)\r\n* OK [UIDVALIDITY 10] valid\r\n'); done();
        } else if (command.startsWith('UID FETCH ')) {
          socket.write(`* 1 FETCH (UID 7 BODY[] {${source.length}}\r\n`);
          socket.write(source); socket.write(')\r\n'); done();
        } else if (command === 'LOGOUT') socket.end(`* BYE done\r\n${tag} OK logout\r\n`);
        else if (command === 'NOOP') done();
        else socket.write(`${tag} BAD unsupported synthetic command\r\n`);
      }
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const client = new ImapFlow({ host: '127.0.0.1', port: server.address().port, secure: false, doSTARTTLS: false,
    auth: { user: 'synthetic', pass: 'synthetic-password' }, logger: false, disableAutoIdle: true });
  client.on('error', () => {});
  t.after(async () => { client.close(); for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); });
  await client.connect(); await client.mailboxOpen('INBOX', { readOnly: true });
  assert.deepEqual(await messageSource(client, remote(), { timeoutMs: 1500 }), source);
  assert.equal(commands.filter(command => command.startsWith('UID FETCH ')).length, 2);
  assert.ok(commands.at(-1).includes('BODY.PEEK[]') && !commands.at(-1).includes('<'));
});
