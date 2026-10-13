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
import { simpleParser } from 'mailparser';

test('SMTP sends Chinese MIME through verified TLS exactly once after approval', async (t) => {
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
  repo.put('account', {
    id: 'a1',
    name: '张明远',
    email: 'me@example.com',
    username: 'me@example.com',
    smtpHost: '127.0.0.1',
    smtpPort: smtp.server.address().port,
    smtpTLS: true,
    isDemo: false,
  });
  repo.put('draft', {
    id: 'd1',
    accountId: 'a1',
    to: 'chen@example.com',
    cc: '',
    bcc: 'hidden@example.com',
    subject: '排期确认',
    body: '陈经理，您好。请在周五前确认。',
    attachmentIds: [],
    status: 'draft',
  });
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
  assert.equal(repo.get('draft', 'd1').status, 'sent');
  const again = await sendDraft(repo, 'd1', 'mail-app-password', true, {
    storeSent,
  });
  assert.equal(again.alreadySent, true);
  assert.equal(received.length, 1);
});
