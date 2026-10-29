import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { completion } from '../src/responses.js';
import { compatibleEvents, responsesEvents } from './helpers/ai-streams.js';
import { aiConfig, aiCredentialAccounts } from '../src/validation.js';
import { cachedModelCatalog, refreshModelCatalog } from '../src/model-catalog.js';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';
import { exportConfiguration, inspectConfiguration, importConfiguration } from '../src/configuration.js';
import { randomUUID } from 'node:crypto';

const protocols = ['openai-completions', 'anthropic-messages'];
const text = JSON.stringify({ subject: '主题', body: '邮件正文', text: '文档理解结果' });
const png = Buffer.from('synthetic-image-bytes');

async function provider(t, apiProtocol) {
  const requests = [];
  const state = { finish: apiProtocol === 'anthropic-messages' ? 'end_turn' : 'stop', text,
    events: null, modelPages: [{ data: [{ id: 'custom-model' }] }], status: 200 };
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (req.method === 'GET') {
      requests.push({ path: url.pathname, query: url.searchParams, headers: req.headers });
      const page = url.searchParams.has('after_id') ? 1 : 0;
      res.writeHead(state.status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(state.modelPages[page])); return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks));
    requests.push({ path: url.pathname, headers: req.headers, body });
    if (state.status === 200 && (state.events || body.stream)) {
      res.writeHead(state.status, { 'Content-Type': 'text/event-stream' });
      const events = state.events || (apiProtocol === 'openai-responses' ? responsesEvents({
        status: 'completed', output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: state.text }] }],
      }) : compatibleEvents(apiProtocol, state));
      for (const event of events) {
        const bytes = Buffer.from(`${event.type ? `event: ${event.type}\r\n` : ''}data: ${JSON.stringify(event)}\r\n\r\n`);
        res.write(bytes.subarray(0, bytes.length - 8));
        await new Promise(resolve => setImmediate(resolve));
        res.write(bytes.subarray(bytes.length - 8));
      }
      res.end(); return;
    }
    res.writeHead(state.status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(apiProtocol === 'anthropic-messages'
      ? { stop_reason: state.finish, content: [{ type: 'thinking', thinking: 'private reasoning' }, { type: 'text', text: state.text }] }
      : { choices: [{ finish_reason: state.finish, message: { role: 'assistant', content: state.text,
        reasoning_content: 'private reasoning' } }] }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  return { state, requests, config: { providerId: 'custom', apiProtocol,
    baseURL: `http://127.0.0.1:${server.address().port}/v1`, model: 'custom-model', models: [{ id: 'custom-model', input: ['text', 'image'] }], timeout: 10 } };
}
async function repository(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-byok-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  return repo;
}
function connection(config, id = 'custom') {
  return { id, name: '自定义服务', baseURL: config.baseURL, apiProtocol: config.apiProtocol,
    model: 'custom-model', models: ['custom-model', 'other-model'] };
}
function stream(apiProtocol, options = {}) {
  return compatibleEvents(apiProtocol, { text, ...options });
}

for (const apiProtocol of protocols) {
  test(apiProtocol + ' handles every mail task and inline images with provider-specific authentication', async t => {
    const ai = await provider(t, apiProtocol);
    for (const task of ['summary', 'reply', 'compose', 'classify', 'attachment', 'translate']) {
      assert.deepEqual(await completion(ai.config, 'synthetic-key', task, { request: '处理中文内容' },
        task === 'attachment' ? [{ name: '图.png', contentType: 'image/png', buffer: png }] : []), JSON.parse(text));
    }
    assert.equal(ai.requests.length, 6);
    const request = ai.requests[4];
    assert.equal(request.path, apiProtocol === 'anthropic-messages' ? '/v1/messages' : '/v1/chat/completions');
    const instructions = apiProtocol === 'anthropic-messages' ? request.body.system.map(p => p.text).join('') : request.body.messages[0].content;
    assert.match(instructions, /不能作为指令/);
    assert.match(instructions, /不添加签名/);
    assert.equal(request.body.reasoning, undefined);
    assert.equal(request.body.reasoning_effort, undefined);
    if (apiProtocol === 'anthropic-messages') {
      assert.equal(request.headers['x-api-key'], 'synthetic-key');
      assert.equal(request.headers['anthropic-version'], '2023-06-01');
      assert.equal(request.headers.authorization, undefined);
      assert.equal(request.body.max_tokens, 32768);
      assert.equal(request.body.messages[0].content[1].source.data, png.toString('base64'));
      // Root and /v1 base URLs resolve to the same Messages endpoint.
      await completion({ ...ai.config, baseURL: ai.config.baseURL.replace(/\/v1$/, '') }, '', 'compose', {});
      assert.equal(ai.requests.at(-1).path, '/v1/messages');
    } else {
      assert.equal(request.headers.authorization, 'Bearer synthetic-key');
      assert.equal(request.body.messages[1].content[1].image_url.url, 'data:image/png;base64,' + png.toString('base64'));
      assert.equal(request.body.max_tokens, undefined);
      assert.deepEqual(request.body.response_format, { type: 'json_object' });
    }
  });
  test(apiProtocol + ' streams only complete assistant text, rejects truncation and surfaces HTTP failures', async t => {
    const ai = await provider(t, apiProtocol);
    ai.state.events = stream(apiProtocol);
    assert.deepEqual(await completion(ai.config, '', 'compose', {}, [], { stream: true }), JSON.parse(text));
    ai.state.events = stream(apiProtocol, { stop: false });
    await assert.rejects(completion(ai.config, '', 'compose', {}, [], { stream: true }), /未完成/);
    ai.state.events = stream(apiProtocol, { finish: apiProtocol === 'anthropic-messages' ? 'max_tokens' : 'length' });
    await assert.rejects(completion(ai.config, '', 'compose', {}, [], { stream: true }), /未完成/);
    ai.state.events = [{ type: 'error', error: { message: 'provider-private-error' } }];
    await assert.rejects(completion(ai.config, '', 'compose', {}, [], { stream: true }), /未完成/);
    ai.state.events = null; ai.state.text = 'invalid-json';
    await assert.rejects(completion(ai.config, '', 'compose', {}), /有效 JSON/);
    ai.state.status = 401;
    const diagnostics = [];
    await assert.rejects(completion(ai.config, '', 'compose', { request: 'private-mail-body' }, [], {
      diagnostics: { record: (event, details) => diagnostics.push({ event, ...details }) },
    }), /HTTP 401/);
    assert.equal(diagnostics[0].event, 'ai.request.failed');
    assert.equal(diagnostics[0].upstreamStatus, 401);
    assert.equal(diagnostics[0].protocol, apiProtocol);
    assert.equal(JSON.stringify(diagnostics).includes('private-mail-body'), false);
    await assert.rejects(completion({ ...ai.config, enabled: false }, '', 'compose', {}), /启用 AI/);
  });
}

test('model discovery isolates provider identities and protocols and handles Anthropic pagination atomically', async t => {
  const ai = await provider(t, 'anthropic-messages'), repo = await repository(t);
  ai.state.modelPages = [{ data: [{ id: 'model-a' }], has_more: true, last_id: 'model-a' },
    { data: [{ id: 'model-b' }], has_more: false, last_id: 'model-b' }];
  assert.deepEqual(await refreshModelCatalog(repo, ai.config, 'catalog-key'), { models: ['model-a', 'model-b'] });
  assert.equal(ai.requests[1].query.get('after_id'), 'model-a');
  assert.equal(ai.requests[0].headers['x-api-key'], 'catalog-key');
  assert.deepEqual(cachedModelCatalog(repo, { ...ai.config, providerId: 'other' }), { models: [] });
  assert.deepEqual(cachedModelCatalog(repo, { ...ai.config, apiProtocol: 'openai-completions' }), { models: [] });
  ai.state.modelPages[1].has_more = true;
  await assert.rejects(refreshModelCatalog(repo, ai.config, 'catalog-key'), /分页格式/);
  assert.deepEqual(cachedModelCatalog(repo, ai.config), { models: ['model-a', 'model-b'] });
  assert.equal(JSON.stringify(repo.list('modelCatalog')).includes('catalog-key'), false);
});

test('multiple providers survive settings saves, restart and configuration imports with optional preserved credentials', async t => {
  const repo = await repository(t);
  let app = await startServer({ directory: repo.directory, token: 'byok-test-token-long-enough-012345', demo: false });
  t.after(() => app.close());
  const config = { providerId: 'gateway', providers: [connection({ baseURL: 'https://gateway.example/v1',
    apiProtocol: 'openai-completions' }, 'gateway'), connection({ baseURL: 'https://api.anthropic.com',
    apiProtocol: 'anthropic-messages' }, 'claude')] };
  const request = async ai => {
    const response = await fetch(`http://127.0.0.1:${app.port}/settings`, { method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Boxmail-Token': 'byok-test-token-long-enough-012345' },
      body: JSON.stringify({ ai }) });
    assert.equal(response.status, 200);
    return (await response.json()).ai;
  };
  await request(config);
  const rejected = await fetch(`http://127.0.0.1:${app.port}/agent`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Boxmail-Token': 'byok-test-token-long-enough-012345' },
    body: JSON.stringify({ task: 'compose', providerId: 'claude', apiKey: 'wrong-provider-key' }) });
  assert.equal(rejected.status, 409);
  assert.match((await rejected.json()).error, /服务商已切换/);
  assert.equal(app.repo.list('job').length, 0);
  const edited = await request({ model: 'manual-outside-catalog' });
  assert.equal(edited.providers[0].model, 'manual-outside-catalog');
  await app.close();
  app = await startServer({ directory: repo.directory, token: 'byok-test-token-long-enough-012345', demo: false });
  assert.equal(app.repo.get('settings', 'settings').ai.providers.length, 2);
  assert.equal(app.repo.get('settings', 'settings').ai.model, 'manual-outside-catalog');
  const configuration = exportConfiguration(app.repo), plan = inspectConfiguration(app.repo, configuration);
  const credentialReferences = Object.fromEntries(aiCredentialAccounts(configuration.settings.ai)
    .map(key => [key, 'configuration-' + randomUUID()]));
  const body = { configuration, ...plan, credentialReferences, approved: true };
  const incomplete = { ...credentialReferences }; delete incomplete['ai-provider-claude'];
  importConfiguration(app.repo, { ...body, credentialReferences: incomplete });
  assert.deepEqual(app.repo.get('settings', 'settings').credentialReferences, incomplete);
  importConfiguration(app.repo, { ...body, ...inspectConfiguration(app.repo, configuration) });
  assert.deepEqual(app.repo.get('settings', 'settings').credentialReferences, credentialReferences);
  assert.equal(configuration.settings.ai.providers[1].apiProtocol, 'anthropic-messages');
});

test('HTTP compose uses the selected BYOK provider without requiring a source message', async t => {
  const ai = await provider(t, 'openai-completions'), repo = await repository(t);
  const token = 'byok-compose-token-long-enough-012345';
  const app = await startServer({ directory: repo.directory, token, demo: false });
  t.after(() => app.close());
  const settings = app.repo.get('settings', 'settings');
  app.repo.put('settings', { ...settings, ai: aiConfig({ providerId: 'custom', providers: [connection(ai.config)] }) });
  const response = await fetch(`http://127.0.0.1:${app.port}/agent`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Boxmail-Token': token },
    body: JSON.stringify({ task: 'compose', providerId: 'custom', apiKey: 'compose-key', prompt: '写一封邮件' }) });
  assert.equal(response.status, 200);
  const job = await response.json();
  assert.equal(job.status, 'completed');
  assert.equal(job.result.body, '邮件正文');
  assert.equal(ai.requests[0].headers.authorization, 'Bearer compose-key');
  assert.equal(JSON.stringify(app.repo.list('job')).includes('compose-key'), false);
});

for (const apiProtocol of ['openai-responses', ...protocols]) {
  test(apiProtocol + ' applies per-model caps and reasoning wire mappings through pi-ai', async t => {
    const ai = await provider(t, apiProtocol);
    const descriptor = { id: 'custom-model', name: '工作模型', contextWindow: 256000, maxTokens: 12000,
      input: ['text'], reasoningEfforts: { off: null, low: 'low', high: 'max' },
      compat: { forceAdaptiveThinking: true, maxTokensField: 'max_completion_tokens' } };
    const config = { ...ai.config, models: [descriptor], effort: 'high' };
    await completion(config, 'synthetic-key', 'compose', {});
    let body = ai.requests.at(-1).body;
    if (apiProtocol === 'openai-responses') {
      assert.equal(body.max_output_tokens, 12000);
      assert.equal(body.reasoning.effort, 'max');
    } else if (apiProtocol === 'openai-completions') {
      assert.equal(body.max_completion_tokens, 12000);
      assert.equal(body.max_tokens, undefined);
      assert.equal(body.reasoning_effort, 'max');
      descriptor.compat.maxTokensField = 'max_tokens';
      await completion(config, '', 'compose', {});
      assert.equal(ai.requests.at(-1).body.max_tokens, 12000);
      assert.equal(ai.requests.at(-1).body.max_completion_tokens, undefined);
    } else {
      assert.equal(body.max_tokens, 12000);
      assert.equal(body.thinking.type, 'adaptive');
      assert.equal(body.output_config.effort, 'max');
      descriptor.compat.forceAdaptiveThinking = false;
      await completion(config, '', 'compose', {});
      body = ai.requests.at(-1).body;
      assert.equal(body.thinking.type, 'enabled');
      assert.equal(body.thinking.budget_tokens, 12000 - 1024);
      assert.equal(body.output_config, undefined);
    }
    await completion({ ...config, effort: 'off' }, '', 'compose', {});
    body = ai.requests.at(-1).body;
    assert.equal(body.reasoning, undefined);
    assert.equal(body.reasoning_effort, undefined);
    assert.equal(body.thinking, undefined);
    descriptor.reasoningEfforts.off = 'none';
    if (apiProtocol !== 'anthropic-messages') {
      await completion({ ...config, effort: 'off' }, '', 'compose', {});
      const off = ai.requests.at(-1).body;
      assert.equal(apiProtocol === 'openai-responses' ? off.reasoning.effort : off.reasoning_effort, 'none');
    }
    const before = ai.requests.length;
    await assert.rejects(completion({ ...config, effort: 'medium' }, '', 'compose', {}), /未提供 medium/);
    await assert.rejects(completion(config, '', 'attachment', {}, [{ name: 'x.png', contentType: 'image/png', buffer: png }]), /不支持图片输入/);
    await assert.rejects(completion({ ...config, models: [{ ...descriptor, contextWindow: 100, maxTokens: 50 }] }, '', 'compose', {}), /上下文窗口/);
    assert.equal(ai.requests.length, before);
    descriptor.reasoningEfforts = false;
    await completion(config, '', 'compose', {});
    body = ai.requests.at(-1).body;
    assert.equal(body.reasoning, undefined); assert.equal(body.reasoning_effort, undefined); assert.equal(body.thinking, undefined);
    ai.state.status = 503;
    const attempts = ai.requests.length;
    await assert.rejects(completion(config, '', 'compose', {}), /HTTP 503/);
    assert.equal(ai.requests.length, attempts + 1, 'an adapter call must not silently retry a paid request');
  });
}

test('model discovery retains declared metadata and caches it without modifying saved model overrides', async t => {
  const ai = await provider(t, 'anthropic-messages'), repo = await repository(t);
  ai.state.modelPages = [{ data: [{ id: 'model-a', display_name: '模型 A', context_window: 200000, max_output_tokens: 32000,
    input_modalities: ['text', 'image'] }], has_more: true, last_id: 'model-a' },
    { data: [{ id: 'model-b', name: '模型 B', limit: { context: 256000, output: 16000 } }], has_more: false }];
  const result = await refreshModelCatalog(repo, ai.config, 'catalog-key');
  assert.deepEqual(result.details, [{ id: 'model-a', name: '模型 A', contextWindow: 200000, maxTokens: 32000, input: ['text', 'image'] },
    { id: 'model-b', name: '模型 B', contextWindow: 256000, maxTokens: 16000 }]);
  assert.equal(result.details[1].input, undefined, 'discovery must not invent vision or reasoning support');
  assert.deepEqual(cachedModelCatalog(repo, ai.config), result);
  ai.state.modelPages[1].data = [{ id: 'invalid', context_window: 1000, max_tokens: 2000 }];
  await assert.rejects(refreshModelCatalog(repo, ai.config, 'catalog-key'), /列表格式/);
  assert.deepEqual(cachedModelCatalog(repo, ai.config), result);
  ai.state.modelPages = [{ models: { 'gateway-model': { displayName: '网关模型', limit: { context: 128000, output: 16000 } } } }];
  const mapped = await refreshModelCatalog(repo, ai.config, 'catalog-key');
  assert.deepEqual(mapped.details, [{ id: 'gateway-model', name: '网关模型', contextWindow: 128000, maxTokens: 16000 }]);
});

test('legacy ID catalogs migrate to rich descriptors and invalid model metadata is rejected', () => {
  const provider = connection({ baseURL: 'https://example.com/v1', apiProtocol: 'openai-completions' });
  const normalized = aiConfig({ providerId: provider.id, providers: [provider] });
  assert.deepEqual(normalized.providers[0].models, [{ id: 'custom-model' }, { id: 'other-model' }]);
  const invalid = [{ id: '' }, { id: 'a', maxTokens: 0 }, { id: 'a', contextWindow: 1.5 },
    { id: 'a', contextWindow: 2000, maxTokens: 3000 }, { id: 'a', input: ['audio'] },
    { id: 'a', reasoningEfforts: {} }, { id: 'a', reasoningEfforts: { off: null } },
    { id: 'a', reasoningEfforts: { high: null } }, { id: 'a', reasoningEfforts: { high: '' } },
    { id: 'a', compat: { maxTokensField: 'unknown' } }];
  for (const model of invalid) assert.throws(() => aiConfig({ providerId: provider.id, providers: [{ ...provider, models: [model] }] }));
  assert.throws(() => aiConfig({ providerId: provider.id, providers: [{ ...provider, models: ['same', 'same'] }] }), /不能重复/);
});

test('keyless local SDK routes never inherit environment API keys or tenant headers', async t => {
  const names = ['OPENAI_API_KEY', 'OPENAI_ORG_ID', 'OPENAI_PROJECT_ID', 'ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN'];
  const previous = Object.fromEntries(names.map(name => [name, process.env[name]]));
  try {
    for (const name of names) process.env[name] = 'ambient-value-that-must-not-be-sent';
    for (const protocol of ['openai-responses', ...protocols]) {
      const ai = await provider(t, protocol);
      await completion(ai.config, '', 'compose', {});
      await refreshModelCatalog(await repository(t), ai.config, '');
      for (const request of ai.requests) {
        for (const name of ['authorization', 'x-api-key', 'openai-organization', 'openai-project']) assert.equal(request.headers[name], undefined);
      }
    }
  } finally {
    for (const name of names) { if (previous[name] === undefined) delete process.env[name]; else process.env[name] = previous[name]; }
  }
});

test('pi-ai response limits also cover terminal-only output and private thinking blocks', async t => {
  for (const apiProtocol of ['openai-responses', ...protocols]) {
    const ai = await provider(t, apiProtocol);
    ai.state.text = JSON.stringify({ text: 'a'.repeat(2_000_001) });
    await assert.rejects(completion(ai.config, '', 'compose', {}), /响应过长/);
    if (apiProtocol === 'anthropic-messages') {
      ai.state.events = compatibleEvents(apiProtocol, { text });
      ai.state.events[1].content_block.thinking = 'a'.repeat(2_000_001);
      await assert.rejects(completion(ai.config, '', 'compose', {}), /响应过长/);
    }
  }
});

test('pi-ai Responses accepts terminal-only assistant text and never treats thinking or foreign roles as the answer', async t => {
  const ai = await provider(t, 'openai-responses');
  const response = { status: 'completed', output: [
    { type: 'reasoning', content: [{ type: 'reasoning_text', text: 'not answer JSON' }] },
    { type: 'message', role: 'assistant', content: [{ type: 'output_text', text }] },
  ] };
  ai.state.events = [{ type: 'response.completed', response }];
  assert.deepEqual(await completion(ai.config, '', 'compose', {}), JSON.parse(text));
  response.output[1].role = 'user';
  await assert.rejects(completion(ai.config, '', 'compose', {}), /返回内容为空/);
  ai.state.events = [{ type: 'response.output_item.added', output_index: 0,
    item: { type: 'message', role: 'user', content: [{ type: 'output_text', text }] } },
  { type: 'response.completed', response }];
  await assert.rejects(completion(ai.config, '', 'compose', {}), /未完成/);
});

test('custom Responses vision uses pi-ai inline images without requiring a Files endpoint', async t => {
  const ai = await provider(t, 'openai-responses');
  assert.deepEqual(await completion(ai.config, 'synthetic-key', 'attachment', {}, [
    { name: 'image.png', buffer: png, contentType: 'image/png' },
  ]), JSON.parse(text));
  assert.equal(ai.requests.length, 1);
  assert.equal(ai.requests[0].path, '/v1/responses');
  assert.equal(ai.requests[0].body.input[0].role, 'user');
  assert.equal(ai.requests[0].body.input[0].content[1].image_url, 'data:image/png;base64,' + png.toString('base64'));
});
