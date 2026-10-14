import test from 'node:test';
import assert from 'node:assert/strict';
import { mailServiceError } from '../src/mail-errors.js';
import { testAccount, syncAccount } from '../src/mail.js';
import { ServiceError } from '../src/validation.js';

const account = { imapHost: 'imap.qq.com', smtpHost: 'smtp.qq.com' };

test('authentication errors explain the protocol without exposing credentials or server payloads', () => {
  const secret = 'private-authorization-code';
  const payload = Buffer.from(`\0me@example.com\0${secret}`).toString('base64');
  for (const [protocol, details, status] of [
    ['IMAP', { authenticationFailed: true, responseStatus: 'NO' }, 'NO'],
    ['SMTP', { code: 'EAUTH', responseCode: 535 }, '535'],
  ]) {
    const error = mailServiceError({ ...details, message: secret, response: payload }, protocol, account);
    assert.equal(error.status, 502);
    assert.match(error.message, new RegExp(`${protocol} 登录被 QQ 邮箱拒绝（${status}）`));
    assert.match(error.message, /完整邮箱地址和登录用户名/);
    assert.equal(error.message.includes(secret), false);
    assert.equal(error.message.includes(payload), false);
  }
  const error = mailServiceError({ code: secret, originalCode: payload, serverResponseCode: payload, responseStatus: secret }, 'IMAP', account);
  assert.equal(error.message.includes(secret), false);
  assert.equal(error.message.includes(payload), false);
});

test('network, timeout, certificate and TLS errors offer distinct diagnostics', () => {
  for (const [details, expected] of [
    [{ code: 'ENOTFOUND' }, /无法解析服务器地址/],
    [{ code: 'ETIMEDOUT' }, /连接超时/],
    [{ name: 'TimeoutError' }, /连接超时/],
    [{ code: 'ERR_TLS_CERT_ALTNAME_INVALID' }, /证书验证失败/],
    [{ code: 'CERT_HAS_EXPIRED' }, /证书验证失败/],
    [{ code: 'ESOCKET', originalCode: 'CERT_HAS_EXPIRED' }, /证书验证失败/],
    [{ code: 'ESOCKET', originalCode: 'ENOTFOUND' }, /无法解析服务器地址/],
    [{ code: 'ESOCKET', originalCode: 'ECONNREFUSED' }, /无法建立连接/],
    [{ code: 'ERR_SSL_WRONG_VERSION_NUMBER' }, /SSL\/TLS 握手失败/],
    [{ code: 'ECONNREFUSED' }, /无法建立连接/],
  ]) {
    const error = mailServiceError(details, 'SMTP', account);
    assert.equal(error.status, 502);
    assert.match(error.message, expected);
  }
  const validation = new ServiceError('邮箱授权码无效');
  assert.equal(mailServiceError(validation, 'IMAP', account), validation);
});

function connections(imapError, smtpError) {
  const closed = { imap: 0, smtp: 0 };
  return {
    closed,
    factories: {
      clientFactory: () => ({
        async connect() { if (imapError) throw imapError; },
        async logout() { closed.imap++; },
        close() { closed.imap++; },
      }),
      transportFactory: () => ({
        async verify() { if (smtpError) throw smtpError; },
        close() { closed.smtp++; },
      }),
    },
  };
}

test('connection test reports both failed protocols and closes both clients', async () => {
  const { closed, factories } = connections(
    { authenticationFailed: true, responseStatus: 'NO' },
    { code: 'EAUTH', responseCode: 535 },
  );
  await assert.rejects(testAccount(account, 'test-password', factories), error => {
    assert.equal(error.status, 502);
    assert.match(error.message, /IMAP 登录被 QQ 邮箱拒绝（NO）/);
    assert.match(error.message, /SMTP 登录被 QQ 邮箱拒绝（535）/);
    return true;
  });
  assert.deepEqual(closed, { imap: 1, smtp: 1 });
});

test('connection test preserves the successful protocol when the other fails', async () => {
  for (const [imapError, smtpError, success, failure] of [
    [null, { code: 'ETLS' }, 'IMAP', 'SMTP'],
    [{ code: 'ENOTFOUND' }, null, 'SMTP', 'IMAP'],
  ]) {
    const { factories } = connections(imapError, smtpError);
    await assert.rejects(testAccount(account, 'test-password', factories), error => {
      assert.match(error.message, new RegExp(`${success} 连接成功`));
      assert.match(error.message, new RegExp(`${failure} (无法解析|SSL/TLS)`));
      return true;
    });
  }
});

test('connection test succeeds only after both protocols authenticate', async () => {
  const { closed, factories } = connections();
  assert.deepEqual(await testAccount(account, 'test-password', factories), { ok: true });
  assert.deepEqual(closed, { imap: 1, smtp: 1 });
});

test('sync login failure uses the same sanitized IMAP diagnosis', async () => {
  const { closed, factories } = connections({ authenticationFailed: true, responseStatus: 'NO', message: 'private-password' });
  await assert.rejects(syncAccount({}, account, 'test-password', factories), error => {
    assert.match(error.message, /IMAP 登录被 QQ 邮箱拒绝/);
    assert.equal(error.message.includes('private-password'), false);
    return true;
  });
  assert.equal(closed.imap, 1);
});
