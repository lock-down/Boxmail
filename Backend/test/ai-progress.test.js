import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { aiConfig } from '../src/validation.js';
import { partialResult, progressText } from '../src/ai-progress.js';
import { translationDocument } from '../src/translation.js';
import { saveAttachment } from '../src/attachments.js';

const token = 'synthetic-stream-session-0123456789';
const mail = { id: 'm1', accountId: 'a1', folder: 'inbox', subject: 'Hello', sender: 'Test',
  senderEmail: 'test@example.com', to: 'me@example.com', cc: '', body: 'Hello', preview: 'Hello',
  date: '2026-10-23T00:00:00Z', category: '未分类', unread: false, starred: false, attachmentIds: [] };

async function provider(t, protocol, raw, { truncated = false } = {}) {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const server = http.createServer(async (req, res) => {
    for await (const _ of req) { /* drain */ }
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    const send = event => res.write(`${protocol === 'anthropic-messages' ? `event: ${event.type}\n` : ''}data: ${JSON.stringify(event)}\n\n`);
    const parts = [raw.slice(0, Math.floor(raw.length / 2)), raw.slice(Math.floor(raw.length / 2))];
    if (protocol === 'openai-responses') {
      send({ type: 'response.output_item.added', output_index: 0, item: { type: 'message', role: 'assistant', id: 'msg', content: [] } });
      send({ type: 'response.content_part.added', output_index: 0, content_index: 0, part: { type: 'output_text', text: '' } });
      send({ type: 'response.output_text.delta', output_index: 0, content_index: 0, delta: parts[0] });
      await gate;
      send({ type: 'response.output_text.delta', output_index: 0, content_index: 0, delta: parts[1] });
      send({ type: truncated ? 'response.incomplete' : 'response.completed', response: { status: truncated ? 'incomplete' : 'completed',
        output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: raw }] }] } });
    } else if (protocol === 'anthropic-messages') {
      send({ type: 'message_start', message: { id: 'msg', role: 'assistant', model: 'custom', usage: { input_tokens: 5, output_tokens: 0 } } });
      send({ type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
      send({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: parts[0] } });
      await gate;
      send({ type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: parts[1] } });
      send({ type: 'content_block_stop', index: 0 });
      send({ type: 'message_delta', delta: { stop_reason: truncated ? 'max_tokens' : 'end_turn' }, usage: { output_tokens: 20 } });
      send({ type: 'message_stop' });
    } else {
      send({ choices: [{ index: 0, delta: { role: 'assistant', reasoning_content: 'private reasoning', content: parts[0] } }] });
      await gate;
      send({ choices: [{ index: 0, delta: { content: parts[1] } }] });
      send({ choices: [{ index: 0, delta: {}, finish_reason: truncated ? 'length' : 'stop' }] });
    }
    res.end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => { release(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); });
  return { release, config: aiConfig({ providerId: 'custom', apiProtocol: protocol,
    baseURL: `http://127.0.0.1:${server.address().port}/v1`, model: 'custom', timeout: 10 }) };
}

async function app(t, config) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-stream-'));
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('account', { id: 'a1', email: 'me@example.com', isDemo: true });
  app.repo.put('message', mail);
  app.repo.put('settings', { ...app.repo.get('settings', 'settings'), ai: config });
  const base = `http://127.0.0.1:${app.port}`;
  return { ...app, base, request: (route, body) => fetch(base + route, { method: body ? 'POST' : 'GET',
    headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) }) };
}
async function subscription(t, app) {
  const controller = new AbortController();
  t.after(() => controller.abort());
  const response = await fetch(app.base + '/ai/events', { headers: { 'X-Boxmail-Token': token }, signal: controller.signal });
  assert.equal(response.headers.get('content-type'), 'text/event-stream; charset=utf-8');
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let pending = '';
  return async predicate => {
    while (true) {
      const end = pending.indexOf('\n\n');
      if (end < 0) { const chunk = await reader.read(); assert.equal(chunk.done, false); pending += chunk.value; continue; }
      const line = pending.slice(0, end); pending = pending.slice(end + 2);
      if (!line.startsWith('data: ')) continue;
      const event = JSON.parse(line.slice(6));
      if (predicate(event)) return event;
    }
  };
}

for (const protocol of ['openai-responses', 'openai-completions', 'anthropic-messages']) {
  test(protocol + ' displays genuine partial answers through authenticated SSE before committing results', { timeout: 15000 }, async t => {
    const ai = await provider(t, protocol, JSON.stringify({ overview: '正在逐步生成中文总结，结束前应当已经可见。', points: ['完整要点'], todos: [] }));
    const service = await app(t, ai.config);
    service.repo.put('message', { ...mail, summaryHidden: true });
    assert.equal((await fetch(service.base + '/ai/events')).status, 403);
    const next = await subscription(t, service);
    await next(event => event.type === 'snapshot');
    const request = service.request('/agent', { task: 'summary', messageId: 'm1', providerId: 'custom' });
    const { output } = await next(event => event.output?.text?.includes('正在逐步生成'));
    assert.equal(output.status, 'running');
    assert.equal(output.messageId, 'm1');
    assert.ok(!output.text.includes('private reasoning'));
    assert.ok(!output.text.includes('"overview"'));
    assert.equal(service.repo.get('message', 'm1').summary, undefined);
    const reconnect = await subscription(t, service);
    const snapshot = await reconnect(event => event.type === 'snapshot');
    assert.equal(snapshot.outputs[0].id, output.id);
    ai.release();
    assert.equal((await request).status, 200);
    assert.equal(service.repo.get('message', 'm1').summary.overview, '正在逐步生成中文总结，结束前应当已经可见。');
    assert.equal(service.repo.get('message', 'm1').summaryHidden, false);
  });
}

test('truncated output is visible in flight but never replaces a saved result', { timeout: 15000 }, async t => {
  const ai = await provider(t, 'openai-completions', JSON.stringify({ overview: '新的尚未完成的内容，请在输出结束之前显示。', points: ['部分内容'] }), { truncated: true });
  const service = await app(t, ai.config);
  service.repo.put('message', { ...mail, summary: { overview: '原有总结', points: ['原有总结'] } });
  const next = await subscription(t, service);
  const request = service.request('/agent', { task: 'summary', messageId: 'm1' });
  await next(event => event.output?.text?.includes('新的尚未'));
  ai.release();
  assert.equal((await request).status, 502);
  assert.equal(service.repo.get('message', 'm1').summary.overview, '原有总结');
  const failure = await next(event => event.output?.status === 'failed');
  assert.equal(failure.output.text, '');
});

test('translation changes only text in the original layout and escapes model markup', () => {
  const source = '<table style="background-color:#eee"><tr><td><a href="https://example.com">View model</a></td></tr></table><pre><code>ollama run model:cloud</code></pre><img src="data:image/png;base64,AAAA" alt="Brand"><p>Free until Thursday &amp; Friday</p>';
  const doc = translationDocument({ html: source, body: '' });
  assert.deepEqual(doc.segments.map(s => s.text), ['View model', 'Free until Thursday & Friday']);
  const partial = doc.render({ segments: [{ id: '0', text: '查看' }] });
  assert.match(partial.text, /查看/);
  assert.match(partial.text, /Free until Thursday/);
  const result = doc.render({ segments: [{ id: '0', text: '查看模型' }, { id: '1', text: '限时免费 <script>alert(1)</script>' }] }, true);
  assert.match(result.html, /href="https:\/\/example.com"/);
  assert.match(result.html, /<pre><code>ollama run model:cloud<\/code><\/pre>/);
  assert.match(result.html, /background-color:#eee/);
  assert.match(result.html, /data:image\/png;base64,AAAA/);
  assert.match(result.html, /&lt;script&gt;/);
  assert.ok(!result.html.includes('<script>'));
  assert.throws(() => doc.render({ segments: [{ id: '0', text: '漏段' }] }, true), /不完整/);
  assert.throws(() => doc.render({ segments: [{ id: '0', text: '重复' }, { id: '0', text: '重复' }] }, true), /不完整/);
});

test('plain translation preserves whitespace and late missing segments never overwrite earlier translations', { timeout: 15000 }, async t => {
  const doc = translationDocument({ body: '  Hello\n\nhttps://example.com\nFriday\n' });
  assert.deepEqual(doc.segments.map(s => s.text), ['  Hello', 'Friday']);
  assert.equal(doc.render({ segments: [{ id: '0', text: '你好' }, { id: '1', text: '星期五' }] }, true).text,
    '  你好\n\nhttps://example.com\n星期五\n');
  const ai = await provider(t, 'openai-completions', JSON.stringify({ segments: [{ id: '0', text: '只有第一段翻译，保留原格式。' }] }));
  const service = await app(t, ai.config);
  service.repo.put('message', { ...mail, html: '<p>Hello</p><p>Friday</p>', translation: '旧译文', translationHTML: '<p>旧译文</p>' });
  const next = await subscription(t, service);
  const request = service.request('/agent', { task: 'translate', messageId: 'm1' });
  const event = await next(event => event.output?.html?.includes('Friday'));
  assert.ok(event.output.html.startsWith('<p>'));
  ai.release();
  assert.equal((await request).status, 502);
  assert.equal(service.repo.get('message', 'm1').translationHTML, '<p>旧译文</p>');
});

test('all answer shapes can be read while strings and escape sequences are incomplete', () => {
  for (const task of ['compose', 'reply']) {
    assert.equal(progressText(task, partialResult('{"subject":"主题","body":"第一行\\n第二行')), '主题\n\n第一行\n第二行');
  }
  assert.equal(progressText('attachment', partialResult('{"text":"## 文档\\n内容')), '## 文档\n内容');
  assert.equal(progressText('classify', partialResult('{"items":[{"id":"m1","category":"工作项目","reason":"关于评审')), '工作项目：关于评审');
});

test('batch attachments stream each child answer before saving analysis', { timeout: 15000 }, async t => {
  const ai = await provider(t, 'openai-completions', JSON.stringify({ text: '## 附件结论\n逐步显示文件内容，结束之后才保存完整分析。' }));
  const service = await app(t, ai.config);
  const file = await saveAttachment(service.repo, 'm1', '说明.txt', Buffer.from('活动说明'), 'text/plain');
  service.repo.put('message', { ...mail, attachmentIds: [file.id] });
  const next = await subscription(t, service);
  const batch = await (await service.request('/messages/m1/attachments/analyze', {})).json();
  const event = await next(event => event.output?.text?.includes('附件结论'));
  assert.equal(event.output.parentJobId, batch.id);
  assert.equal(event.output.attachmentId, file.id);
  assert.ok(!service.repo.get('attachment', file.id).analysis);
  ai.release();
  await next(event => event.output?.status === 'completed');
  assert.match(service.repo.get('attachment', file.id).analysis, /完整分析/);
});

test('organizer streams in-flight reasons while keeping categories unchanged until approval', { timeout: 15000 }, async t => {
  const ai = await provider(t, 'openai-completions', JSON.stringify({ items: [{ id: 'm1', category: '订阅资讯',
    reason: '内容是产品更新，归入订阅资讯。分类建议仍需要用户审核后才能应用。' }] }));
  const service = await app(t, ai.config);
  const next = await subscription(t, service);
  const job = await (await service.request('/organize', { accountId: 'a1' })).json();
  const event = await next(event => event.output?.text?.includes('订阅资讯'));
  assert.equal(event.output.id, job.id);
  assert.equal(service.repo.get('message', 'm1').category, '未分类');
  ai.release();
  await next(event => event.output?.status === 'needsApproval');
  assert.equal(service.repo.get('job', job.id).result.items[0].category, '订阅资讯');
  assert.equal(service.repo.get('message', 'm1').category, '未分类');
});

test('translated HTML stays out of compact snapshots and preserves the source body', { timeout: 15000 }, async t => {
  const ai = await provider(t, 'openai-completions', JSON.stringify({ segments: [{ id: '0', text: '你好，保留排版' }] }));
  const service = await app(t, ai.config);
  service.repo.put('message', { ...mail, html: '<p style="font-weight:bold">Hello</p>' });
  ai.release();
  assert.equal((await service.request('/agent', { task: 'translate', messageId: 'm1' })).status, 200);
  const full = service.repo.get('message', 'm1');
  assert.equal(full.body, 'Hello');
  assert.equal(full.html, '<p style="font-weight:bold">Hello</p>');
  assert.match(full.translationHTML, /你好，保留排版/);
  assert.equal(service.repo.messageHeaders()[0].translationHTML, undefined);
  const snapshot = await (await service.request('/state?compact=1')).json();
  assert.equal(snapshot.messages[0].translationHTML, undefined);
});
