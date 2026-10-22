import test from 'node:test';
import assert from 'node:assert/strict';
import { SMTPServer } from 'smtp-server';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import tls from 'node:tls';
import os from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { sendDraft } from '../src/mail.js';
import { saveAttachment } from '../src/attachments.js';
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

test('sending a forwarded draft keeps its attachments with the original message', async (t) => {
  const { repo, received, port } = await smtpFixture(t);
  repo.put('account', accountFor(port));
  const attachment = await saveAttachment(
    repo,
    'm1',
    '原件.txt',
    Buffer.from('原始附件'),
    'text/plain',
  );
  // A forwarded draft reuses the source message's attachment ids instead of uploading copies.
  repo.put('draft', draftFor({ attachmentIds: [attachment.id] }));
  await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent: async () => {},
  });
  assert.equal(received.length, 1);
  assert.equal(repo.get('attachment', attachment.id).messageId, 'm1');
});
