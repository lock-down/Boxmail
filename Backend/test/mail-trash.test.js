import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { syncAccount, updateMessage, restoreMessage, unarchiveMessage, emptyTrash } from '../src/mail.js';
import { archiveRestoreFolder, trashRestoreFolder } from '../src/mail-folders.js';
import { saveAttachment } from '../src/attachments.js';
import { startServer } from '../src/server.js';

const account = { id: 'a1', email: 'me@example.com', isDemo: false };
const base = { id: 'm1', accountId: 'a1', folder: 'inbox', sender: 'Sender',
  senderEmail: 'sender@example.com', to: 'me@example.com', cc: '', subject: '项目',
  body: '正文', preview: '正文', date: '2026-10-20T00:00:00Z', category: '未分类',
  unread: false, starred: false, attachmentIds: [], summary: null };
const token = 'boxmail-trash-test-session-0123456789';
async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-trash-'));
  const repo = new Repository(directory);
  repo.put('account', account);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return repo;
}
function mailbox() {
  const folders = new Map([
    ['INBOX', undefined], ['Sent', '\\Sent'], ['Trash', '\\Trash'], ['Archive', '\\Archive'],
  ].map(([path, specialUse], index) => [path, { path, specialUse,
    validity: String(10 + index), nextUID: 1, messages: new Map() }]));
  const calls = [];
  let selected;
  const add = (folder, messageId = '<mail@example.com>') => {
    const box = folders.get(folder), uid = box.nextUID++;
    box.messages.set(uid, { source: Buffer.from(`From: Me <me@example.com>\r\nTo: to@example.com\r\nSubject: Project\r\n${messageId ? `Message-ID: ${messageId}\r\n` : ''}Content-Type: text/plain; charset=utf-8\r\n\r\nBody`), flags: new Set(['\\Seen']) });
    return uid;
  };
  const client = {
    mailbox: {}, failDelete: false, failConnect: false,
    async connect() { if (this.failConnect) throw new Error('offline'); },
    async logout() { calls.push(['logout']); }, close() {},
    async list() { return [...folders.values()].map(({ path, specialUse }) => ({ path, specialUse })); },
    async getMailboxLock(path) {
      selected = folders.get(path);
      assert.ok(selected, `unknown mailbox ${path}`);
      this.mailbox = { uidValidity: selected.validity, exists: selected.messages.size };
      return { release() {} };
    },
    async status() { return { messages: selected.messages.size, uidValidity: selected.validity }; },
    async *fetch() {
      for (const [uid, item] of selected.messages)
        yield { uid, flags: item.flags, size: item.source.length };
    },
    async fetchOne(uid) { return selected.messages.get(uid); },
    async search(query, options) {
      assert.equal(options.uid, true);
      if (query.all) return [...selected.messages.keys()];
      const id = query.header['Message-ID'];
      return [...selected.messages].filter(([, item]) => item.source.includes(`Message-ID: ${id}\r\n`)).map(([uid]) => uid);
    },
    async messageMove(uid, target, options) {
      assert.equal(options.uid, true);
      assert.notEqual(selected.path, target, 'never MOVE into the same mailbox');
      const item = selected.messages.get(uid), box = folders.get(target), newUID = box.nextUID++;
      assert.ok(item);
      calls.push(['move', selected.path, target]);
      selected.messages.delete(uid); box.messages.set(newUID, item);
      return { destination: target, uidValidity: BigInt(box.validity), uidMap: new Map([[uid, newUID]]) };
    },
    async mailboxCreate(path) {
      calls.push(['create', path]);
      folders.set(path, { path, validity: '90', nextUID: 1, messages: new Map() });
    },
    async messageDelete(range) {
      calls.push(['delete', selected.path, range]);
      if (this.failDelete) return false;
      selected.messages.clear(); return true;
    },
    async messageFlagsAdd(uid, flags) { for (const flag of flags) selected.messages.get(uid).flags.add(flag); },
    async messageFlagsRemove(uid, flags) { for (const flag of flags) selected.messages.get(uid).flags.delete(flag); },
  };
  return { folders, calls, client, add, options: { clientFactory: () => client } };
}

test('deletions remember every source folder across restarts and repeated deletes', async t => {
  const repo = await fixture(t);
  for (const folder of ['inbox', 'sent', 'archive', 'drafts', 'spam']) {
    repo.put('message', { ...base, id: folder, folder });
    updateMessage(repo, folder, { folder: 'trash' });
    updateMessage(repo, folder, { folder: 'trash' });
    const reopened = new Repository(repo.directory);
    assert.equal(reopened.get('message', folder).deletedFromFolder, folder);
    reopened.close();
    assert.equal(restoreMessage(repo, folder).folder, folder);
    assert.equal(repo.get('message', folder).deletedFromFolder, undefined);
  }
  repo.put('message', base);
  updateMessage(repo, base.id, { folder: 'trash' }); restoreMessage(repo, base.id);
  updateMessage(repo, base.id, { folder: 'archive' });
  updateMessage(repo, base.id, { folder: 'trash' });
  assert.equal(restoreMessage(repo, base.id).folder, 'archive');
  assert.throws(() => restoreMessage(repo, base.id), /只能恢复/);
  assert.throws(() => updateMessage(repo, base.id, { folder: 'not-a-folder' }), /文件夹无效/);
});

test('legacy trash uses its known source before the sender fallback', () => {
  const a = { ...account, folders: { sent: 'Sent', archive: 'Archive' }, aliases: ['alias@example.com'] };
  assert.equal(trashRestoreFolder({ ...base, folder: 'trash', remotePath: 'Sent' }, a), 'sent');
  assert.equal(trashRestoreFolder({ ...base, folder: 'trash', remotePath: 'Archive', senderEmail: a.email }, a), 'archive');
  assert.equal(trashRestoreFolder({ ...base, folder: 'trash', remotePath: 'Trash', senderEmail: 'ME@example.com' }, a), 'sent');
  assert.equal(trashRestoreFolder({ ...base, folder: 'trash', senderEmail: 'alias@example.com' }, a), 'sent');
  assert.equal(trashRestoreFolder({ ...base, folder: 'trash' }, a), 'inbox');
});

test('unarchive restores each original mailbox after restart and repeated archiving', async t => {
  const repo = await fixture(t);
  for (const folder of ['inbox', 'sent', 'drafts', 'spam']) {
    repo.put('message', { ...base, id: folder, folder });
    updateMessage(repo, folder, { folder: 'archive' });
    updateMessage(repo, folder, { folder: 'archive' });
    const reopened = new Repository(repo.directory);
    assert.equal(reopened.get('message', folder).archivedFromFolder, folder);
    reopened.close();
    assert.equal(unarchiveMessage(repo, folder).folder, folder);
    assert.equal(repo.get('message', folder).archivedFromFolder, undefined);
  }
  assert.throws(() => unarchiveMessage(repo, 'inbox'), /只能取消已归档/);
  assert.equal(archiveRestoreFolder({ ...base, folder: 'archive', remotePath: 'Sent' },
    { ...account, folders: { sent: 'Sent' } }), 'sent');
  assert.equal(archiveRestoreFolder({ ...base, folder: 'archive', remotePath: 'Boxmail Archive' }, account), 'inbox');
});

test('archive origin survives sync, UID reset, deletion, and restoration before unarchiving', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('Sent');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  let message = repo.list('message')[0];
  updateMessage(repo, message.id, { folder: 'archive' });
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.archivedFromFolder, 'sent');
  remote.folders.get('Archive').validity = '121';
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.archivedFromFolder, 'sent');
  updateMessage(repo, message.id, { folder: 'trash' });
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.deletedFromFolder, 'archive');
  assert.equal(message.archivedFromFolder, 'sent');
  restoreMessage(repo, message.id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.folder, 'archive'); assert.equal(message.archivedFromFolder, 'sent');
  unarchiveMessage(repo, message.id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.folder, 'sent'); assert.equal(message.archivedFromFolder, undefined);
});

test('unarchive before sync cancels the pending archive move', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('INBOX');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  const message = repo.list('message')[0];
  updateMessage(repo, message.id, { folder: 'archive' }); unarchiveMessage(repo, message.id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message')[0].folder, 'inbox');
  assert.equal(remote.calls.some(c => c[0] === 'move'), false);
  assert.equal(repo.list('mutation').length, 0);
});

test('sent deletion and restoration survive IMAP moves, UID changes and UIDVALIDITY reset', async t => {
  const repo = await fixture(t), remote = mailbox();
  remote.add('Sent');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  let message = repo.list('message')[0];
  repo.put('message', { ...message, summary: { points: ['保留总结'], todos: [], keyInfo: [] }, translation: '译文' });
  updateMessage(repo, message.id, { folder: 'trash' });
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.folder, 'trash'); assert.equal(message.deletedFromFolder, 'sent');
  remote.folders.get('Trash').validity = '99';
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.deletedFromFolder, 'sent');
  restoreMessage(repo, message.id);
  assert.equal(repo.get('mutation', `${message.id}:folder`).target, 'sent');
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  message = repo.list('message')[0];
  assert.equal(message.folder, 'sent'); assert.equal(message.deletedFromFolder, undefined);
  assert.deepEqual(message.summary.points, ['保留总结']); assert.equal(message.translation, '译文');
  assert.equal(repo.list('mutation').length, 0);
  assert.deepEqual(remote.calls.filter(c => c[0] === 'move'), [['move', 'Sent', 'Trash'], ['move', 'Trash', 'Sent']]);
});

test('UIDPLUS relocation retains the deletion source even without a Message-ID', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('Archive', '');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  updateMessage(repo, repo.list('message')[0].id, { folder: 'trash' });
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message')[0].deletedFromFolder, 'archive');
});

test('received and sent copies sharing a Message-ID retain their own restore folders', async t => {
  const repo = await fixture(t), remote = mailbox();
  remote.add('INBOX'); remote.add('Sent');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  const original = repo.list('message');
  for (const message of original) {
    repo.put('message', { ...message, category: message.folder });
    updateMessage(repo, message.id, { folder: 'trash' });
  }
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  const trashed = repo.list('message');
  assert.equal(trashed.length, 2);
  for (const message of trashed) {
    assert.equal(message.deletedFromFolder, message.category);
    restoreMessage(repo, message.id);
  }
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.deepEqual(repo.list('message').map(m => m.folder).sort(), ['inbox', 'sent']);
  for (const message of repo.list('message')) assert.equal(message.folder, message.category);
});

test('restore before sync cancels the pending move without moving a message into itself', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('Sent');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  const message = repo.list('message')[0];
  updateMessage(repo, message.id, { folder: 'trash' }); restoreMessage(repo, message.id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message')[0].folder, 'sent');
  assert.equal(remote.calls.some(c => c[0] === 'move'), false);
  assert.equal(repo.list('mutation').length, 0);
});

test('locally sent copies can be deleted, synced, and restored before their first download', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('Sent');
  repo.put('message', { ...base, id: 'sent-local', folder: 'sent', senderEmail: account.email, messageId: '<mail@example.com>' });
  updateMessage(repo, 'sent-local', { folder: 'trash' });
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  assert.equal(repo.list('message').length, 1);
  assert.equal(repo.list('message')[0].folder, 'trash');
  assert.equal(repo.list('message')[0].deletedFromFolder, 'sent');
  restoreMessage(repo, repo.list('message')[0].id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message')[0].folder, 'sent');
});

test('missing Sent special-use mapping creates a Sent mailbox rather than using INBOX', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.folders.delete('Sent'); remote.add('Trash');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  restoreMessage(repo, repo.list('message')[0].id);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message')[0].folder, 'sent');
  assert.ok(remote.calls.some(c => c[0] === 'create' && c[1] === 'Boxmail Sent'));
  assert.equal(remote.folders.get('INBOX').messages.size, 0);
});

test('empty trash requires approval, removes only the chosen account, and retains shared draft attachments', async t => {
  const repo = await fixture(t);
  repo.put('account', { ...account, isDemo: true });
  const removed = await saveAttachment(repo, base.id, 'removed.txt', Buffer.from('delete'));
  const shared = await saveAttachment(repo, base.id, 'shared.txt', Buffer.from('keep'));
  repo.put('message', { ...base, folder: 'trash', attachmentIds: [removed.id, shared.id] });
  repo.put('message', { ...base, id: 'sent', folder: 'sent' });
  repo.put('message', { ...base, id: 'other-account', accountId: 'a2', folder: 'trash' });
  repo.put('draft', { id: 'd1', accountId: account.id, attachmentIds: [shared.id] });
  repo.put('mutation', { id: 'flag', accountId: account.id, messageId: base.id });
  repo.put('job', { id: 'summary', accountId: account.id, messageId: base.id });
  await assert.rejects(emptyTrash(repo, account.id, '', false), /明确确认/);
  assert.ok(repo.get('message', base.id));
  const result = await emptyTrash(repo, account.id, '', true);
  assert.equal(result.count, 1); assert.equal(repo.get('message', base.id), null);
  assert.ok(repo.get('message', 'sent')); assert.ok(repo.get('message', 'other-account'));
  assert.ok(repo.get('attachment', shared.id)); await access(shared.path);
  assert.equal(repo.get('attachment', removed.id), null); await assert.rejects(access(removed.path));
  assert.equal(repo.get('mutation', 'flag'), null); assert.equal(repo.get('job', 'summary'), null);
  assert.equal((await emptyTrash(repo, account.id, '', true)).count, 0);
});

test('old delivery receipts do not retain attachments after the Sent mail is permanently cleared', async t => {
  const repo = await fixture(t);
  repo.put('account', { ...account, isDemo: true });
  const file = await saveAttachment(repo, 'sent-old', 'sent.txt', Buffer.from('sent attachment'));
  repo.put('message', { ...base, id: 'sent-old', folder: 'trash', attachmentIds: [file.id] });
  repo.put('draft', { id: 'old', accountId: account.id, status: 'sent', body: '历史已发送草稿', attachmentIds: [file.id] });
  await emptyTrash(repo, account.id, '', true);
  assert.equal(repo.get('attachment', file.id), null);
  await assert.rejects(access(file.path));
  assert.equal(repo.get('draft', 'old').status, 'sent');
  assert.deepEqual(repo.get('draft', 'old').attachmentIds, []);
});

test('empty trash clears uncached server mail and applies pending restores before clearing', async t => {
  const repo = await fixture(t), remote = mailbox();
  remote.add('Trash', '<restore@example.com>'); remote.add('Trash', '<delete@example.com>');
  remote.add('Sent', '<sent@example.com>');
  await syncAccount(repo, { ...account }, 'pw', { ...remote.options, batchSize: 1 });
  // The newest cached Trash mail is restored; the older, uncached one must still be purged.
  const restored = repo.list('message').find(m => m.folder === 'trash');
  restoreMessage(repo, restored.id);
  const pendingDelete = repo.list('message').find(m => m.folder === 'sent' && m.id !== restored.id);
  updateMessage(repo, pendingDelete.id, { folder: 'trash' });
  await emptyTrash(repo, account.id, 'pw', true, remote.options);
  assert.equal(remote.folders.get('Trash').messages.size, 0);
  assert.equal(remote.folders.get('Sent').messages.size, 1);
  assert.equal(repo.list('relocation').filter(r => r.original.folder === 'trash').length, 0);
  await syncAccount(repo, repo.get('account', account.id), 'pw', remote.options);
  assert.equal(repo.list('message').filter(m => m.folder === 'trash').length, 0);
  assert.equal(repo.list('message').length, 1);
  assert.equal(repo.list('message')[0].messageId, restored.messageId);
});

test('empty trash keeps local mail when the server fails or rejects expunge', async t => {
  const repo = await fixture(t), remote = mailbox(); remote.add('Trash');
  await syncAccount(repo, { ...account }, 'pw', remote.options);
  const id = repo.list('message')[0].id;
  remote.client.failConnect = true;
  await assert.rejects(emptyTrash(repo, account.id, 'pw', true, remote.options));
  assert.ok(repo.get('message', id));
  remote.client.failConnect = false; remote.client.failDelete = true;
  await assert.rejects(emptyTrash(repo, account.id, 'pw', true, remote.options), /服务器未确认/);
  assert.ok(repo.get('message', id)); assert.equal(remote.folders.get('Trash').messages.size, 1);
});

test('account edits made while clearing trash survive discovered folder updates', async t => {
  const repo = await fixture(t), remote = mailbox();
  const list = remote.client.list;
  remote.client.list = async () => {
    repo.put('account', { ...repo.get('account', account.id), name: '新账户名称', signature: '新签名' });
    return list();
  };
  await emptyTrash(repo, account.id, 'pw', true, remote.options);
  const saved = repo.get('account', account.id);
  assert.equal(saved.name, '新账户名称');
  assert.equal(saved.signature, '新签名');
  assert.equal(saved.folders.trash, 'Trash');
});

test('trash API exposes the same restore target in compact state, pages and details and enforces account locks', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-trash-api-'));
  let release, started;
  const clearing = new Promise(resolve => { started = resolve; });
  const app = await startServer({ directory, token, demo: false,
    mailEmptyTrash: async (...args) => { started(); await new Promise(resolve => { release = resolve; }); return emptyTrash(...args); } });
  t.after(async () => { release?.(); await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('account', { ...account, isDemo: true });
  app.repo.put('message', { ...base, folder: 'trash', deletedFromFolder: 'sent' });
  const request = async (route, body, method = body ? 'POST' : 'GET') => {
    const r = await fetch(`http://127.0.0.1:${app.port}${route}`, { method,
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json() };
  };
  for (const route of ['/state?compact=1', '/messages?accountId=a1&folder=trash'])
    assert.equal((await request(route)).body.messages[0].restoreFolder, 'sent');
  assert.equal((await request('/messages/m1')).body.restoreFolder, 'sent');
  assert.equal((await request('/messages/m1/restore', {})).body.folder, 'sent');
  await request('/messages/m1', { folder: 'archive' }, 'PATCH');
  for (const route of ['/state?compact=1', '/messages?accountId=a1&folder=archive'])
    assert.equal((await request(route)).body.messages[0].unarchiveFolder, 'sent');
  assert.equal((await request('/messages/m1')).body.unarchiveFolder, 'sent');
  assert.equal((await request('/messages/m1/unarchive', {})).body.folder, 'sent');
  await request('/messages/m1', { folder: 'trash' }, 'PATCH');
  assert.equal((await request('/trash/empty', { accountId: account.id })).status, 403);
  assert.equal((await request('/trash/empty', { accountId: 'missing', approved: true })).status, 404);
  const pending = request('/trash/empty', { accountId: account.id, approved: true });
  await clearing;
  assert.equal((await request('/messages/m1/restore', {})).status, 409);
  assert.equal((await request('/messages/m1/unarchive', {})).status, 409);
  assert.equal((await request('/messages/m1', { starred: true }, 'PATCH')).status, 409);
  assert.equal((await request('/trash/empty', { accountId: account.id, approved: true })).status, 409);
  assert.equal((await request('/agent', { messageId: base.id, task: 'summary' })).status, 409);
  release(); assert.equal((await pending).status, 200);
  assert.equal((await request('/messages?accountId=a1&folder=trash')).body.total, 0);
});
