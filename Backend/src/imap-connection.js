import { ImapFlow } from 'imapflow';
import { required } from './validation.js';

export function createIMAPClient(account, password) {
  const client = new ImapFlow({
    host: account.imapHost,
    port: account.imapPort,
    secure: account.imapTLS,
    doSTARTTLS: account.imapTLS ? undefined : true,
    tls: { rejectUnauthorized: true },
    auth: {
      user: account.username,
      pass: required(password, '邮箱授权码', 4000),
    },
    logger: false,
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 60000,
  });
  client.on('error', () => {});
  return client;
}
