import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { Repository } from '../Backend/src/database.js';
import { contactSuggestions } from '../Backend/src/contacts.js';
import { conversation } from '../Backend/src/threads.js';
import { syncAccount } from '../Backend/src/mail.js';

// Synthetic data only. Run with `node script/benchmark.mjs [message-count]`.
const count = Number(process.argv[2] || 2400);
assert.ok(Number.isSafeInteger(count) && count >= 8 && count <= 100000);
const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-benchmark-'));
const repo = new Repository(directory);
const measurements = {};
async function measure(name, run, repetitions = 5) {
  const samples = [];
  for (let index = 0; index < repetitions; index++) {
    const start = performance.now();
    await run();
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  measurements[name] = Number(samples[Math.floor(samples.length / 2)].toFixed(2));
}
try {
  const body = '项目资料与历史正文，仅用于本机性能测量。'.repeat(400);
  repo.transaction(() => {
    for (let index = 0; index < 4; index++) repo.put('account', {
      id: `a${index}`, name: '合成账户', email: `me${index}@example.com`, isDemo: false, folders: { inbox: 'INBOX' },
    });
    for (let index = 0; index < count; index++) repo.put('message', {
      id: `m${String(index).padStart(6, '0')}`, accountId: `a${index % 4}`, folder: 'inbox', remotePath: 'INBOX',
      uid: index + 1, uidValidity: '10', bodyVersion: 1, headersVersion: 1,
      sender: `联系人${index % 37}`, senderEmail: `contact${index % 37}@example.com`,
      to: `me${index % 4}@example.com`, cc: '', subject: `项目 ${index}`, body, html: `<p>${body}</p>`,
      date: '2026-10-23T00:00:00Z', unread: false, starred: false, category: '未分类', attachmentIds: [],
      messageId: `<m${index}@example.com>`, references: [`<root${index % 4}@example.com>`],
    });
  });
  const target = repo.list('message').filter(item => item.accountId === 'a0');
  await measure('indexFlushMs', () => repo.searchIndex.flush(), 1);
  assert.equal(repo.search('项目资料').length, count);
  const contactCount = Math.min(8, new Set(target.map(item => item.senderEmail)).size);
  await measure('contactsMs', () => assert.equal(contactSuggestions(repo, 'a0', '联系人').contacts.length, contactCount));
  await measure('conversationMs', () => assert.equal(conversation(repo, target[0].id).total, target.length));
  await measure('messagePageMs', () => assert.equal(repo.messagePage({ accountId: 'a0', folder: 'inbox' }).total, target.length));
  const client = { mailbox: { uidValidity: '10', exists: target.length },
    async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }]; },
    async getMailboxLock() { return { release() {} }; },
    async status() { return { messages: target.length, uidValidity: '10' }; },
    async search() { return target.map(item => item.uid); },
    async *fetch(range) { for (const item of target.filter(item => range.includes(item.uid))) yield { uid: item.uid, flags: new Set(['\\Seen']), size: 100 }; },
    async fetchOne() { throw new Error('完整缓存不应重复下载正文'); },
  };
  await measure('unchangedSyncMs', async () => {
    const result = await syncAccount(repo, repo.get('account', 'a0'), 'synthetic', { clientFactory: () => client });
    assert.equal(result.count, 0);
  }, 3);
  const dirtyAfterUnchangedSync = repo.searchIndex.status().pending;
  await measure('searchAfterSyncMs', () => assert.equal(repo.messagePage({ accountId: 'a0', query: '项目资料' }).total, target.length), 1);
  process.stdout.write(JSON.stringify({ node: process.versions.node, platform: process.platform, arch: process.arch,
    messages: count, accounts: 4, targetMessages: target.length,
    bodyCharacters: body.length, medianMilliseconds: measurements, dirtyAfterUnchangedSync }, null, 2) + '\n');
} finally {
  repo.close();
  await rm(directory, { recursive: true, force: true });
}
