import test from 'node:test';
import assert from 'node:assert/strict';
import { SMTPServer } from 'smtp-server';
import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import tls from 'node:tls';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { emptyTrash, sendDraft, syncAccount, updateMessage } from '../src/mail.js';
import { attachmentBytes, modelAttachment, saveAttachment } from '../src/attachments.js';
import { createReplyDraft } from '../src/reply.js';
import { AttachmentBatch } from '../src/attachment-batch.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { conversation } from '../src/threads.js';
import { simpleParser } from 'mailparser';

async function smtpFixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-smtp-'));
  const keyPath = path.join(directory, 'key.pem'),
    certPath = path.join(directory, 'cert.pem');
  execFileSync(
    '/usr/bin/openssl',
    [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '1',
      '-subj',
      '/CN=127.0.0.1',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
    ],
    { stdio: 'ignore' },
  );
  const cert = await readFile(certPath, 'utf8');
  const key = await readFile(keyPath, 'utf8');
  const oldCertificates = tls.getCACertificates('default');
  tls.setDefaultCACertificates([...oldCertificates, cert]);
  const received = [];
  const smtp = new SMTPServer({
    secure: true,
    key,
    cert,
    logger: false,
    onAuth(auth, session, callback) {
      callback(
        auth.username === 'me@example.com' &&
          auth.password === 'mail-app-password'
          ? null
          : new Error('Invalid credentials'),
        { user: 'me@example.com' },
      );
    },
    onData(stream, session, callback) {
      const chunks = [];
      stream.on('data', (c) => chunks.push(c));
      stream.on('end', () => {
        received.push(Buffer.concat(chunks));
        callback();
      });
    },
  });
  await new Promise((resolve) => smtp.listen(0, '127.0.0.1', resolve));
  const repo = new Repository(directory);
  t.after(async () => {
    tls.setDefaultCACertificates(oldCertificates);
    await new Promise((r) => smtp.close(r));
    repo.close();
    await rm(directory, { recursive: true, force: true });
  });
  return { repo, received, port: smtp.server.address().port };
}

function accountFor(port) {
  return {
    id: 'a1',
    name: '张明远',
    email: 'me@example.com',
    username: 'me@example.com',
    smtpHost: '127.0.0.1',
    smtpPort: port,
    smtpTLS: true,
    isDemo: false,
  };
}

function draftFor(overrides = {}) {
  return {
    id: 'd1',
    accountId: 'a1',
    to: 'chen@example.com',
    cc: '',
    bcc: 'hidden@example.com',
    subject: '排期确认',
    body: '陈经理，您好。请在周五前确认。',
    attachmentIds: [],
    status: 'draft',
    inReplyTo: '<previous@example.com>',
    references: ['<root@example.com>', '<previous@example.com>'],
    ...overrides,
  };
}

test('SMTP sends Chinese MIME through verified TLS exactly once after approval', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  repo.put('draft', draftFor());
  await assert.rejects(
    sendDraft(repo, 'd1', 'mail-app-password', false),
    /确认/,
  );
  assert.equal(received.length, 0);
  let appended = 0;
  const storeSent = async (a, p, raw) => {
    appended++;
    assert.match(raw.toString(), /Message-ID:/i);
  };
  const result = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent,
  });
  assert.equal(result.ok, true);
  assert.equal(received.length, 1);
  assert.equal(appended, 1);
  const parsed = await simpleParser(received[0]);
  assert.equal(parsed.subject, '排期确认');
  assert.match(parsed.text, /周五前确认/);
  assert.equal(parsed.bcc, undefined);
  assert.equal(parsed.inReplyTo, '<previous@example.com>');
  assert.deepEqual(parsed.references, ['<root@example.com>', '<previous@example.com>']);
  const sent = repo.get('message', 'sent-d1');
  assert.equal(sent.inReplyTo, '<previous@example.com>');
  assert.deepEqual(sent.references, ['<root@example.com>', '<previous@example.com>']);
  repo.put('message', { ...sent, id: 'previous', messageId: '<previous@example.com>', inReplyTo: '', references: [] });
  assert.equal(conversation(repo, sent.id).total, 2);
  assert.equal(repo.get('draft', 'd1').status, 'sent');
  const again = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent,
  });
  assert.equal(again.alreadySent, true);
  assert.equal(received.length, 1);
});

test('concurrent sends of the same draft deliver one message and reject the other with 409', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  repo.put('draft', draftFor());
  let appended = 0;
  const storeSent = async () => {
    appended++;
  };
  const results = await Promise.allSettled([
    sendDraft(repo, 'd1', 'mail-app-password', true, { storeSent }),
    sendDraft(repo, 'd1', 'mail-app-password', true, { storeSent }),
  ]);
  assert.equal(received.length, 1);
  const fulfilled = results.filter((result) => result.status === 'fulfilled');
  const rejected = results.filter((result) => result.status === 'rejected');
  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason.status, 409);
  assert.match(rejected[0].reason.message, /重复发送/);
  assert.equal(appended, 1);
  assert.equal(repo.get('draft', 'd1').status, 'sent');
  assert.equal(repo.list('message').filter((m) => m.id === 'sent-d1').length, 1);
  const again = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent,
  });
  assert.equal(again.alreadySent, true);
  assert.equal(received.length, 1);
});

test('a failure before SMTP releases the send claim and restores the draft', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-send-claim-'));
  const repo = new Repository(directory);
  t.after(async () => {
    repo.close();
    await rm(directory, { recursive: true, force: true });
  });
  repo.put('account', accountFor(1));
  repo.put('draft', draftFor({ attachmentIds: ['missing-attachment'] }));
  await assert.rejects(
    sendDraft(repo, 'd1', 'mail-app-password', true, {
      storeSent: async () => {},
    }),
    (error) => error.status === 404 && /附件不存在/.test(error.message),
  );
  assert.equal(repo.get('draft', 'd1').status, 'draft');
  assert.equal(repo.list('message').length, 0);
});

test('sent message attachments are reassociated with the sent copy', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  const attachment = await saveAttachment(
    repo,
    'd1',
    '排期说明.txt',
    Buffer.from('附件正文内容'),
    'text/plain',
  );
  repo.put('draft', draftFor({ attachmentIds: [attachment.id] }));
  const result = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent: async () => {},
  });
  assert.equal(result.ok, true);
  assert.equal(received.length, 1);
  const saved = repo.get('attachment', attachment.id);
  const sent = repo.get('message', 'sent-d1');
  assert.ok(sent.attachmentIds.includes(attachment.id));
  assert.equal(saved.messageId, 'sent-d1');
  const parsed = await simpleParser(received[0]);
  assert.equal(parsed.attachments[0].filename, '排期说明.txt');
  assert.equal(
    Buffer.from(parsed.attachments[0].content).toString('utf8'),
    '附件正文内容',
  );
});

test('sending to a contact-completion display name delivers to the bare address', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  repo.put('draft', draftFor({ to: '"张明远" <chen@example.com>' }));
  const result = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent: async () => {},
  });
  assert.equal(result.ok, true);
  assert.equal(received.length, 1);
  const parsed = await simpleParser(received[0]);
  assert.deepEqual(
    parsed.to.value.map(({ name, address }) => ({ name, address })),
    [{ name: '张明远', address: 'chen@example.com' }],
  );
});

function originalMessage(attachmentId) {
  return {
    id: 'm1', accountId: 'a1', folder: 'inbox', sender: '原发件人', senderEmail: 'sender@example.com',
    to: 'me@example.com', cc: '', subject: '原始邮件', body: '请查看附件', preview: '请查看附件',
    date: '2026-10-22T00:00:00Z', messageId: '<original@example.com>', attachmentIds: [attachmentId],
    category: '未分类', unread: false, starred: false, summary: null,
  };
}

function sentMailbox(raw) {
  return {
    mailbox: { uidValidity: '10', exists: 1 },
    async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }, { path: 'Sent', specialUse: '\\Sent' }]; },
    async getMailboxLock() { return { release() {} }; },
    async *fetch() {
      yield { uid: 7, size: raw.length, flags: new Set(['\\Seen']), internalDate: new Date() };
    },
    async fetchOne() { return { source: raw }; },
  };
}

test('forwarded attachments remain readable and analyzable on both mails before and after Sent sync', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  const attachment = await saveAttachment(
    repo,
    'm1',
    '原件.txt',
    Buffer.from('原始附件'),
    'text/plain',
  );
  repo.put('message', originalMessage(attachment.id));
  const draft = { ...createReplyDraft(repo, 'm1', { forward: true }), to: 'chen@example.com' };
  repo.put('draft', draft);
  // A rejected SMTP login must retain the prepared copy for the next send attempt.
  await assert.rejects(sendDraft(repo, draft.id, 'wrong-password', true, {
    storeSent: async () => {},
  }));
  const prepared = repo.get('draft', draft.id);
  assert.equal(prepared.status, 'draft');
  assert.notEqual(prepared.attachmentIds[0], attachment.id);
  assert.equal(repo.list('attachment').length, 2);
  await sendDraft(repo, draft.id, 'mail-app-password', true, {
    storeSent: async () => {},
  });
  assert.equal(received.length, 1);
  assert.equal(repo.list('attachment').length, 2);
  const sentId = 'sent-' + draft.id;
  const sent = repo.get('message', sentId);
  assert.deepEqual(sent.attachmentIds, prepared.attachmentIds);
  const copied = repo.get('attachment', sent.attachmentIds[0]);
  assert.notEqual(copied.path, attachment.path);
  assert.equal(repo.get('attachment', attachment.id).messageId, 'm1');
  const parsed = await simpleParser(received[0]);
  assert.equal(parsed.attachments[0].filename, attachment.name);
  assert.equal(parsed.attachments[0].content.toString(), '原始附件');

  const manager = new AttachmentBatch(repo, { run: async (repo, input) => {
    const file = repo.get('attachment', input.attachmentId);
    repo.put('attachment', { ...file, analysis: '分析来源：' + input.messageId });
  } });
  t.after(() => manager.close());
  async function verifyAttachment(messageId) {
    const mail = repo.get('message', messageId);
    const visible = repo.attachmentHeaders().filter(file =>
      mail.attachmentIds.includes(file.id) && file.messageId === messageId);
    assert.equal(visible.length, 1);
    const id = visible[0].id;
    assert.equal((await attachmentBytes(repo, id)).buffer.toString(), '原始附件');
    assert.equal((await modelAttachment(repo, id)).kind, 'text');
    const job = manager.start({ messageId, accountId: 'a1', config: DEFAULT_AI, apiKey: 'test-key', force: true });
    await manager.workers.get(job.id).promise;
    assert.equal(repo.get('job', job.id).status, 'completed');
    assert.equal(repo.get('attachment', id).analysis, '分析来源：' + messageId);
  }
  await verifyAttachment('m1');
  await verifyAttachment(sentId);
  assert.equal(repo.get('attachment', attachment.id).analysis, '分析来源：m1');

  await syncAccount(repo, repo.get('account', 'a1'), 'pw', {
    folder: 'sent', clientFactory: () => sentMailbox(received[0]),
  });
  const synced = repo.list('message').find(mail => mail.folder === 'sent');
  assert.notEqual(synced.id, sentId);
  assert.deepEqual(synced.attachmentIds, sent.attachmentIds);
  await verifyAttachment('m1');
  await verifyAttachment(synced.id);
  assert.equal(repo.get('attachment', attachment.id).messageId, 'm1');
  assert.equal(repo.get('attachment', attachment.id).analysis, '分析来源：m1');

  updateMessage(repo, 'm1', { folder: 'trash' });
  await emptyTrash(repo, 'a1', 'pw', true, { clientFactory: () => ({
    mailbox: { exists: 0 }, async connect() {}, async logout() {}, close() {},
    async list() { return [{ path: 'INBOX' }, { path: 'Trash', specialUse: '\\Trash' }]; },
    async getMailboxLock() { return { release() {} }; },
  }) });
  assert.equal(repo.get('message', 'm1'), null);
  assert.equal(repo.get('attachment', attachment.id), null);
  await assert.rejects(readFile(attachment.path), { code: 'ENOENT' });
  await verifyAttachment(synced.id);
});

test('Sent sync repairs legacy forwarded copies without taking attachments from the source mail', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  const attachment = await saveAttachment(repo, 'm1', '历史附件.txt', Buffer.from('历史附件正文'), 'text/plain');
  repo.put('message', originalMessage(attachment.id));
  // Recreate the shared ids written by older releases after obtaining a real MIME message.
  repo.put('draft', draftFor({ attachmentIds: [attachment.id] }));
  await sendDraft(repo, 'd1', 'mail-app-password', true, { storeSent: async () => {} });
  const local = repo.get('message', 'sent-d1');
  repo.put('message', { ...local, attachmentIds: [attachment.id] });
  const manager = new AttachmentBatch(repo, { run: async (repo, input) => {
    const file = repo.get('attachment', input.attachmentId);
    repo.put('attachment', { ...file, analysis: '历史任务重试成功' });
  } });
  t.after(() => manager.close());
  const job = manager.start({ messageId: local.id, config: DEFAULT_AI, apiKey: 'test-key' });
  await manager.workers.get(job.id).promise;
  assert.equal(repo.get('job', job.id).status, 'failed');
  await syncAccount(repo, repo.get('account', 'a1'), 'pw', {
    folder: 'sent', clientFactory: () => sentMailbox(received[0]),
  });
  const synced = repo.list('message').find(mail => mail.folder === 'sent');
  assert.notEqual(synced.attachmentIds[0], attachment.id);
  const copied = repo.get('attachment', synced.attachmentIds[0]);
  assert.equal(copied.messageId, synced.id);
  assert.notEqual(copied.path, attachment.path);
  assert.equal((await attachmentBytes(repo, copied.id)).buffer.toString(), '历史附件正文');
  assert.equal(repo.get('attachment', attachment.id).messageId, 'm1');
  assert.deepEqual(repo.get('message', 'm1').attachmentIds, [attachment.id]);
  assert.equal(repo.get('job', job.id).messageId, synced.id);
  assert.equal(repo.get('job', job.id).attachmentItems[0].id, copied.id);
  manager.start({ config: DEFAULT_AI, apiKey: 'test-key' }, job.id);
  await manager.workers.get(job.id).promise;
  assert.equal(repo.get('job', job.id).status, 'completed');
  assert.equal(repo.get('attachment', copied.id).analysis, '历史任务重试成功');
  assert.equal(repo.get('attachment', attachment.id).analysis, null);
});

test('a missing forwarded file rolls back prepared copies without changing the source or draft', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-forward-copy-failure-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('account', accountFor(1));
  const first = await saveAttachment(repo, 'm1', '可读.txt', Buffer.from('原件'), 'text/plain');
  const missing = await saveAttachment(repo, 'm1', '缺失.txt', Buffer.from('待删除'), 'text/plain');
  await rm(missing.path);
  const ids = [first.id, missing.id];
  repo.put('draft', draftFor({ attachmentIds: ids }));
  const filesBefore = await readdir(path.join(directory, 'attachments'));
  await assert.rejects(sendDraft(repo, 'd1', 'pw', true, { storeSent: async () => {} }));
  assert.equal(repo.get('draft', 'd1').status, 'draft');
  assert.deepEqual(repo.get('draft', 'd1').attachmentIds, ids);
  assert.equal(repo.list('attachment').length, 2);
  assert.deepEqual(await readdir(path.join(directory, 'attachments')), filesBefore);
  assert.equal(repo.get('attachment', first.id).messageId, 'm1');
  assert.equal(await readFile(first.path, 'utf8'), '原件');
});

for (const ownerId of ['m1', 'cached-sent']) {
  test('cached shared attachments are repaired without redownloading mail when owned by ' + ownerId, async (t) => {
    const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-forward-cached-'));
    const repo = new Repository(directory);
    t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
    repo.put('account', accountFor(1));
    const attachment = await saveAttachment(repo, ownerId, '已缓存.txt', Buffer.from('共享附件正文'), 'text/plain');
    repo.put('message', { ...originalMessage(attachment.id), uid: 7, uidValidity: '10', remotePath: 'INBOX',
      bodyVersion: 1, headersVersion: 1 });
    repo.put('message', { ...originalMessage(attachment.id), id: 'cached-sent', folder: 'sent',
      uid: 7, uidValidity: '10', remotePath: 'Sent', bodyVersion: 1, headersVersion: 1,
      messageId: '<cached-sent@example.com>' });
    const manager = new AttachmentBatch(repo, { run: async (repo, input) => {
      const file = repo.get('attachment', input.attachmentId);
      repo.put('attachment', { ...file, analysis: '理解归属：' + input.messageId });
    } });
    t.after(() => manager.close());
    const jobs = [];
    for (const messageId of ['m1', 'cached-sent']) {
      const job = manager.start({ messageId, config: DEFAULT_AI, apiKey: 'test-key', force: true });
      await manager.workers.get(job.id).promise;
      assert.equal(repo.get('job', job.id).status, messageId === ownerId ? 'completed' : 'failed');
      jobs.push(job.id);
    }
    const client = sentMailbox(Buffer.from('cached'));
    client.fetchOne = async () => { throw new Error('Cached mail must not be downloaded again'); };
    const sync = async () => {
      for (const folder of ['sent', 'inbox']) {
        const result = await syncAccount(repo, repo.get('account', 'a1'), 'pw', {
          folder, clientFactory: () => client,
        });
        assert.equal(result.count, 0);
        assert.equal(result.repaired, 0);
      }
    };
    await sync();
    const source = repo.get('message', 'm1'), sent = repo.get('message', 'cached-sent');
    assert.notEqual(source.attachmentIds[0], sent.attachmentIds[0]);
    for (const mail of [source, sent]) {
      const file = repo.get('attachment', mail.attachmentIds[0]);
      assert.equal(file.messageId, mail.id);
      assert.equal((await attachmentBytes(repo, file.id)).buffer.toString(), '共享附件正文');
    }
    assert.notEqual(repo.get('attachment', source.attachmentIds[0]).path,
      repo.get('attachment', sent.attachmentIds[0]).path);
    assert.equal(repo.list('attachment').length, 2);
    await sync();
    assert.equal(repo.list('attachment').length, 2);
    assert.deepEqual(repo.get('message', 'm1').attachmentIds, source.attachmentIds);
    assert.deepEqual(repo.get('message', 'cached-sent').attachmentIds, sent.attachmentIds);
    for (const id of jobs) {
      const job = repo.get('job', id), mail = repo.get('message', job.messageId);
      assert.equal(job.attachmentItems[0].id, mail.attachmentIds[0]);
      if (job.status === 'failed') {
        manager.start({ config: DEFAULT_AI, apiKey: 'test-key' }, id);
        await manager.workers.get(id).promise;
      }
      assert.equal(repo.get('job', id).status, 'completed');
      assert.equal(repo.get('attachment', mail.attachmentIds[0]).analysis, '理解归属：' + mail.id);
    }
  });
}

test('an active attachment batch follows copied ids when cached ownership is repaired', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-forward-active-batch-'));
  const repo = new Repository(directory);
  const gate = Promise.withResolvers(), started = Promise.withResolvers();
  const calls = [];
  const manager = new AttachmentBatch(repo, { run: async (repo, input) => {
    calls.push(input.attachmentId);
    if (calls.length === 1) { started.resolve(); await gate.promise; }
    const file = repo.get('attachment', input.attachmentId);
    repo.put('attachment', { ...file, analysis: '批量理解完成' });
  } });
  t.after(async () => {
    gate.resolve(); await manager.close(); repo.close();
    await rm(directory, { recursive: true, force: true });
  });
  repo.put('account', accountFor(1));
  const own = await saveAttachment(repo, 'cached-sent', '自有.txt', Buffer.from('自有附件'), 'text/plain');
  const borrowed = await saveAttachment(repo, 'm1', '借用.txt', Buffer.from('原始附件'), 'text/plain');
  repo.put('message', originalMessage(borrowed.id));
  repo.put('message', { ...originalMessage(borrowed.id), id: 'cached-sent', folder: 'sent',
    attachmentIds: [own.id, borrowed.id], uid: 7, uidValidity: '10', remotePath: 'Sent',
    bodyVersion: 1, headersVersion: 1, messageId: '<active-sent@example.com>' });
  const job = manager.start({ messageId: 'cached-sent', config: DEFAULT_AI, apiKey: 'test-key' });
  const pending = manager.workers.get(job.id).promise;
  await started.promise;
  await syncAccount(repo, repo.get('account', 'a1'), 'pw', {
    folder: 'sent', clientFactory: () => sentMailbox(Buffer.from('cached')),
  });
  const sent = repo.get('message', 'cached-sent');
  assert.notEqual(sent.attachmentIds[1], borrowed.id);
  assert.deepEqual(repo.get('job', job.id).attachmentItems.map(item => item.id), sent.attachmentIds);
  gate.resolve();
  await pending;
  assert.equal(repo.get('job', job.id).status, 'completed');
  assert.deepEqual(calls, sent.attachmentIds);
  assert.equal(repo.get('attachment', borrowed.id).analysis, null);
});

test('a draft write failure rolls back copied attachment records and files together', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-forward-write-failure-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('account', accountFor(1));
  const file = await saveAttachment(repo, 'm1', '原件.txt', Buffer.from('保持原件'), 'text/plain');
  repo.put('draft', draftFor({ attachmentIds: [file.id] }));
  const put = repo.put.bind(repo);
  repo.put = (kind, value) => {
    if (kind === 'draft' && value.status === 'sending' && value.attachmentIds[0] !== file.id)
      throw new Error('Simulated draft write failure');
    return put(kind, value);
  };
  await assert.rejects(sendDraft(repo, 'd1', 'pw', true, { storeSent: async () => {} }), /draft write failure/);
  assert.equal(repo.get('draft', 'd1').status, 'draft');
  assert.deepEqual(repo.get('draft', 'd1').attachmentIds, [file.id]);
  assert.equal(repo.list('attachment').length, 1);
  assert.deepEqual(await readdir(path.join(directory, 'attachments')), [path.basename(file.path)]);
  assert.equal(await readFile(file.path, 'utf8'), '保持原件');
});
