import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { syncAccount } from '../src/mail.js';

function mailbox(onList) {
  return {
    mailbox: {},
    async connect() {},
    async logout() {},
    close() {},
    async list() {
      onList();
      return [{ path: 'INBOX' }];
    },
    async getMailboxLock() {
      this.mailbox = { uidValidity: '10', exists: 1 };
      return { release() {} };
    },
    async status() { return { messages: 1, uidValidity: '10' }; },
    async search() { return [1]; },
    async *fetch() {
      yield {
        uid: 1,
        size: 200,
        flags: new Set(),
        internalDate: new Date('2026-10-20T00:00:00Z'),
      };
    },
    async fetchOne() {
      return {
        source: Buffer.from(
          'From: 发件人 <sender@example.com>\r\nTo: me@example.com\r\nSubject: 同步邮件\r\nMessage-ID: <uid-1@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n正文',
        ),
      };
    },
  };
}

test('account settings saved during a sync survive while folders and lastSync are merged', async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-sync-account-'));
  const repo = new Repository(directory);
  t.after(async () => {
    repo.close();
    await rm(directory, { recursive: true, force: true });
  });
  repo.put('account', {
    id: 'a1',
    name: '旧名字',
    email: 'me@example.com',
    username: 'me@example.com',
    isDemo: false,
    folders: {},
  });
  // The server captured this snapshot before the sync began, like POST /sync does.
  const snapshot = repo.get('account', 'a1');
  const client = mailbox(() => {
    // The user saves account settings from the settings page while the sync is running.
    repo.put('account', {
      ...repo.get('account', 'a1'),
      name: '同步期间保存的新名字',
      signature: '同步期间保存的新签名',
    });
  });
  const result = await syncAccount(repo, snapshot, 'pw', {
    clientFactory: () => client,
  });
  assert.equal(result.ok, true);
  assert.equal(result.count, 1);
  const account = repo.get('account', 'a1');
  assert.equal(account.name, '同步期间保存的新名字');
  assert.equal(account.signature, '同步期间保存的新签名');
  assert.equal(account.email, 'me@example.com');
  assert.equal(account.folders.inbox, 'INBOX');
  assert.ok(account.lastSync);
  assert.equal(repo.list('message').length, 1);
  assert.equal(repo.events()[0].type, 'sync');
});
