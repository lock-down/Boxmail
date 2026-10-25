import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { applyMailMutations } from '../src/mail-folders.js';
import { syncAccount } from '../src/mail.js';

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-mutation-timeout-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  const account = { id: 'a', email: 'reader@example.test', folders: { inbox: 'INBOX', archive: 'Archive' } };
  const message = { id: 'm', accountId: 'a', uid: 1, uidValidity: '10', remotePath: 'INBOX', folder: 'archive' };
  const mutation = { id: 'mutation', accountId: 'a', messageId: 'm', path: 'INBOX',
    uid: 1, uidValidity: '10', target: 'archive', revision: 'original' };
  repo.put('account', account); repo.put('message', message); repo.put('mutation', mutation);
  let closed = 0, released = 0;
  const client = { mailbox: { uidValidity: '10' },
    close() { closed++; }, async connect() {}, async logout() {},
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock() { return { release() { released++; } }; },
    async messageMove() { return { uidMap: new Map([[1, 2]]), uidValidity: '20' }; },
  };
  return { repo, account, client, message, mutation, closed: () => closed, released: () => released };
}

for (const command of ['getMailboxLock', 'messageMove', 'messageFlagsAdd', 'messageFlagsRemove', 'search', 'mailboxCreate']) {
  test(`a stalled ${command} times out without discarding the queued local change`, { timeout: 3000 }, async t => {
    const { repo, account, client, message, mutation, closed, released } = await fixture(t);
    const queued = { ...mutation };
    if (command.startsWith('messageFlags')) {
      delete queued.target;
      queued.flag = '\\Seen'; queued.value = command.endsWith('Add');
    }
    if (command === 'search') { delete queued.uid; queued.rfcMessageId = '<local@example.test>'; }
    if (command === 'mailboxCreate') delete account.folders.archive;
    repo.put('mutation', queued);
    client[command] = () => new Promise(() => {});
    await assert.rejects(applyMailMutations(repo, account, client, { timeoutMs: 15 }), /超时/);
    assert.deepEqual(repo.get('message', 'm'), message);
    assert.deepEqual(repo.get('mutation', 'mutation'), queued);
    assert.deepEqual(repo.list('relocation'), []);
    assert.equal(closed(), 1);
    assert.equal(released(), command === 'getMailboxLock' ? 0 : 1);
  });
}

test('sync cancellation interrupts a stalled pending move and keeps it recoverable', { timeout: 3000 }, async t => {
  const { repo, account, client, mutation, closed } = await fixture(t);
  const controller = new AbortController();
  client.messageMove = () => {
    queueMicrotask(() => controller.abort(new Error('cancelled by user')));
    return new Promise(() => {});
  };
  await assert.rejects(syncAccount(repo, account, 'synthetic', {
    clientFactory: () => client, signal: controller.signal, operationTimeoutMs: 1000,
  }), /cancelled by user/);
  assert.deepEqual(repo.get('mutation', 'mutation'), mutation);
  assert.ok(closed() >= 1);
});
