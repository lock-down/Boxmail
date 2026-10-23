import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { setTimeout as delay } from 'node:timers/promises';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { completion } from '../src/responses.js';
import { responseOutputEvents, responsesEvents, sse } from './helpers/ai-streams.js';
import { runAgent } from '../src/agent.js';
import { saveAttachment, modelAttachment } from '../src/attachments.js';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';
import { DEFAULT_AI, DEFAULT_PROMPTS } from '../src/ai-settings.js';
import { aiConfig } from '../src/validation.js';
import { presentationRendererPath } from '../src/presentations.js';

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6ioAAAAASUVORK5CYII=', 'base64');
const sessionToken = 'test-responses-session-0123456789';
const nativePresentations = process.platform === 'darwin' && existsSync(presentationRendererPath());
const presentationFixture = name => readFile(new URL(`fixtures/${name}`, import.meta.url));

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
    const payload = {
      status: options.status ?? 'completed',
      output: [
        { type: 'reasoning', content: [{ type: 'reasoning_text', text: 'This is not the result JSON.' }] },
        { type: 'message', role: 'assistant', content: [
          { type: 'output_text', text: text.slice(0, 12) },
          { type: 'output_text', text: text.slice(12) },
        ] },
      ],
    };
    if (options.events) {
      res.setHeader('Content-Type', 'text/event-stream');
      res.write(sse(responseOutputEvents(payload)));
      for (const chunk of options.events(payload)) { res.write(chunk); await delay(1); }
      if (options.disconnect) res.destroy();
      else res.end();
    } else if (!options.httpStatus && body.stream) {
      res.setHeader('Content-Type', 'text/event-stream'); res.end(sse(responsesEvents(payload)));
    } else res.end(JSON.stringify(payload));
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
  assert.throws(() => aiConfig({ ...ai.config, effort: 'unknown' }), /思考等级/);
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

test('PPTX and legacy PPT render every slide through the PDF image pipeline and preserve originals',
  { skip: !nativePresentations }, async t => {
  const repo = await repository(t);
  for (const name of ['two-slides.pptx', 'two-slides.ppt']) {
    const original = await presentationFixture(name);
    const attachment = await saveAttachment(repo, 'm1', name, original);
    assert.match(attachment.text, /第一页/);
    assert.match(attachment.text, /第二页/);
    const ai = await provider(t);
    await runAgent(repo, { task: 'attachment', attachmentId: attachment.id, config: ai.config });
    assert.equal(ai.uploads.length, 2);
    assert.deepEqual(ai.uploads.map(file => file.name), ['two-slides-page-1.png', 'two-slides-page-2.png']);
    assert.notDeepEqual(ai.uploads[0].bytes, ai.uploads[1].bytes);
    assert.ok(ai.uploads.every(file => file.bytes.length > 5000));
    const context = JSON.parse(ai.requests[0].input[0].content[0].text);
    assert.equal(context.inputKind, 'presentation');
    assert.equal(context.pages, 2);
    assert.match(context.text, /收入增长38%/);
    assert.equal(ai.deleted.length, 2);
    assert.deepEqual(await readFile(attachment.path), original);
  }
});

test('image-only PPTX remains analyzable without extracted text and old attachments gain searchable text',
  { skip: !nativePresentations }, async t => {
  const repo = await repository(t);
  const image = await saveAttachment(repo, 'm1', 'image-only.pptx', await presentationFixture('image-only.pptx'));
  assert.equal(image.text, '');
  const ai = await provider(t);
  await runAgent(repo, { task: 'attachment', attachmentId: image.id, config: ai.config });
  assert.equal(ai.uploads.length, 1);
  assert.ok(ai.uploads[0].bytes.length > 1000);
  const old = await saveAttachment(repo, 'm1', 'two-slides.pptx', await presentationFixture('two-slides.pptx'));
  repo.put('attachment', { ...old, text: '', parseError: '旧版本不支持' });
  await runAgent(repo, { task: 'attachment', attachmentId: old.id, config: ai.config });
  assert.match(repo.get('attachment', old.id).text, /第二页/);
  assert.equal(repo.get('attachment', old.id).parseError, '');
});

test('hidden PPTX slides are included in order without changing the original attachment',
  { skip: !nativePresentations }, async t => {
  const repo = await repository(t);
  const original = await presentationFixture('hidden-slide.pptx');
  const file = await saveAttachment(repo, 'm1', 'hidden-slide.pptx', original);
  const result = await modelAttachment(repo, file.id);
  assert.equal(result.pages, 2);
  assert.match(result.text, /第二页/);
  assert.deepEqual(await readFile(file.path), original);
});

test('PPT limits, corrupt files and cancellation fail before any model upload and retain existing analysis',
  { skip: !nativePresentations }, async t => {
  const repo = await repository(t);
  const long = await saveAttachment(repo, 'm1', 'long.PPTX', await presentationFixture('twenty-one-slides.pptx'));
  await assert.rejects(modelAttachment(repo, long.id), /21.*20/);
  const broken = await saveAttachment(repo, 'm1', 'broken.pptx', Buffer.from('not a presentation'));
  const ai = await provider(t);
  repo.put('attachment', { ...broken, analysis: '已有理解结果' });
  await assert.rejects(runAgent(repo, { task: 'attachment', attachmentId: broken.id, config: ai.config }), /PPT.*损坏/);
  assert.equal(repo.get('attachment', broken.id).analysis, '已有理解结果');
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(modelAttachment(repo, long.id, { signal: controller.signal }), { name: 'AbortError' });
  assert.equal(ai.uploads.length, 0);
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
  ]), /不支持图片输入/);
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

test('streamed Responses handles split UTF-8, CRLF, keepalives and only the completed assistant result', async t => {
  const ai = await provider(t, { result: { items: [{ id: 'm1', category: '订阅资讯', reason: '新闻' }] }, events: payload => {
    const bytes = Buffer.from(': keepalive\r\n\r\ndata: ' + JSON.stringify({ type: 'response.reasoning_text.delta', delta: '不能作为输出' }) + '\r\n\r\n'
      + 'event: response.completed\r\ndata: ' + JSON.stringify({ type: 'response.completed', response: payload }) + '\r\n\r\n');
    return Array.from({ length: Math.ceil(bytes.length / 7) }, (_, i) => bytes.subarray(i * 7, i * 7 + 7));
  } });
  const result = await completion(ai.config, '', 'classify', [{ id: 'm1' }], [], { stream: true });
  assert.equal(result.items[0].category, '订阅资讯');
  assert.equal(ai.requests[0].stream, true);
});

test('truncated, incomplete and malformed streams never become successful results', async t => {
  for (const [name, events, pattern] of [
    ['truncated', () => ['data: {"type":"response.output_text.delta","delta":"partial"}\n\n'], /连接中断/],
    ['incomplete', () => ['data: {"type":"response.incomplete","response":{"status":"incomplete"}}\n\n'], /未完成/],
    ['malformed', () => ['data: invalid-json\n\n'], /格式不正确/],
  ]) await t.test(name, async st => {
    const ai = await provider(st, { events });
    await assert.rejects(completion(ai.config, '', 'classify', [], [], { stream: true }), pattern);
  });
});

test('caller cancellation interrupts a model request without changing the configured timeout', async t => {
  const ai = await provider(t, { delay: 150 });
  const controller = new AbortController();
  const pending = completion(ai.config, '', 'classify', [], [], { signal: controller.signal, stream: true });
  await delay(20);
  controller.abort();
  await assert.rejects(pending, { name: 'AbortError' });
});

test('attachment analysis validates email ownership and records its source email and attachment', async t => {
  const repo = await repository(t);
  const a = await saveAttachment(repo, 'm1', '说明.txt', Buffer.from('交付：周五'));
  const mail = { id: 'm1', accountId: 'a1', subject: '评审资料', sender: '陈嘉禾', body: '请审核附件', attachmentIds: [a.id] };
  repo.put('message', mail);
  repo.put('message', { ...mail, id: 'm2', attachmentIds: [] });
  const ai = await provider(t);
  await assert.rejects(runAgent(repo, { task: 'attachment', messageId: 'm2', attachmentId: a.id, accountId: 'a1', config: ai.config }), /不属于当前邮件/);
  await assert.rejects(runAgent(repo, { task: 'summary', messageId: 'm1', accountId: 'a2', config: ai.config }), /不属于当前账户/);
  assert.equal(ai.requests.length, 0);
  const job = await runAgent(repo, { task: 'attachment', messageId: 'm1', accountId: 'a1', attachmentId: a.id, config: ai.config });
  assert.equal(job.messageId, 'm1');
  assert.equal(job.attachmentId, a.id);
  const context = JSON.parse(ai.requests[0].input[0].content[0].text);
  assert.equal(context.email.subject, '评审资料');
  assert.equal(context.email.body, '请审核附件');
});

test('translation persists on its source mail and a later failure preserves the prior translation', async t => {
  const repo = await repository(t);
  const mail = { id: 'm1', accountId: 'a1', subject: 'Hello', sender: 'Test', body: 'Hello', attachmentIds: [] };
  repo.put('message', mail);
  repo.put('message', { ...mail, id: 'm2' });
  const ai = await provider(t, { result: { segments: [{ id: '0', text: '你好' }] } });
  await runAgent(repo, { task: 'translate', messageId: 'm1', config: ai.config });
  assert.equal(repo.get('message', 'm1').translation, '你好');
  assert.equal(repo.get('message', 'm2').translation, undefined);
  const broken = await provider(t, { status: 'incomplete' });
  await assert.rejects(runAgent(repo, { task: 'translate', messageId: 'm1', config: broken.config }), /未完成/);
  assert.equal(repo.get('message', 'm1').translation, '你好');
});

test('eight long attachments retain valid context and complete a streamed mail summary', async t => {
  const repo = await repository(t);
  const ids = Array.from({ length: 8 }, (_, i) => `attachment-${i}`);
  for (const [i, id] of ids.entries()) repo.put('attachment', {
    id, messageId: 'bulk', name: `附件${i + 1}.docx`, text: '资料内容'.repeat(5000), analysis: '',
  });
  repo.put('message', { id: 'bulk', accountId: 'a1', sender: '演示发件人', subject: '多附件评审',
    body: '请核对全部八个附件。'.repeat(3500), attachmentIds: ids });
  const ai = await provider(t, { result: { points: ['八个文件需分别核对'], todos: [], keyInfo: [] },
    events: payload => ['data: ' + JSON.stringify({ type: 'response.completed', response: payload }) + '\n\n'] });
  const job = await runAgent(repo, { task: 'summary', messageId: 'bulk', config: ai.config });
  const request = ai.requests[0];
  assert.equal(request.stream, true);
  assert.ok(request.input[0].content[0].text.length > 100000);
  const context = JSON.parse(request.input[0].content[0].text);
  assert.equal(context.attachments.length, 8);
  assert.equal(context.attachments[7].name, '附件8.docx');
  assert.equal(context.attachments[7].textTruncated, true);
  assert.equal(job.status, 'completed');
  assert.deepEqual(repo.get('message', 'bulk').summary.points, ['八个文件需分别核对']);
});

test('a disconnected summary stream keeps the existing summary and returns a specific retry error', async t => {
  const repo = await repository(t);
  const summary = { points: ['原有总结'], todos: [], keyInfo: [] };
  repo.put('message', { id: 'bulk', accountId: 'a1', sender: '演示', subject: '资料', body: '正文', attachmentIds: [], summary });
  const ai = await provider(t, { disconnect: true,
    events: () => ['data: {"type":"response.output_text.delta","delta":"unfinished"}\n\n'] });
  await assert.rejects(runAgent(repo, { task: 'summary', messageId: 'bulk', config: ai.config }), /连接中断/);
  assert.deepEqual(repo.get('message', 'bulk').summary, summary);
  assert.equal(repo.list('job')[0].status, 'failed');
  assert.match(repo.list('job')[0].error, /连接中断/);
});
