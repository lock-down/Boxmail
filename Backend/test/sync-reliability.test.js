import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { ImapFlow } from 'imapflow';
import { Repository } from '../src/database.js';
import { syncAccount } from '../src/mail.js';
import { messageSource } from '../src/mail-sync.js';

const account = { id: 'a1', email: 'me@example.com', imapHost: 'imap.example.com' };
async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-sync-reliability-'));
  const repo = new Repository(directory);
  repo.put('account', account);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return repo;
}
function remote(boxes = { INBOX: [1, 2, 3], Sent: [1, 2] }) {
  const state = { boxes, downloads: [], ranges: [], connections: 0, closes: 0,
    invalidSearch: false, truncate: false, missingExists: false, zeroExists: false,
    failingFolder: null, slowFolder: null, hangFolder: null };
  const clientFactory = () => {
    let selected;
    return {
      mailbox: {},
      async connect() { state.connections++; },
      async logout() {},
      close() { state.closes++; },
      async list() { return Object.keys(state.boxes).map(path => ({ path,
        ...(path === 'Sent' ? { specialUse: '\\Sent' } : {}) })); },
      async getMailboxLock(folder, options) {
        assert.equal(options.readOnly, true);
        if (folder === state.failingFolder) throw Object.assign(new Error('private server response'), { code: 'ECONNRESET' });
        selected = folder;
        this.mailbox = { path: folder, uidValidity: '10',
          ...(state.missingExists ? {} : { exists: state.zeroExists ? 0 : state.boxes[folder].length }) };
        return { release() {} };
      },
      async status(folder) { return { messages: state.boxes[folder].length, uidValidity: '10' }; },
      async search() { return state.invalidSearch ? false : [...state.boxes[selected]]; },
      async *fetch(range, query, options) {
        assert.equal(options.uid, true);
        const uids = Array.isArray(range) ? range : String(range).split(',').map(Number);
        state.ranges.push(uids);
        for (const uid of uids) {
          if (state.truncate && uid === 2) continue;
          yield { uid, size: 200, flags: new Set(), internalDate: new Date('2026-10-23T00:00:00Z') };
        }
      },
      async fetchOne(uid) {
        if (selected === state.hangFolder) return new Promise(() => {});
        if (selected === state.slowFolder) await delay(15);
        state.downloads.push(`${selected}:${uid}`);
        return { source: Buffer.from(`From: sender@example.com\r\nSubject: Test\r\nMessage-ID: <${selected}-${uid}@example.com>\r\nContent-Type: text/plain\r\n\r\nBody`) };
      },
    };
  };
  return { state, options: { clientFactory } };
}

test('a successful but incomplete metadata response never removes cached mail', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: [1, 2, 3] });
  await syncAccount(repo, { ...account }, 'pw', options);
  const cached = repo.list('message');
  state.truncate = true;
  await assert.rejects(syncAccount(repo, { ...account }, 'pw', options), /清单.*不完整/);
  assert.deepEqual(repo.list('message'), cached);
  assert.deepEqual(repo.list('recovery'), []);
  assert.match(repo.list('sync')[0].lastError, /清单.*不完整/);
});

test('missing or misleading EXAMINE counts still discover mail through STATUS and UID SEARCH', async t => {
  for (const mode of ['missingExists', 'zeroExists']) {
    const repo = await fixture(t), { state, options } = remote({ INBOX: [1, 2, 3] });
    state[mode] = true;
    const result = await syncAccount(repo, { ...account }, 'pw', options);
    assert.equal(result.count, 3);
    assert.equal(repo.list('sync')[0].total, 3);
  }
});

test('a false SEARCH response is a failure rather than an empty mailbox', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: [1, 2, 3] });
  await syncAccount(repo, { ...account }, 'pw', options);
  state.invalidSearch = true;
  await assert.rejects(syncAccount(repo, { ...account }, 'pw', options), /清单/);
  assert.equal(repo.list('message').length, 3);
});

test('server-confirmed empty folders still reconcile genuine deletions', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: [1, 2, 3] });
  await syncAccount(repo, { ...account }, 'pw', options);
  state.boxes.INBOX = [];
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.equal(repo.list('message').length, 0);
  assert.equal(repo.list('sync')[0].total, 0);
  assert.equal(repo.list('sync')[0].beforeUID, undefined);
  assert.equal(repo.list('sync')[0].highestUID, undefined);
});

test('lightweight sync reconciliation retains bodies, translations and AI results in recovered mail', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: [1, 2] });
  await syncAccount(repo, { ...account }, 'pw', options);
  const original = repo.list('message')[0];
  const saved = { ...original, summary: { overview: '已保存总结' }, summaryHidden: true,
    translation: '已保存译文', translationHTML: '<p>已保存译文</p>', starred: true };
  repo.put('message', saved);
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.deepEqual(repo.get('message', saved.id), { ...saved, starred: false });
  state.boxes.INBOX = [];
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.deepEqual(repo.get('recovery', saved.id).original, { ...saved, starred: false });
  state.boxes.INBOX = [1, 2];
  await syncAccount(repo, { ...account }, 'pw', options);
  const restored = repo.get('message', saved.id);
  for (const key of ['body', 'html', 'summary', 'summaryHidden', 'translation', 'translationHTML'])
    assert.deepEqual(restored[key], saved[key]);
});

test('mail exposed again after a provider changes its collection range restores retained summaries', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: [], Sent: [1, 2] });
  await syncAccount(repo, { ...account }, 'pw', options);
  const original = repo.list('message')[0];
  repo.put('message', { ...original, summary: { overview: '保留的总结', points: ['原结果'] } });
  state.boxes.Sent = [];
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.equal(repo.list('message').length, 0);
  state.boxes.Sent = [1, 2];
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.equal(repo.list('message').length, 2);
  assert.equal(repo.get('message', original.id).summary.overview, '保留的总结');
  assert.equal(repo.list('recovery').length, 0);
});

test('one folder failing does not starve another folder and safe errors identify the failure', async t => {
  const repo = await fixture(t), { state, options } = remote();
  state.failingFolder = 'INBOX';
  await assert.rejects(syncAccount(repo, { ...account }, 'private-password', options), /收件箱.*ECONNRESET/);
  assert.equal(repo.list('message', { accountId: account.id }).filter(m => m.folder === 'sent').length, 2);
  assert.equal(state.connections, 2);
  const sync = repo.list('sync');
  assert.equal(sync.find(s => s.folder === 'inbox').status, 'failed');
  assert.equal(sync.find(s => s.folder === 'sent').status, 'completed');
  assert.equal(JSON.stringify(sync).includes('private'), false);
  assert.equal(repo.get('account', account.id).folders.sent, 'Sent');
});

test('large UID lists use bounded metadata requests while body batches keep resumable progress', async t => {
  const repo = await fixture(t), { state, options } = remote({ INBOX: Array.from({ length: 445 }, (_, i) => i + 1) });
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.ok(state.ranges.length >= 3);
  assert.ok(state.ranges.every(range => range.length <= 200));
  assert.equal(repo.list('message').length, 200);
  assert.equal(repo.list('sync')[0].remaining, 245);
  for (let i = 0; i < 2; i++) await syncAccount(repo, { ...account }, 'pw', options);
  assert.equal(repo.list('message').length, 445);
  assert.equal(new Set(state.downloads).size, 445);
  assert.equal(state.downloads.length, 445);
});

test('a slow folder yields after its time budget and lets the next folder synchronize', async t => {
  const repo = await fixture(t), { state, options } = remote();
  state.slowFolder = 'INBOX';
  await syncAccount(repo, { ...account }, 'pw', { ...options, downloadBudgetMs: 5 });
  assert.equal(repo.list('message').filter(m => m.folder === 'inbox').length, 1);
  assert.equal(repo.list('message').filter(m => m.folder === 'sent').length, 2);
  assert.equal(repo.list('sync').find(s => s.folder === 'inbox').status, 'partial');
  state.slowFolder = null;
  await syncAccount(repo, { ...account }, 'pw', options);
  assert.equal(repo.list('message').length, 5);
  assert.equal(state.downloads.length, 5);
});

test('a stuck IMAP operation has a deadline, preserves completed mail, and continues other folders', async t => {
  const repo = await fixture(t), { state, options } = remote();
  state.hangFolder = 'INBOX';
  await assert.rejects(syncAccount(repo, { ...account }, 'pw', { ...options, operationTimeoutMs: 30 }), /超时/);
  assert.ok(state.closes >= 1);
  assert.equal(repo.list('message').filter(m => m.folder === 'sent').length, 2);
  assert.equal(repo.list('sync').find(s => s.folder === 'inbox').remaining, 3);
});

test('large MIME sources use bounded partial FETCH requests and preserve every original byte', async () => {
  const original = Buffer.alloc(1024 * 1024 + 37, 97), calls = [];
  const client = {
    async fetchOne(uid, query, options) {
      assert.equal(uid, 7); assert.equal(options.uid, true);
      const { start, maxLength } = query.source;
      calls.push({ start, maxLength });
      return { source: original.subarray(start, start + maxLength) };
    }, close() {},
  };
  const downloaded = await messageSource(client, { uid: 7, size: original.length }, {});
  assert.deepEqual(downloaded, original);
  assert.equal(calls.length, 5);
  assert.ok(calls.every(call => call.maxLength <= 256 * 1024));
  assert.deepEqual(calls.at(-1), { start: 1024 * 1024, maxLength: 37 });
});

test('an interrupted partial MIME response never turns a truncated body into completed mail', async () => {
  let calls = 0;
  await assert.rejects(messageSource({
    async fetchOne() { return ++calls === 1 ? { source: Buffer.alloc(256 * 1024) } : false; }, close() {},
  }, { uid: 7, size: 2 * 1024 * 1024 }, {}), /未完整返回邮件正文/);
});

test('real IMAP commands synchronize both folders despite missing and zero EXAMINE counts', { timeout: 10000 }, async t => {
  const repo = await fixture(t);
  const sockets = new Set(), commands = [];
  const source = Buffer.from('From: sender@example.com\r\nTo: me@example.com\r\nSubject: Fixture\r\nContent-Type: text/plain\r\n\r\nBody');
  const server = net.createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    let input = '', selected = 'INBOX';
    socket.write('* OK [CAPABILITY IMAP4rev1] synthetic server\r\n');
    socket.on('data', data => {
      input += data.toString();
      while (input.includes('\r\n')) {
        const end = input.indexOf('\r\n'), line = input.slice(0, end);
        input = input.slice(end + 2);
        const [, tag, raw] = line.match(/^(\S+) (.*)$/) || [];
        if (!tag) continue;
        const command = raw.toUpperCase();
        commands.push(command.replace(/^LOGIN .*/, 'LOGIN [synthetic]'));
        const done = () => socket.write(`${tag} OK completed\r\n`);
        if (command === 'CAPABILITY') { socket.write('* CAPABILITY IMAP4rev1\r\n'); done(); }
        else if (command.startsWith('LOGIN ')) done();
        else if (command.startsWith('LIST ') || command.startsWith('LSUB ')) {
          socket.write('* LIST () "/" "INBOX"\r\n* LIST (\\Sent) "/" "Sent"\r\n'); done();
        } else if (command.startsWith('EXAMINE ')) {
          selected = command.includes('SENT') ? 'Sent' : 'INBOX';
          socket.write(`* FLAGS (\\Seen)\r\n* OK [UIDVALIDITY 10] valid\r\n${selected === 'Sent' ? '* 0 EXISTS\r\n' : ''}${tag} OK [READ-ONLY] selected\r\n`);
        } else if (command.startsWith('STATUS ')) {
          socket.write(`* STATUS "${selected}" (MESSAGES 1 UIDVALIDITY 10)\r\n`); done();
        } else if (command === 'UID SEARCH ALL') { socket.write('* SEARCH 7\r\n'); done(); }
        else if (command.startsWith('UID FETCH ')) {
          if (command.includes('BODY.PEEK')) {
            socket.write(`* 1 FETCH (UID 7 BODY[] {${source.length}}\r\n`);
            socket.write(source); socket.write(')\r\n');
          } else socket.write(`* 1 FETCH (UID 7 FLAGS () RFC822.SIZE ${source.length} INTERNALDATE "23-Oct-2026 00:00:00 +0000")\r\n`);
          done();
        } else if (command === 'LOGOUT') socket.end(`* BYE done\r\n${tag} OK logout\r\n`);
        else if (command === 'NOOP') done();
        else socket.write(`${tag} BAD unsupported synthetic command\r\n`);
      }
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); });
  await syncAccount(repo, { ...account }, 'synthetic-password', {
    operationTimeoutMs: 1500,
    clientFactory: () => {
      const client = new ImapFlow({ host: '127.0.0.1', port: server.address().port,
        secure: false, doSTARTTLS: false, auth: { user: 'synthetic', pass: 'synthetic-password' },
        logger: false, disableAutoIdle: true });
      client.on('error', () => {});
      return client;
    },
  });
  assert.deepEqual(repo.list('message').map(m => m.folder).sort(), ['inbox', 'sent']);
  assert.equal(commands.filter(c => c === 'UID SEARCH ALL').length, 2);
  assert.equal(commands.some(c => c.startsWith('FETCH ')), false);
  assert.ok(commands.filter(c => c.includes('BODY.PEEK')).length === 2);
});
