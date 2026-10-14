import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { completion } from '../src/responses.js';
import { runAgent } from '../src/agent.js';
import { saveAttachment, modelAttachment } from '../src/attachments.js';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';
import { DEFAULT_AI, DEFAULT_PROMPTS } from '../src/ai-settings.js';
import { aiConfig } from '../src/validation.js';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6ioAAAAASUVORK5CYII=', 'base64');
const sessionToken = 'test-responses-session-0123456789';

async function provider(t, options = {}) {
  const requests = [], uploads = [], deleted = [];
  const server = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json');
    if (req.method === 'GET' && req.url === '/v1/models') {
      res.end(JSON.stringify({ data: [{ id: 'deepseek-flash' }, { id: 'deepseek-v4-pro' }] }));
      return;
    }
    if (req.method === 'DELETE') {
      deleted.push(req.url);
      res.end(JSON.stringify({ deleted: true }));
      return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const buffer = Buffer.concat(chunks);
    if (req.url === '/v1/files') {
      const form = await new Request('http://localhost/files', {
        method: 'POST', headers: req.headers, body: buffer,
      }).formData();
      const file = form.get('file');
      uploads.push({
        purpose: form.get('purpose'), anchor: form.get('expires_after[anchor]'),
        seconds: form.get('expires_after[seconds]'), name: file.name,
        bytes: Buffer.from(await file.arrayBuffer()), authorization: req.headers.authorization,
      });
      if (options.failUploadAt === uploads.length) {
        res.writeHead(500); res.end('{}'); return;
      }
      res.end(JSON.stringify({ id: `file-api-${uploads.length}` }));
      return;
    }
    assert.equal(req.url, '/v1/responses');
    const body = JSON.parse(buffer);
    requests.push(body);
    if (options.delay) await delay(options.delay);
    if (options.httpStatus) res.writeHead(options.httpStatus);
    const text = options.raw ?? JSON.stringify(options.result ?? { text: '图表显示项目已完成' });
    res.end(JSON.stringify({
      status: options.status ?? 'completed',
      output: [
        { type: 'reasoning', content: [{ type: 'reasoning_text', text: 'This is not the result JSON.' }] },
        { type: 'message', role: 'assistant', content: [
          { type: 'output_text', text: text.slice(0, 12) },
          { type: 'output_text', text: text.slice(12) },
        ] },
      ],
    }));
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return { requests, uploads, deleted, config: {
    ...DEFAULT_AI, baseURL: `http://127.0.0.1:${server.address().port}/v1`, timeout: 10,
  } };
}

async function repository(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-responses-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return repo;
}

function blankPDF(pages = 1) {
  const contentId = 3 + pages;
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Kids [${Array.from({ length: pages }, (_, i) => `${i + 3} 0 R`).join(' ')}] /Count ${pages} >>`,
    ...Array.from({ length: pages }, () => `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents ${contentId} 0 R >>`),
    '<< /Length 0 >>\nstream\n\nendstream',
  ];
  let result = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 0; i < objects.length; i++) {
    offsets.push(Buffer.byteLength(result));
    result += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xref = Buffer.byteLength(result);
  result += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  result += offsets.slice(1).map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`).join('');
  result += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(result);
}

test('Responses sends all three effort levels without sampling or token limits and ignores reasoning output', async (t) => {
  const ai = await provider(t, { result: { subject: '主题', body: '正文' } });
  for (const effort of ['low', 'high', 'max']) {
    const result = await completion({ ...ai.config, effort, temperature: 2, maxTokens: 999 }, '', 'compose', { request: '写信' });
    assert.equal(result.body, '正文');
    const request = ai.requests.at(-1);
    assert.deepEqual(request.reasoning, { effort });
    assert.deepEqual(request.text, { format: { type: 'json_object' } });
    for (const field of ['temperature', 'max_tokens', 'max_completion_tokens', 'max_output_tokens'])
      assert.equal(Object.hasOwn(request, field), false);
    assert.match(request.instructions, /待分析的数据/);
    assert.equal(request.input[0].role, 'user');
  }
  assert.throws(() => aiConfig({ ...ai.config, effort: 'medium' }), /思考等级/);
});

test('legacy settings migrate while preserving custom prompts and providers; blank prompts restore defaults', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-migration-'));
  const repo = new Repository(directory);
  repo.put('settings', { id: 'settings', preferences: { signature: '保留签名' }, ai: {
    baseURL: 'https://custom.example/v1', model: 'custom-model', timeout: 180,
    temperature: 0.3, maxTokens: 4096, tokenParameter: 'max_tokens', prompts: { reply: '使用正式语气', summary: '' },
  } });
  repo.close();
  const app = await startServer({ directory, token: sessionToken, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const saved = app.repo.get('settings', 'settings');
  assert.equal(saved.ai.baseURL, 'https://custom.example/v1');
  assert.equal(saved.ai.model, 'custom-model');
  assert.equal(saved.ai.effort, 'high');
  assert.equal(saved.ai.timeout, 180);
  assert.equal(saved.ai.prompts.reply, '使用正式语气');
  assert.equal(saved.ai.prompts.summary, DEFAULT_PROMPTS.summary);
  assert.equal(saved.preferences.signature, '保留签名');
  assert.equal(saved.ai.temperature, undefined);
  assert.equal(saved.ai.maxTokens, undefined);
  assert.equal(saved.ai.tokenParameter, undefined);
  const response = await fetch(`http://127.0.0.1:${app.port}/settings`, {
    method: 'POST', headers: { 'X-Boxmail-Token': sessionToken, 'Content-Type': 'application/json' },
    body: JSON.stringify({ ai: { effort: 'max', prompts: { reply: ' ' } } }),
  });
  assert.equal(response.status, 200);
  assert.equal(app.repo.get('settings', 'settings').ai.prompts.reply, DEFAULT_PROMPTS.reply);
  assert.ok(Object.values(app.repo.get('settings', 'settings').ai.prompts).every((prompt) => prompt.trim()));
});

test('custom system prompt is used with the required result contract', async (t) => {
  const ai = await provider(t);
  await completion({ ...ai.config, prompts: { attachment: '重点分析发票金额' } }, '', 'attachment', { name: '发票' });
  assert.match(ai.requests[0].instructions, /重点分析发票金额/);
  assert.match(ai.requests[0].instructions, /"text"/);
});

test('image attachments without extracted text upload through Files, persist analysis and clean up', async (t) => {
  const repo = await repository(t);
  const attachment = await saveAttachment(repo, 'm1', '进度图.png', png, 'image/png');
  assert.equal(attachment.text, '');
  const ai = await provider(t);
  const job = await runAgent(repo, { task: 'attachment', attachmentId: attachment.id, config: ai.config, apiKey: 'test-key' });
  assert.equal(job.status, 'completed');
  assert.equal(repo.get('attachment', attachment.id).analysis, '图表显示项目已完成');
  assert.equal(ai.uploads[0].name, '进度图.png');
  assert.deepEqual(ai.uploads[0].bytes, png);
  assert.equal(ai.uploads[0].purpose, 'user_data');
  assert.equal(ai.uploads[0].anchor, 'created_at');
  assert.equal(ai.uploads[0].seconds, '3600');
  assert.equal(ai.uploads[0].authorization, 'Bearer test-key');
  assert.deepEqual(ai.requests[0].input[0].content[1], { type: 'input_image', file_id: 'file-api-1' });
  assert.deepEqual(ai.deleted, ['/v1/files/file-api-1']);
});

test('PDF with no readable text renders every page for model understanding without OCR', async (t) => {
  const repo = await repository(t);
  const attachment = await saveAttachment(repo, 'm1', '扫描件.pdf', blankPDF(2), 'application/pdf');
  repo.put('attachment', { ...attachment, text: '' });
  const ai = await provider(t);
  const job = await runAgent(repo, { task: 'attachment', attachmentId: attachment.id, config: ai.config });
  assert.equal(job.status, 'completed');
  assert.equal(ai.uploads.length, 2);
  assert.equal(ai.uploads[0].name, '扫描件-page-1.png');
  assert.equal(ai.uploads[1].name, '扫描件-page-2.png');
  assert.deepEqual([...ai.uploads[0].bytes.subarray(0, 8)], [137, 80, 78, 71, 13, 10, 26, 10]);
  assert.equal(JSON.parse(ai.requests[0].input[0].content[0].text).pages, 2);
  assert.equal(ai.requests[0].input[0].content.filter((part) => part.type === 'input_image').length, 2);
  assert.equal(ai.deleted.length, 2);
});

test('oversized PDF is rejected instead of silently analyzing a partial document', async (t) => {
  const repo = await repository(t);
  const attachment = await saveAttachment(repo, 'm1', 'long.pdf', blankPDF(21), 'application/pdf');
  await assert.rejects(modelAttachment(repo, attachment.id), /21.*20/);
});

test('document text is understood without using unsupported file input', async (t) => {
  const repo = await repository(t);
  const attachment = await saveAttachment(repo, 'm1', '说明.txt', Buffer.from('交付时间：周五'), 'text/plain');
  const ai = await provider(t);
  await runAgent(repo, { task: 'attachment', attachmentId: attachment.id, config: ai.config });
  assert.equal(ai.uploads.length, 0);
  assert.match(ai.requests[0].input[0].content[0].text, /交付时间/);
  assert.equal(ai.requests[0].input[0].content.length, 1);
});

test('failed upload and failed Responses both clean up prior uploaded files', async (t) => {
  const image = { name: 'image.png', buffer: png, contentType: 'image/png' };
  const uploadFailure = await provider(t, { failUploadAt: 2 });
  await assert.rejects(completion(uploadFailure.config, '', 'attachment', {}, [image, image]), /上传失败/);
  assert.deepEqual(uploadFailure.deleted, ['/v1/files/file-api-1']);
  const responseFailure = await provider(t, { httpStatus: 500 });
  await assert.rejects(completion(responseFailure.config, '', 'attachment', {}, [image]), /HTTP 500/);
  assert.deepEqual(responseFailure.deleted, ['/v1/files/file-api-1']);
});

test('incomplete output does not replace stored attachment analysis', async (t) => {
  const repo = await repository(t);
  const attachment = await saveAttachment(repo, 'm1', 'note.txt', Buffer.from('内容'));
  repo.put('attachment', { ...attachment, analysis: '已有结果' });
  const ai = await provider(t, { status: 'incomplete' });
  await assert.rejects(runAgent(repo, { task: 'attachment', attachmentId: attachment.id, config: ai.config }), /未完成/);
  assert.equal(repo.get('attachment', attachment.id).analysis, '已有结果');
  assert.equal(repo.list('job')[0].status, 'failed');
});

test('DeepSeek text-only model rejects image tasks before uploading', async (t) => {
  const ai = await provider(t);
  await assert.rejects(completion({ ...ai.config, model: 'deepseek-v4-pro' }, '', 'attachment', {}, [
    { name: 'image.png', buffer: png, contentType: 'image/png' },
  ]), /deepseek-flash/);
  assert.equal(ai.uploads.length, 0);
});

test('timeout interrupts Responses and still cleans up uploaded files', async (t) => {
  const ai = await provider(t, { delay: 150 });
  const originalTimeout = AbortSignal.timeout.bind(AbortSignal);
  t.mock.method(AbortSignal, 'timeout', (milliseconds) => originalTimeout(milliseconds === 10000 ? 50 : milliseconds));
  await assert.rejects(completion(ai.config, '', 'attachment', {}, [
    { name: 'image.png', buffer: png, contentType: 'image/png' },
  ]), { name: 'TimeoutError' });
  assert.deepEqual(ai.deleted, ['/v1/files/file-api-1']);
});

test('connection test and model list routes use the configured Responses provider', async (t) => {
  const ai = await provider(t, { result: { subject: '连接成功', body: '连接成功' } });
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-ai-routes-'));
  const app = await startServer({ directory, token: sessionToken, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  async function request(route) {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: 'POST', headers: { 'X-Boxmail-Token': sessionToken, 'Content-Type': 'application/json' },
      body: JSON.stringify({ config: { ...ai.config, effort: 'max' }, apiKey: 'test-key' }),
    });
    assert.equal(response.status, 200);
    return response.json();
  }
  assert.deepEqual(await request('/ai/test'), { ok: true });
  assert.equal(ai.requests[0].reasoning.effort, 'max');
  assert.deepEqual(await request('/ai/models'), { models: ['deepseek-flash', 'deepseek-v4-pro'] });
});
