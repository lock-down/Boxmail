import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import os from 'node:os';
import path from 'node:path';

const args = process.argv.slice(2);
const rootIndex = args.indexOf('--root');
const root = path.resolve(rootIndex < 0 ? fileURLToPath(new URL('..', import.meta.url)) : args[rootIndex + 1]);
const count = Number(args.find(value => /^\d+$/.test(value)) || 2400);
const token = 'boxmail-startup-synthetic-session-20261024';
const moduleURL = name => pathToFileURL(path.join(root, 'Backend/src', name)).href;

if (args.includes('--child')) {
  const directory = args[args.indexOf('--directory') + 1];
  const started = performance.now();
  const { startServer } = await import(moduleURL('server.js'));
  const imported = performance.now();
  const app = await startServer({ directory, token, demo: false });
  const listening = performance.now();
  const request = async route => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { headers: { 'X-Boxmail-Token': token } });
    assert.equal(response.status, 200);
    return response.json();
  };
  try {
    const snapshot = await request('/state?compact=1&previews=0');
    const stateReady = performance.now();
    assert.equal(snapshot.messages.length, count);
    const page = await request('/messages?accountId=a0&folder=inbox&limit=100');
    const pageReady = performance.now();
    assert.equal(page.messages.length, Math.min(100, count / 4));
    const selected = await request(`/messages/${page.messages[0].id}`);
    assert.ok(selected.body.includes('项目资料'));
    assert.ok(page.messages.every(mail => !mail.preview.includes('测试签名')));
    const bodyReady = performance.now();
    const thread = await request(`/messages/${selected.id}/thread`);
    assert.equal(thread.total, 1);
    process.stdout.write(JSON.stringify({
      importMs: imported - started, listenMs: listening - started,
      stateMs: stateReady - listening, firstPageMs: pageReady - stateReady,
      threadMs: performance.now() - bodyReady,
      readyMs: performance.now() - started, readyRSSMiB: process.memoryUsage().rss / 1024 ** 2,
      stateBytes: Buffer.byteLength(JSON.stringify(snapshot)),
    }) + '\n');
  } finally { await app.close(); }
} else {
  assert.ok(Number.isSafeInteger(count) && count >= 400 && count <= 20000 && count % 4 === 0);
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-startup-'));
  const { Repository } = await import(moduleURL('database.js'));
  const repo = new Repository(directory);
  try {
    const body = '项目资料与历史正文，仅用于本机启动测量。'.repeat(400);
    repo.transaction(() => {
      for (let i = 0; i < 4; i++) repo.put('account', { id: `a${i}`, name: '合成账户', email: `me${i}@example.test`,
        username: '', imapHost: '', imapPort: 993, imapTLS: true, smtpHost: '', smtpPort: 465, smtpTLS: true, isDemo: true });
      for (let i = 0; i < count; i++) repo.put('message', {
        id: `m${String(i).padStart(6, '0')}`, accountId: `a${i % 4}`, folder: 'inbox', sender: '合成联系人',
        senderEmail: 'sender@example.test', to: `me${i % 4}@example.test`, cc: '', subject: `项目 ${i}`,
        body: body + '\n--\n测试签名', html: `<p>${body}</p><div class="signature">测试签名</div>`,
        preview: '测试签名', date: '2026-10-24T00:00:00Z', category: '未分类', unread: false, starred: false,
        attachmentIds: [], bodyVersion: 1, messageId: `<m${i}@example.test>`,
      });
    });
    repo.close();
    const samples = [];
    for (let i = 0; i < 3; i++) {
      const sample = await new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [fileURLToPath(import.meta.url), '--child', '--root', root,
          '--directory', directory, String(count)],
        { stdio: ['ignore', 'pipe', 'pipe'] });
        let output = '', errors = '';
        child.stdout.on('data', chunk => { output += chunk; });
        child.stderr.on('data', chunk => { errors += chunk; });
        child.on('error', reject);
        child.on('exit', code => code === 0 ? resolve(JSON.parse(output.trim())) : reject(new Error(errors)));
      });
      samples.push(sample);
    }
    const median = Object.fromEntries(Object.keys(samples[0]).map(key => [key,
      Number(samples.map(sample => sample[key]).sort((a, b) => a - b)[1].toFixed(2))]));
    process.stdout.write(JSON.stringify({ node: process.versions.node, messages: count, accounts: 4,
      bodyCharacters: body.length, freshProcesses: 3, filesystemCache: 'warm',
      stateRoute: '/state?compact=1&previews=0', median, samples }, null, 2) + '\n');
  } finally {
    if (repo.db.isOpen) repo.close();
    await rm(directory, { recursive: true, force: true });
  }
}
