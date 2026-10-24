import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { ImapFlow } from 'imapflow';
import { Repository } from '../src/database.js';
import { syncAccount } from '../src/mail.js';
import { mailboxMetadata, messageSource } from '../src/mail-sync.js';

const account = { id: 'a1', email: 'me@example.test', imapHost: 'imap.example.test' };
const receivedAt = new Date('2026-10-20T03:00:00Z');
async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-inventory-'));
  const repo = new Repository(directory);
  repo.put('account', account);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return repo;
}
function mailbox(count = 205) {
  const state = { uids: Array.from({ length: count }, (_, i) => i + 1), queries: [],
    sources: [], headers: [], closes: 0, rows: (page, query) => page.map(uid =>
      ({ uid, flags: new Set(), size: 200 })) };
  const client = {
    mailbox: { path: 'INBOX', uidValidity: '10', exists: count },
    async connect() {}, async logout() {}, close() { state.closes++; },
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock() { return { release() {} }; },
    async status() { return { messages: state.uids.length, uidValidity: '10' }; },
    async search() { return [...state.uids]; },
    async *fetch(page, query, options) {
      assert.equal(options.uid, true);
      state.queries.push({ page: [...page], query });
      yield* await state.rows(page, query);
    },
    async fetchOne(uid, query, options) {
      assert.equal(options.uid, true);
      if (query.source) {
        state.sources.push(uid);
        return { uid, internalDate: receivedAt, source: Buffer.from(`From: Sender <sender@example.test>\r\n`
          + `Subject: Mail ${uid}\r\nMessage-ID: <${uid}@example.test>\r\nContent-Type: text/plain\r\n\r\nBody ${uid}`) };
      }
      state.headers.push({ uid, query });
      return { uid, internalDate: receivedAt, envelope: { subject: 'Large original',
        messageId: `<${uid}@example.test>`, from: [{ address: 'sender@example.test' }],
        to: [{ address: account.email }] } };
    },
  };
  return { state, client, options: { clientFactory: () => client } };
}

test('servers truncating ENVELOPE or INTERNALDATE batches still backfill every message', async t => {
  const repo = await fixture(t), { state, options } = mailbox(230);
  const rows = state.rows;
  state.rows = (page, query) => rows(query.envelope || query.internalDate ? page.slice(0, 100) : page, query);
  await syncAccount(repo, { ...account }, 'synthetic', options);
  assert.equal(repo.list('message').length, 200);
  assert.equal(repo.list('sync')[0].remaining, 30);
  await syncAccount(repo, { ...account }, 'synthetic', options);
  assert.equal(repo.list('message').length, 230);
  assert.equal(new Set(state.sources).size, 230);
  assert.equal(state.sources.length, 230);
  assert.ok(state.queries.every(({ query }) => !query.envelope && !query.internalDate));
  assert.ok(repo.list('message').every(message => message.date === receivedAt.toISOString()));
});

test('a UID consistently omitted from bulk FETCH is recovered by requesting only the missing UID', async () => {
  const { client, state } = mailbox();
  const rows = state.rows;
  state.rows = (page, query) => rows(page.length > 1 ? page.filter(uid => uid !== 199) : page, query);
  let inventory;
  const result = await mailboxMetadata(client, 'INBOX', { onInventory: value => { inventory = { ...inventory, ...value }; } });
  assert.equal(result.fetched.length, 205);
  assert.equal(new Set(result.fetched.map(remote => remote.uid)).size, 205);
  assert.ok(state.queries.some(({ page }) => page.length === 1 && page[0] === 199));
  assert.equal(inventory.metadataRecoveredCount, 1);
  assert.equal(inventory.metadataMissingCount, 0);
  assert.deepEqual(inventory.metadataMissingUIDs, []);
});

test('lightweight responses capped by a server recover through progressively smaller missing-UID requests', async () => {
  const { client, state } = mailbox(445);
  const rows = state.rows;
  state.rows = (page, query) => rows(page.length > 10 ? page.slice(0, Math.min(100, Math.floor(page.length / 2))) : page, query);
  let inventory;
  const result = await mailboxMetadata(client, 'INBOX', { onInventory: value => { inventory = { ...inventory, ...value }; } });
  assert.equal(result.fetched.length, 445);
  assert.equal(new Set(result.fetched.map(remote => remote.uid)).size, 445);
  assert.ok(state.queries.every(({ page }) => page.length <= 200));
  assert.ok(state.queries.some(({ page }) => page.length <= 10));
  assert.ok(inventory.metadataRetryRequests > 0);
  assert.ok(inventory.metadataRecoveredCount > 100);
  assert.equal(inventory.metadataCount, 445);
});

test('permanently missing metadata keeps cached mail and records bounded recovery diagnostics', async t => {
  const repo = await fixture(t), { state, options } = mailbox(3);
  await syncAccount(repo, { ...account }, 'synthetic', options);
  const original = repo.list('message');
  state.queries = [];
  const rows = state.rows;
  state.rows = (page, query) => rows(page.filter(uid => uid !== 2), query);
  await assert.rejects(syncAccount(repo, { ...account }, 'synthetic', options), /清单.*不完整/);
  assert.deepEqual(repo.list('message'), original);
  assert.deepEqual(repo.list('recovery'), []);
  assert.ok(state.queries.length > 1 && state.queries.length <= 5);
  const { inventory, status } = repo.list('sync')[0];
  assert.equal(status, 'failed');
  assert.equal(inventory.metadataCount, 2);
  assert.equal(inventory.metadataMissingCount, 1);
  assert.deepEqual(inventory.metadataMissingUIDs, [2]);
  assert.ok(inventory.metadataRetryRequests > 0);
});

test('retrying metadata retains duplicate, unexpected UID, flag and size validation', async () => {
  const invalid = [
    rows => [...rows, rows[0]],
    rows => [...rows, { ...rows[0], uid: 99 }],
    rows => rows.map(row => ({ ...row, flags: [] })),
    rows => rows.map(row => ({ ...row, size: -1 })),
  ];
  for (const corrupt of invalid) {
    const { client, state } = mailbox(2);
    const rows = state.rows;
    state.rows = (page, query) => state.queries.length === 1
      ? rows(page.filter(uid => uid !== 2), query) : corrupt(rows(page, query));
    await assert.rejects(mailboxMetadata(client, 'INBOX', {}), /清单.*不完整/);
    assert.equal(state.queries.length, 2);
  }
});

test('an empty metadata server exhausts a finite budget and bounds the persisted UID sample', async () => {
  const { client, state } = mailbox();
  state.rows = () => [];
  let inventory;
  await assert.rejects(mailboxMetadata(client, 'INBOX', {
    onInventory: value => { inventory = { ...inventory, ...value }; },
  }), /清单.*不完整/);
  assert.equal(state.queries.length, 25);
  assert.equal(inventory.metadataRetryRequests, 24);
  assert.equal(inventory.metadataCount, 0);
  assert.equal(inventory.metadataMissingCount, 200);
  assert.equal(inventory.metadataMissingUIDs.length, 20);
});

test('cancelling after a truncated response prevents further recovery requests', async () => {
  const { client, state } = mailbox(3), controller = new AbortController();
  const rows = state.rows;
  state.rows = (page, query) => rows(page.filter(uid => uid !== 2), query);
  await assert.rejects(mailboxMetadata(client, 'INBOX', { signal: controller.signal,
    onInventory: value => { if (value.metadataMissingCount) controller.abort(new Error('cancel recovery')); } }), /cancel recovery/);
  assert.equal(state.queries.length, 1);
});

test('each recovery request has an independent deadline and cannot hang synchronization', async () => {
  const { client, state } = mailbox(3);
  const rows = state.rows;
  state.rows = (page, query) => state.queries.length === 1
    ? rows(page.filter(uid => uid !== 2), query) : new Promise(() => {});
  await assert.rejects(mailboxMetadata(client, 'INBOX', { timeoutMs: 30 }), /超时/);
  assert.equal(state.queries.length, 2);
  assert.ok(state.closes > 0);
});

test('single-message source fetch preserves the server date without a heavy inventory request', async () => {
  const remote = { uid: 7, size: 100 };
  let query;
  const source = Buffer.from('Subject: No Date header\r\n\r\nBody');
  const result = await messageSource({ async fetchOne(uid, value) { query = value; return { uid, source, internalDate: receivedAt }; } }, remote, {});
  assert.deepEqual(result, source);
  assert.equal(query.internalDate, true);
  assert.equal(remote.internalDate.toISOString(), receivedAt.toISOString());
});

test('partial source downloads retain INTERNALDATE from the first chunk only', async () => {
  const source = Buffer.alloc(1024 * 1024 + 1, 97), remote = { uid: 7, size: source.length }, queries = [];
  const result = await messageSource({ async fetchOne(uid, query) {
    queries.push(query);
    const { start, maxLength } = query.source;
    return { uid, source: source.subarray(start, start + maxLength), ...(start === 0 ? { internalDate: receivedAt } : {}) };
  } }, remote, {});
  assert.deepEqual(result, source);
  assert.equal(queries[0].internalDate, true);
  assert.ok(queries.slice(1).every(query => !query.internalDate));
  assert.equal(remote.internalDate.toISOString(), receivedAt.toISOString());
});

test('oversized mail fetches its envelope individually and keeps sender, subject and server date', async t => {
  const repo = await fixture(t), { state, options } = mailbox(1);
  const rows = state.rows;
  state.rows = (page, query) => rows(page, query).map(row => ({ ...row, size: 26 * 1024 * 1024 }));
  await syncAccount(repo, { ...account }, 'synthetic', options);
  const message = repo.list('message')[0];
  assert.equal(message.subject, 'Large original');
  assert.equal(message.senderEmail, 'sender@example.test');
  assert.equal(message.date, receivedAt.toISOString());
  assert.equal(message.oversized, true);
  assert.deepEqual(state.sources, []);
  assert.equal(state.headers.length, 1);
  assert.equal(state.headers[0].uid, 1);
  assert.equal(state.headers[0].query.envelope, true);
});

test('an unavailable oversized envelope preserves completed downloads and can resume later', async t => {
  const repo = await fixture(t), { client, state, options } = mailbox(2);
  const rows = state.rows, fetchOne = client.fetchOne;
  state.rows = (page, query) => rows(page, query).map(row => row.uid === 1 ? { ...row, size: 26 * 1024 * 1024 } : row);
  client.fetchOne = (uid, query, options) => query.envelope ? false : fetchOne(uid, query, options);
  await assert.rejects(syncAccount(repo, { ...account }, 'synthetic', options), /未完整返回邮件头/);
  assert.deepEqual(repo.list('message').map(message => message.uid), [2]);
  assert.equal(repo.list('sync')[0].remaining, 1);
  client.fetchOne = fetchOne;
  await syncAccount(repo, { ...account }, 'synthetic', options);
  assert.equal(repo.list('message').length, 2);
  assert.equal(repo.list('sync')[0].status, 'completed');
  assert.deepEqual(state.sources, [2]);
});

test('real ImapFlow handles capped heavy metadata and an omitted lightweight UID safely', { timeout: 10000 }, async t => {
  const repo = await fixture(t), sockets = new Set(), metadataCommands = [];
  const allUIDs = Array.from({ length: 205 }, (_, i) => i + 1);
  const server = net.createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    let input = '';
    socket.write('* OK [CAPABILITY IMAP4rev1] synthetic server\r\n');
    socket.on('data', data => {
      input += data.toString();
      while (input.includes('\r\n')) {
        const end = input.indexOf('\r\n'), line = input.slice(0, end);
        input = input.slice(end + 2);
        const [, tag, raw] = line.match(/^(\S+) (.*)$/) || [];
        if (!tag) continue;
        const command = raw.toUpperCase(), done = () => socket.write(`${tag} OK completed\r\n`);
        if (command === 'CAPABILITY') { socket.write('* CAPABILITY IMAP4rev1\r\n'); done(); }
        else if (command.startsWith('LOGIN ')) done();
        else if (command.startsWith('LIST ') || command.startsWith('LSUB ')) { socket.write('* LIST () "/" "INBOX"\r\n'); done(); }
        else if (command.startsWith('EXAMINE ')) { socket.write('* 205 EXISTS\r\n* FLAGS (\\Seen)\r\n* OK [UIDVALIDITY 10] valid\r\n'); done(); }
        else if (command.startsWith('STATUS ')) { socket.write('* STATUS "INBOX" (MESSAGES 205 UIDVALIDITY 10)\r\n'); done(); }
        else if (command === 'UID SEARCH ALL') { socket.write(`* SEARCH ${allUIDs.join(' ')}\r\n`); done(); }
        else if (command.startsWith('UID FETCH ')) {
          const range = command.split(' ')[2], requested = new Set();
          for (const part of range.split(',')) {
            const [first, last = first] = part.split(':').map(Number);
            for (let uid = first; uid <= last; uid++) requested.add(uid);
          }
          let page = allUIDs.filter(uid => requested.has(uid));
          if (command.includes('BODY.PEEK')) {
            for (const uid of page) {
              const source = Buffer.from(`From: Sender <sender@example.test>\r\nSubject: Mail ${uid}\r\nMessage-ID: <${uid}@example.test>\r\n\r\nBody`);
              socket.write(`* ${uid} FETCH (UID ${uid} INTERNALDATE "20-Oct-2026 03:00:00 +0000" BODY[] {${source.length}}\r\n`);
              socket.write(source); socket.write(')\r\n');
            }
          } else {
            metadataCommands.push(command);
            if (command.includes('ENVELOPE') || command.includes('INTERNALDATE')) page = page.slice(0, 100);
            else if (page.length > 1) page = page.filter(uid => uid !== 199);
            for (const uid of page) socket.write(`* ${uid} FETCH (UID ${uid} FLAGS () RFC822.SIZE 200)\r\n`);
          }
          done();
        } else if (command === 'LOGOUT') socket.end(`* BYE done\r\n${tag} OK logout\r\n`);
        else if (command === 'NOOP') done();
        else socket.write(`${tag} BAD unsupported synthetic command\r\n`);
      }
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); });
  await syncAccount(repo, { ...account }, 'synthetic', { batchSize: 2, operationTimeoutMs: 1500,
    clientFactory: () => {
      const client = new ImapFlow({ host: '127.0.0.1', port: server.address().port,
        secure: false, doSTARTTLS: false, auth: { user: 'synthetic', pass: 'synthetic' }, logger: false, disableAutoIdle: true });
      client.on('error', () => {});
      return client;
    } });
  assert.equal(repo.list('sync')[0].total, 205);
  assert.equal(repo.list('sync')[0].remaining, 203);
  assert.equal(repo.list('message').length, 2);
  assert.ok(metadataCommands.every(command => !/ENVELOPE|INTERNALDATE/.test(command)));
  assert.ok(metadataCommands.some(command => /^UID FETCH 199 /.test(command)));
});
