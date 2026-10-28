import { startServer } from '../../src/server.js';
import { parseMailContent } from '../../src/mail-content-worker.js';
const [directory, token] = process.argv.slice(2);
const app = await startServer({ directory, token, demo: false });
if (!app.repo.db.prepare("SELECT count(*) AS n FROM records WHERE kind='message'").get().n) {
  const parsed = await parseMailContent('mime', Buffer.from('From: Synthetic <sender@example.test>\r\n'
    + 'Subject: =?UTF-16LE?B?ANg=?=\r\n\r\nOriginal body survives restarts'));
  const body = 'a'.repeat(139) + String.fromCodePoint(0x20bb7) + ' original body tail';
  const base = { folder: 'inbox', sender: 'Synthetic', senderEmail: 'sender@example.test',
    to: 'reader@example.test', cc: '', subject: 'Synthetic message', body, html: `<p>${body}</p>`,
    preview: body.slice(0, 140), date: '2026-10-28T00:00:00Z', category: '未分类', unread: false,
    starred: false, attachmentIds: [], bodyVersion: 1, headersVersion: 1 };
  app.repo.transaction(() => {
    for (let i = 0; i < 6; i++) app.repo.put('account', { id: `a${i}`, name: 'Synthetic',
      email: `reader${i}@example.test`, username: '', imapHost: '', imapPort: 993, imapTLS: true,
      smtpHost: '', smtpPort: 465, smtpTLS: true, isDemo: false });
    for (let i = 0; i < 12000; i++) app.repo.put('message', { ...base, id: `m${i}`, accountId: `a${i % 6}` });
    const legacy = { ...base, id: 'legacy', accountId: 'a0', subject: parsed.parsed.subject };
    app.repo.db.prepare('INSERT INTO records VALUES(?,?,?)').run('message', legacy.id, JSON.stringify(legacy));
  });
}
process.stdout.write(JSON.stringify({ port: app.port }) + '\n');
process.once('SIGTERM', async () => { await app.close(); process.exit(0); });
