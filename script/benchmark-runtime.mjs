import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { once } from 'node:events';
import { spawnSync } from 'node:child_process';
import { monitorEventLoopDelay } from 'node:perf_hooks';
import { setTimeout as delay } from 'node:timers/promises';
import { Repository } from '../Backend/src/database.js';
import { syncAccount } from '../Backend/src/mail.js';
import { runAgent } from '../Backend/src/agent.js';
import { saveAttachment } from '../Backend/src/attachments.js';
import { completion } from '../Backend/src/responses.js';
import { DEFAULT_AI } from '../Backend/src/ai-settings.js';

function syntheticPDF(pages) {
  const contentId = 3 + pages;
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Kids [${Array.from({ length: pages }, (_, i) => `${i + 3} 0 R`).join(' ')}] /Count ${pages} >>`,
    ...Array.from({ length: pages }, () => `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents ${contentId} 0 R >>`),
    '<< /Length 0 >>\nstream\n\nendstream'];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, i) => { offsets.push(Buffer.byteLength(pdf)); pdf += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = Buffer.byteLength(pdf);
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
    + offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('')
    + `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  return Buffer.from(pdf);
}

// Synthetic, local-only workloads. Each mode gets a fresh process for comparable peaks.
const mode = process.argv[2];
const rounds = Number(process.env.BOXMAIL_BENCHMARK_ROUNDS || 4);
assert.ok(Number.isSafeInteger(rounds) && rounds >= 1 && rounds <= 100);
if (!mode) {
  const results = {};
  for (const name of ['sync', 'ai', 'vision', 'pdf']) {
    const child = spawnSync(process.execPath, ['--expose-gc', process.argv[1], name], { encoding: 'utf8' });
    assert.equal(child.status, 0, child.stderr);
    results[name] = JSON.parse(child.stdout);
  }
  console.log(JSON.stringify(results, null, 2));
} else {
  assert.equal(typeof global.gc, 'function', 'Run individual modes with node --expose-gc');
  assert.ok(['sync', 'ai', 'vision', 'pdf'].includes(mode));
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-runtime-'));
  const repo = new Repository(directory);
  const body = 'Synthetic project update for local resource measurement. '.repeat(150);
  const account = { id: 'a', email: 'me@example.test', folders: { inbox: 'INBOX', sent: 'Sent' } };
  repo.put('account', account);
  const base = { accountId: 'a', sender: 'Sender', senderEmail: 'sender@example.test', to: account.email,
    date: '2026-10-23T00:00:00Z', body, html: `<p>${body}</p>`, category: '未分类', attachmentIds: [],
    bodyVersion: 1, headersVersion: 1, uidValidity: '10', unread: true, starred: false };
  let model;
  try {
    if (mode === 'sync') repo.transaction(() => {
      for (let i = 1; i <= 2400; i++) repo.put('message', { ...base, id: `m${i}`, uid: i,
        folder: 'sent', remotePath: 'Sent', messageId: `<cached-${i}@example.test>`, subject: `Cached ${i}` });
    });
    else repo.put('message', { ...base, id: 'm', folder: 'inbox', subject: '压力测试',
      html: Array.from({ length: 300 }, (_, i) => `<p>Original paragraph ${i}.</p>`).join('') });
    let output;
    let uploadedBytes = 0, uploads = 0;
    if (mode !== 'sync') {
      model = http.createServer(async (req, res) => {
        let size = 0;
        for await (const chunk of req) size += chunk.length;
        if (req.url === '/v1/files') {
          uploads++; uploadedBytes += size;
          res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ id: `file-${uploads}` })); return;
        }
        if (req.method === 'DELETE') { res.end('{"deleted":true}'); return; }
        res.writeHead(200, { 'Content-Type': 'text/event-stream' });
        const write = async event => { if (!res.write(`data: ${JSON.stringify(event)}\n\n`)) await once(res, 'drain'); };
        if (mode !== 'ai') {
          await write({ type: 'response.completed', response: { status: 'completed', output: [
            { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: '{"text":"合成图片分析"}' }] },
          ] } });
          res.end(); return;
        }
        await write({ choices: [{ index: 0, delta: { role: 'assistant' } }] });
        const text = JSON.stringify(output);
        for (let i = 0; i < text.length; i += 32)
        {
          await write({ choices: [{ index: 0, delta: { content: text.slice(i, i + 32) } }] });
          if (i % 1024 === 0) await delay(2);
        }
        await write({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
        res.end('data: [DONE]\n\n');
      }).listen(0, '127.0.0.1');
      await once(model, 'listening');
    }
    const attachment = mode === 'ai' ? await saveAttachment(repo, 'm', 'synthetic.txt', Buffer.from(body), 'text/plain')
      : mode === 'pdf' ? await saveAttachment(repo, 'm', 'synthetic.pdf', syntheticPDF(20), 'application/pdf') : null;
    const images = mode === 'vision' ? [{ name: 'synthetic.png', contentType: 'image/png', buffer: Buffer.alloc(20 * 1024 * 1024, 7) }] : [];
    if (attachment) repo.put('message', { ...repo.get('message', 'm'), attachmentIds: [attachment.id] });
    global.gc?.();
    const memoryBefore = process.memoryUsage();
    const cpu = process.cpuUsage(), start = performance.now();
    const lag = monitorEventLoopDelay({ resolution: 10 }); lag.enable();
    let peakRSS = memoryBefore.rss, peakHeap = memoryBefore.heapUsed, previews = 0, streamedBytes = 0;
    const sample = () => { const m = process.memoryUsage(); peakRSS = Math.max(peakRSS, m.rss); peakHeap = Math.max(peakHeap, m.heapUsed); };
    const sampler = setInterval(sample, 10);
    let verified;
    if (mode === 'sync') {
      const client = { mailbox: {}, async connect() {}, async logout() {}, close() {},
        async list() { return [{ path: 'Sent', specialUse: '\\Sent' }]; },
        async getMailboxLock() { this.mailbox = { path: 'Sent', uidValidity: '10', exists: 2600 }; return { release() {} }; },
        async status() { return { messages: 2600, uidValidity: '10' }; },
        async search() { return Array.from({ length: 2600 }, (_, i) => i + 1); },
        async *fetch(uids) { for (const uid of uids) yield { uid, flags: new Set(), size: 9000 }; },
        async fetchOne(uid) { return { source: Buffer.from(`From: sender@example.test\r\nTo: me@example.test\r\nSubject: New ${uid}\r\nMessage-ID: <new-${uid}@example.test>\r\nContent-Type: text/plain\r\n\r\n${body}`) }; },
      };
      const result = await syncAccount(repo, account, 'synthetic', { clientFactory: () => client, folder: 'sent', downloadBudgetMs: 600000 });
      assert.equal(result.count, 200);
      assert.equal(repo.db.prepare("SELECT COUNT(*) AS n FROM records WHERE kind='message'").get().n, 2600);
      verified = { cached: 2400, downloaded: result.count };
    } else if (mode === 'ai') {
      const config = { apiProtocol: 'openai-completions', providerId: 'local', model: 'synthetic-model',
        baseURL: `http://127.0.0.1:${model.address().port}/v1`, timeout: 120, effort: 'off', enabled: true };
      const workloads = [
        ['summary', { overview: '合成概要。'.repeat(3000), points: ['合成要点'], todos: [], keyInfo: [], nextSteps: [] }],
        ['translate', { segments: Array.from({ length: 300 }, (_, i) => ({ id: String(i), text: `译文段落 ${i}。`.repeat(20) })) }],
        ['attachment', { text: '## 合成附件分析\n\n'.repeat(12000) }],
      ];
      for (let round = 0; round < rounds; round++) for (const [task, result] of workloads) {
        output = result;
        const job = await runAgent(repo, { task, messageId: 'm', attachmentId: attachment.id, config, apiKey: '',
          onProgress: event => { previews++; streamedBytes += Buffer.byteLength(JSON.stringify(event)); sample(); } });
        assert.equal(job.status, 'completed');
      }
      assert.ok(repo.get('message', 'm').summary);
      assert.ok(repo.get('message', 'm').translationHTML.includes('译文段落'));
      assert.equal(repo.get('attachment', attachment.id).analysis, workloads[2][1].text);
      const compactJobs = repo.jobHeaders ? repo.jobHeaders() : repo.list('job');
      verified = { completed: repo.list('job').length, tasks: workloads.map(([task]) => task), previews, streamedBytes,
        compactJobBytes: Buffer.byteLength(JSON.stringify(compactJobs)) };
    } else {
      const config = { ...DEFAULT_AI, baseURL: `http://127.0.0.1:${model.address().port}/v1`, timeout: 120 };
      for (let round = 0; round < 3; round++) {
        const result = mode === 'vision'
          ? await completion(config, '', 'attachment', { name: 'synthetic' }, images)
          : (await runAgent(repo, { task: 'attachment', messageId: 'm', attachmentId: attachment.id, config, apiKey: '' })).result;
        assert.equal(result.text, '合成图片分析'); sample();
      }
      assert.equal(uploads, mode === 'vision' ? 3 : 60);
      verified = { completed: 3, uploads, uploadedBytes, ...(mode === 'pdf' ? { pagesPerTask: 20 } : { imageMiB: 20 }) };
    }
    sample(); peakRSS = Math.max(peakRSS, process.resourceUsage().maxRSS * 1024);
    clearInterval(sampler); lag.disable();
    const elapsedMs = performance.now() - start, usage = process.cpuUsage(cpu);
    global.gc?.(); await delay(50); global.gc?.();
    const retained = process.memoryUsage();
    const mib = value => Number((value / 1048576).toFixed(2));
    console.log(JSON.stringify({ node: process.versions.node, mode, elapsedMs: Math.round(elapsedMs),
      cpuMs: Math.round((usage.user + usage.system) / 1000), eventLoopP99Ms: Number((lag.percentile(99) / 1e6).toFixed(2)),
      rssBeforeMiB: mib(memoryBefore.rss), peakRSSMiB: mib(peakRSS), rssAfterGCMiB: mib(retained.rss),
      heapBeforeMiB: mib(memoryBefore.heapUsed), peakHeapMiB: mib(peakHeap), heapAfterGCMiB: mib(retained.heapUsed), verified }, null, 2));
  } finally {
    if (model) { model.closeAllConnections(); await new Promise(resolve => model.close(resolve)); }
    repo.close(); await rm(directory, { recursive: true, force: true });
  }
}
