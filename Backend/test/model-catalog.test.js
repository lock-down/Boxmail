import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { startServer } from '../src/server.js';

const token = 'model-catalog-test-session-0123456789';

async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-model-catalog-'));
  const provider = { payload: { data: [] }, raw: null, status: 200, requests: 0 };
  const server = http.createServer((req, res) => {
    assert.match(req.url, /^\/v[12]\/models$/);
    provider.requests += 1;
    res.writeHead(provider.status, { 'Content-Type': 'application/json' });
    res.end(provider.raw ?? JSON.stringify(provider.payload));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let app = await startServer({ directory, token, demo: false });
  t.after(async () => {
    await app.close();
    await new Promise(resolve => server.close(resolve));
    await rm(directory, { recursive: true, force: true });
  });
  const endpoint = `http://127.0.0.1:${server.address().port}/v1`;
  async function request(route, body) {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, {
      method: body ? 'POST' : 'GET',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, body: await response.json() };
  }
  return {
    provider, endpoint, request,
    refresh: (baseURL = endpoint) => request('/ai/models', {
      config: { baseURL, model: '' }, apiKey: 'fake-catalog-key-not-to-be-stored',
    }),
    cached: (baseURL = endpoint) => request('/ai/models?baseURL=' + encodeURIComponent(baseURL)),
    restart: async () => { await app.close(); app = await startServer({ directory, token, demo: false }); },
    catalogs: () => app.repo.list('modelCatalog'),
  };
}

test('refreshed model lists survive service restart without another provider request or saved API settings', async t => {
  const app = await fixture(t);
  assert.deepEqual((await app.cached()).body, { models: [] });
  assert.equal(app.provider.requests, 0);
  app.provider.payload = { data: [{ id: ' deepseek-flash ' }, { id: 'deepseek-v4-pro' }, { id: 'deepseek-flash' }] };
  assert.deepEqual((await app.refresh(app.endpoint + '/')).body,
    { models: ['deepseek-flash', 'deepseek-v4-pro'] });
  await app.restart();
  app.provider.status = 503;
  assert.deepEqual((await app.cached(app.endpoint + '/')).body,
    { models: ['deepseek-flash', 'deepseek-v4-pro'] });
  assert.equal(app.provider.requests, 1);
  assert.equal(JSON.stringify(app.catalogs()).includes('fake-catalog-key-not-to-be-stored'), false);
});

test('a successful refresh replaces the old catalog and an explicitly empty list clears it', async t => {
  const app = await fixture(t);
  app.provider.payload = { data: [{ id: 'old-model' }, { id: 'removed-model' }] };
  await app.refresh();
  app.provider.payload = { data: [{ id: 'new-model' }] };
  await app.refresh();
  assert.deepEqual((await app.cached()).body, { models: ['new-model'] });
  app.provider.payload = { data: [] };
  assert.deepEqual((await app.refresh()).body, { models: [] });
  await app.restart();
  assert.deepEqual((await app.cached()).body, { models: [] });
});

test('HTTP failures and malformed model responses leave the last successful catalog intact', async t => {
  const app = await fixture(t);
  app.provider.payload = { data: [{ id: 'saved-model' }] };
  await app.refresh();
  app.provider.status = 503;
  assert.equal((await app.refresh()).status, 502);
  app.provider.status = 200;
  for (const payload of [{}, { data: null }, { data: [{ id: 42 }] }, { data: [{ id: ' ' }] }]) {
    app.provider.payload = payload;
    assert.equal((await app.refresh()).status, 502);
    assert.deepEqual((await app.cached()).body, { models: ['saved-model'] });
  }
  app.provider.raw = 'not-json';
  assert.equal((await app.refresh()).status, 502);
  await app.restart();
  assert.deepEqual((await app.cached()).body, { models: ['saved-model'] });
});

test('catalogs are scoped to the normalized API endpoint and survive unrelated settings saves', async t => {
  const app = await fixture(t);
  app.provider.payload = { data: [{ id: 'provider-one' }] };
  await app.refresh();
  const second = app.endpoint.replace('/v1', '/v2');
  assert.deepEqual((await app.cached(second)).body, { models: [] });
  app.provider.payload = { data: [{ id: 'provider-two' }] };
  await app.refresh(second);
  await app.request('/settings', { preferences: { signature: 'A saved preference' } });
  assert.deepEqual((await app.cached()).body, { models: ['provider-one'] });
  assert.deepEqual((await app.cached(second)).body, { models: ['provider-two'] });
  assert.equal(app.provider.requests, 2);
  const rejected = await app.cached('https://user:secret@example.com/v1');
  assert.equal(rejected.status, 400);
});
