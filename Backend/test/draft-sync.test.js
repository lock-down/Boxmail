import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { simpleParser } from 'mailparser';
import { Repository } from '../src/database.js';
import { MailContentWorker } from '../src/mail-content-worker.js';
import { syncRemoteDrafts, queueDraftDeletion } from '../src/draft-sync.js';
import { draftRevision } from '../src/draft-state.js';
import { saveAttachment } from '../src/attachments.js';
import { richContent } from '../src/rich-text.js';

const account = { id: 'a1', name: '本人', email: 'me@example.test', username: 'me@example.test', folders: { drafts: 'Drafts' } };
const localDraft = () => ({ id: 'local', accountId: 'a1', to: 'you@example.test', cc: '', bcc: 'hidden@example.test',
  subject: '草稿', body: '本机正文', attachmentIds: [], status: 'draft', updatedAt: new Date().toISOString(), syncState: 'pending' });
const mime = (body, messageId = '<external@example.test>', options = {}) => new MailComposer({
  from: account.email, to: 'you@example.test', subject: '草稿', text: body, messageId, ...options }).compile().build();

async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-draft-sync-'));
  let repo = new Repository(directory);
  const worker = new MailContentWorker();
  repo.put('account', account);
  t.after(async () => { await worker.close(); repo.close(); await rm(directory, { recursive: true, force: true }); });
  const state = { validity: '10', next: 1, messages: new Map(), appends: 0, deletes: [], afterAppend: null, searches: 0, onSearch: null };
  const add = raw => { const uid = state.next++; state.messages.set(uid, raw); return uid; };
  const client = { capabilities: new Set(['UIDPLUS']), mailbox: {},
    async getMailboxLock() { this.mailbox = { path: 'Drafts', uidValidity: state.validity, exists: state.messages.size }; return { release() {} }; },
    async status() { return { messages: state.messages.size, uidValidity: state.validity, uidNext: state.next }; },
    async search() { state.onSearch?.(++state.searches); return [...state.messages.keys()]; },
    async *fetch(uids) { for (const uid of uids) if (state.messages.has(uid)) yield { uid, flags: new Set(['\\Draft']), size: state.messages.get(uid).length }; },
    async fetchOne(uid) { return state.messages.has(uid) ? { uid, source: state.messages.get(uid) } : false; },
    async append(folder, raw, flags) {
      assert.equal(folder, 'Drafts'); assert.ok(flags.includes('\\Draft'));
      state.appends++; const uid = add(raw);
      await state.afterAppend?.(uid);
      return { uid, uidValidity: state.validity };
    },
    async messageDelete(uid, options) { assert.equal(options.uid, true); state.deletes.push(uid); state.messages.delete(uid); return true; },
  };
  const sync = (changes = {}) => syncRemoteDrafts(repo, { ...structuredClone(account), ...changes }, client, { contentWorker: worker, timeoutMs: 2000 });
  return { get repo() { return repo; }, state, client, sync, add,
    reopen() { repo.close(); repo = new Repository(directory); } };
}

test('rich draft and attachments upload with Bcc, converge without duplicates, and delete only their remote UID', async t => {
  const { repo, state, sync } = await fixture(t);
  const attachment = await saveAttachment(repo, 'local', '中文.txt', Buffer.from('附件内容'), 'text/plain');
  const draft = { ...localDraft(), ...richContent({ blocks: [{ kind: 'bullet', runs: [{ text: '正文', bold: true }] }] }), attachmentIds: [attachment.id] };
  repo.put('draft', draft);
  await sync(); await sync();
  assert.equal(state.appends, 1); assert.equal(state.messages.size, 1);
  const uploaded = await simpleParser([...state.messages.values()][0]);
  assert.match(uploaded.html, /<strong>正文/); assert.match(uploaded.text, /正文/);
  assert.equal(uploaded.bcc.value[0].address, 'hidden@example.test');
  assert.equal(uploaded.attachments[0].content.toString(), '附件内容');
  assert.equal(repo.get('draft', 'local').syncState, 'synced');
  queueDraftDeletion(repo, repo.get('draft', 'local')); repo.remove('draft', 'local');
  await sync();
  assert.equal(state.messages.size, 0); assert.equal(repo.list('draftDeletion').length, 0);
});

test('remote drafts import as editable documents and remote replacement invalidates the old editor revision', async t => {
  const { repo, state, sync, add } = await fixture(t);
  const first = add(await mime('旧正文', undefined, { html: '<p><strong>旧正文</strong></p>' }));
  await sync();
  const draft = repo.activeDrafts('a1')[0], revision = draftRevision(draft);
  assert.equal(draft.richText.blocks[0].runs[0].bold, true);
  state.messages.delete(first); add(await mime('服务器新正文'));
  await sync();
  assert.equal(repo.activeDrafts('a1').length, 1);
  assert.match(repo.get('draft', draft.id).body, /服务器新正文/);
  assert.notEqual(draftRevision(repo.get('draft', draft.id)), revision);
  assert.equal(state.appends, 0);
});

test('point size and color survive server draft upload and import on another installation', async t => {
  const { repo, state, sync } = await fixture(t);
  const styled = richContent({ blocks: [{ kind: 'bullet', runs: [
    { text: '重点', bold: true, fontSize: 24, color: '#B42318' },
    { text: '链接', link: 'https://example.test', fontSize: 12, color: '#3567AF' },
  ] }] });
  repo.put('draft', { ...localDraft(), ...styled });
  await sync();
  const uploaded = await simpleParser([...state.messages.values()][0]);
  assert.match(uploaded.html, /font-size:24pt;color:#B42318/);
  repo.remove('draft', 'local');
  await sync();
  const imported = repo.activeDrafts('a1');
  assert.equal(imported.length, 1);
  assert.deepEqual(imported[0].richText, styled.richText);
  assert.equal(imported[0].body, styled.body);
  assert.equal(state.appends, 1);
});

test('simultaneous local and remote edits retain both versions and require an explicit decision for the local copy', async t => {
  const { repo, state, sync, add } = await fixture(t);
  const first = add(await mime('共同基线')); await sync();
  const original = repo.activeDrafts('a1')[0];
  repo.put('draft', { ...original, body: '本机未同步修改', syncState: 'pending' });
  state.messages.delete(first); add(await mime('另一设备的修改'));
  await sync();
  const drafts = repo.activeDrafts('a1'); assert.equal(drafts.length, 2);
  assert.match(repo.get('draft', original.id).body, /另一设备的修改/);
  const copy = drafts.find(draft => draft.id !== original.id);
  assert.equal(copy.body, '本机未同步修改'); assert.equal(copy.syncState, 'conflict');
  await sync(); assert.equal(state.appends, 0);
});

test('lost APPEND acknowledgements reconcile the durable token across restart without uploading again', async t => {
  const context = await fixture(t);
  const { repo, state, sync } = context;
  repo.put('draft', localDraft());
  state.afterAppend = () => { throw new Error('synthetic connection lost'); };
  await assert.rejects(sync(), /connection lost/);
  assert.ok(repo.get('draft', 'local').remotePending);
  context.reopen();
  state.afterAppend = null;
  await sync(); await sync();
  assert.equal(state.appends, 1); assert.equal(state.messages.size, 1);
  assert.equal(context.repo.get('draft', 'local').syncState, 'synced');
});

test('editing while APPEND is in flight preserves the latest body for the next sync', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft());
  state.afterAppend = () => {
    const current = repo.get('draft', 'local'); repo.put('draft', { ...current, body: 'APPEND 期间的新编辑' });
  };
  await sync();
  assert.equal(repo.get('draft', 'local').body, 'APPEND 期间的新编辑');
  assert.equal(repo.get('draft', 'local').syncState, 'pending');
  state.afterAppend = null; await sync();
  assert.equal(state.messages.size, 1);
  assert.match((await simpleParser([...state.messages.values()][0])).text, /APPEND 期间的新编辑/);
});

test('remote deletion keeps the local draft without resurrecting it automatically', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft()); await sync(); state.messages.clear();
  await sync(); await sync();
  assert.equal(repo.get('draft', 'local').body, '本机正文');
  assert.equal(repo.get('draft', 'local').syncState, 'conflict');
  assert.equal(state.appends, 1); assert.equal(state.messages.size, 0);
});

test('UIDVALIDITY changes never delete a new draft that reuses the old UID', async t => {
  const { repo, state, sync, add } = await fixture(t);
  repo.put('draft', localDraft()); await sync();
  queueDraftDeletion(repo, repo.get('draft', 'local')); repo.remove('draft', 'local');
  state.messages.clear(); state.validity = '11'; state.next = 1;
  add(await mime('新邮箱中的另一份草稿', '<different@example.test>'));
  await sync();
  assert.equal(state.deletes.length, 0); assert.equal(state.messages.size, 1);
  assert.match(repo.activeDrafts('a1')[0].body, /另一份草稿/);
});

test('servers without UIDPLUS never trigger a mailbox-wide EXPUNGE', async t => {
  const { repo, state, client, sync } = await fixture(t);
  repo.put('draft', localDraft()); await sync();
  client.capabilities.clear();
  queueDraftDeletion(repo, repo.get('draft', 'local')); repo.remove('draft', 'local');
  await assert.rejects(sync(), /UIDPLUS/);
  assert.equal(state.deletes.length, 0); assert.equal(state.messages.size, 1);
  assert.equal(repo.list('draftDeletion').length, 1);
});

test('an edit during the final inventory check cannot be overwritten by an older upload snapshot', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft());
  state.onSearch = count => { if (count === 3) repo.put('draft', { ...repo.get('draft', 'local'), body: '最终核对期间的编辑' }); };
  await sync();
  assert.equal(repo.get('draft', 'local').body, '最终核对期间的编辑');
  assert.equal(repo.get('draft', 'local').syncState, 'pending');
});

test('changing the sender account during APPEND never binds the old mailbox to the new account', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft());
  state.afterAppend = () => repo.put('draft', { ...repo.get('draft', 'local'), accountId: 'a2', remotePending: null });
  await sync();
  assert.equal(repo.get('draft', 'local').accountId, 'a2');
  assert.equal(repo.get('draft', 'local').remoteDraft, undefined);
  assert.equal(repo.list('draftDeletion')[0].accountId, 'a1');
});

test('deleting a local draft during APPEND queues the acknowledged remote copy for cleanup', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft());
  state.afterAppend = () => { queueDraftDeletion(repo, repo.get('draft', 'local')); repo.remove('draft', 'local'); };
  await sync();
  assert.equal(repo.get('draft', 'local'), null);
  state.afterAppend = null; await sync();
  assert.equal(state.messages.size, 0);
});

test('a second device keeps forwarded originals separate from the editable rich introduction', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', { ...localDraft(), ...richContent({ blocks: [{ kind: 'paragraph', runs: [{ text: '转发说明', bold: true }] }] }),
    forwardedHTML: '<table><tr><td>原文与表格</td></tr></table>', forwardedText: '原文与表格' });
  await sync();
  // Another installation sees the MIME draft without this installation's local binding.
  repo.remove('draft', 'local');
  await sync();
  const imported = repo.activeDrafts('a1')[0];
  assert.equal(imported.body, '转发说明'); assert.equal(imported.richText.blocks[0].runs[0].bold, true);
  assert.match(imported.forwardedHTML, /<table>/); assert.match(imported.forwardedText, /原文与表格/);
  assert.equal(state.appends, 1);
});

test('old read-only draft mail caches migrate to editable drafts without losing their contents or attachments', async t => {
  const { repo, state, sync, add } = await fixture(t);
  const uid = add(await mime('旧缓存正文'));
  const attachment = await saveAttachment(repo, 'legacy', 'note.txt', Buffer.from('保留附件'), 'text/plain');
  repo.put('message', { id: 'legacy', accountId: 'a1', folder: 'drafts', remotePath: 'Drafts', uid,
    uidValidity: state.validity, messageId: '<external@example.test>', to: 'you@example.test', cc: '',
    subject: '草稿', body: '旧缓存正文', html: '<p><strong>旧缓存正文</strong></p>',
    attachmentIds: [attachment.id], date: new Date().toISOString() });
  await sync();
  assert.equal(repo.get('message', 'legacy'), null);
  const draft = repo.activeDrafts('a1')[0];
  assert.equal(draft.body, '旧缓存正文'); assert.equal(draft.richText.blocks[0].runs[0].bold, true);
  assert.deepEqual(draft.attachmentIds, [attachment.id]);
  assert.equal(repo.get('attachment', attachment.id).text, '保留附件');
  assert.equal(state.appends, 0);
});

test('changing the IMAP endpoint cannot apply queued draft deletions to a new server with matching UIDs', async t => {
  const { repo, state, sync, add } = await fixture(t);
  repo.put('draft', localDraft()); await sync();
  queueDraftDeletion(repo, repo.get('draft', 'local')); repo.remove('draft', 'local');
  state.messages.clear(); state.next = 1;
  add(await mime('另一台服务器的草稿', '<other-server@example.test>'));
  await sync({ imapHost: 'other.example.test' });
  assert.equal(state.deletes.length, 0); assert.equal(state.messages.size, 1);
  assert.match(repo.activeDrafts('a1')[0].body, /另一台服务器/);
});

test('unsent local work is detached from remote bindings after the server identity changes', async t => {
  const { repo, state, sync } = await fixture(t);
  repo.put('draft', localDraft()); await sync();
  state.messages.clear();
  await sync({ username: 'another@example.test' });
  assert.equal(repo.get('draft', 'local').syncState, 'conflict');
  assert.equal(repo.get('draft', 'local').remoteDraft, null);
  assert.equal(state.appends, 1);
});

test('oversized attachment collections stop before MIME allocation or network upload and retain local files', async t => {
  const { repo, state, sync } = await fixture(t);
  const files = [];
  for (let index = 0; index < 2; index++) files.push(await saveAttachment(repo, 'local', `large-${index}.bin`,
    Buffer.alloc(13 * 1024 * 1024), 'application/octet-stream'));
  repo.put('draft', { ...localDraft(), attachmentIds: files.map(file => file.id) });
  await assert.rejects(sync(), /25 MB/);
  assert.equal(state.appends, 0); assert.equal(repo.get('draft', 'local').attachmentIds.length, 2);
  assert.ok(files.every(file => repo.get('attachment', file.id)));
});
