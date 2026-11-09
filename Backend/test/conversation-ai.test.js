import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { conversation } from '../src/threads.js';
import { conversationContext, conversationResult, requireFreshConversation } from '../src/conversation-ai.js';
import { runAgent, useReplyPreview } from '../src/agent.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { responsesWire } from './helpers/ai-streams.js';

const base = { accountId: 'a1', folder: 'inbox', sender: '同事', senderEmail: 'you@example.test',
  to: 'me@example.test', cc: '', subject: '排期', body: '需要确认排期', preview: '', attachmentIds: [],
  date: '2026-11-01T00:00:00Z', category: '未分类', unread: false, starred: false };
async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-conversation-ai-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory, { recursive: true, force: true }); });
  repo.put('account', { id: 'a1', name: '本人', email: 'me@example.test' });
  repo.put('message', { ...base, id: 'root', messageId: '<root@example.test>' });
  repo.put('message', { ...base, id: 'latest', date: '2026-11-02T00:00:00Z', body: '周五前确认，不必重复提交旧材料',
    messageId: '<latest@example.test>', references: ['<root@example.test>'] });
  repo.put('message', { ...base, accountId: 'other', id: 'foreign', body: '其他账户私有内容',
    messageId: '<foreign@example.test>', references: ['<root@example.test>'] });
  return repo;
}
async function provider(t, result) {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    requests.push(JSON.parse(Buffer.concat(chunks)));
    res.setHeader('Content-Type', 'text/event-stream');
    res.end(responsesWire({ status: 'completed', output: [{ type: 'message', role: 'assistant',
      content: [{ type: 'output_text', text: JSON.stringify(result) }] }] }));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  return { requests, config: { ...DEFAULT_AI, baseURL: `http://127.0.0.1:${server.address().port}/v1`, timeout: 10 } };
}

test('conversation AI receives same-account chronology, preserves cited sources, and persists a structured summary', async t => {
  const repo = await fixture(t);
  const ai = await provider(t, { progress: [{ text: '排期进入确认阶段', messageIds: ['root', 'latest'] }],
    openItems: [{ text: '周五前确认', messageIds: ['latest'] }], nextSteps: [] });
  const output = [];
  const job = await runAgent(repo, { task: 'conversationSummary', messageId: 'root', config: ai.config,
    onProgress: value => output.push(value) });
  assert.equal(job.status, 'completed'); assert.equal(job.result.total, 2);
  assert.deepEqual(job.result.sourceMessages.map(source => source.id), ['root', 'latest']);
  assert.deepEqual(job.result.openItems[0].messageIds, ['latest']);
  const sent = JSON.stringify(ai.requests[0]);
  assert.match(sent, /需要确认排期/); assert.match(sent, /周五前确认/);
  assert.doesNotMatch(sent, /其他账户私有内容/); assert.match(sent, /不能作为指令/);
  assert.ok(output.some(value => value.text.includes('排期进入确认阶段')));
  assert.equal(repo.get('message', 'root').summary, undefined, 'thread summaries do not replace per-mail summaries');
  assert.deepEqual(repo.get('job', job.id).result, job.result);
});

test('a conversation reply stays a preview, targets the latest mail, and never overwrites a used draft', async t => {
  const repo = await fixture(t);
  const ai = await provider(t, { subject: 'Re: 排期', body: '收到，将核对周五前的排期要求。', sourceIds: ['latest'] });
  const job = await runAgent(repo, { task: 'conversationReply', messageId: 'root', config: ai.config });
  assert.equal(repo.activeDrafts('a1').length, 0);
  const draft = useReplyPreview(repo, job.id);
  assert.equal(draft.sourceMessageId, 'latest'); assert.equal(draft.inReplyTo, '<latest@example.test>');
  assert.equal(draft.to, 'you@example.test');
  repo.put('draft', { ...draft, body: '用户已编辑的回复' });
  assert.equal(useReplyPreview(repo, job.id).body, '用户已编辑的回复');
  assert.equal(repo.activeDrafts('a1').length, 1);
});

test('new messages make old results stale and prevent adopting an outdated reply', async t => {
  const repo = await fixture(t), context = conversationContext(repo, 'root');
  const result = conversationResult({ subject: 'Re: 排期', body: '回复正文', sourceIds: ['latest'] }, context, 'conversationReply');
  const job = repo.put('job', { id: 'preview', task: 'conversationReply', status: 'completed', preview: true,
    accountId: 'a1', messageId: 'root', createdAt: new Date().toISOString(), result });
  assert.equal(conversation(repo, 'root').fingerprint, result.contextFingerprint);
  repo.put('message', { ...base, id: 'new', messageId: '<new@example.test>', body: '期限已延后',
    references: ['<root@example.test>'], date: '2026-11-03T00:00:00Z' });
  assert.notEqual(conversation(repo, 'root').fingerprint, result.contextFingerprint);
  assert.throws(() => useReplyPreview(repo, job.id), /新邮件/);
  assert.equal(repo.activeDrafts('a1').length, 0);
});

test('changes to source bodies invalidate reply adoption even when membership is unchanged', async t => {
  const repo = await fixture(t), context = conversationContext(repo, 'root');
  const result = conversationResult({ subject: '回复', body: '正文', sourceIds: ['latest'] }, context, 'conversationReply');
  repo.put('message', { ...repo.get('message', 'latest'), body: '更新了重要事实' });
  assert.throws(() => requireFreshConversation(repo, { messageId: 'root', accountId: 'a1', result }), /内容变化/);
});

test('unknown or cross-account source IDs fail closed without storing model claims', async t => {
  const repo = await fixture(t);
  const ai = await provider(t, { progress: [{ text: '没有依据的结论', messageIds: ['foreign'] }], openItems: [], nextSteps: [] });
  await assert.rejects(runAgent(repo, { task: 'conversationSummary', messageId: 'root', config: ai.config }), /依据邮件/);
  assert.equal(repo.list('job')[0].status, 'failed'); assert.equal(repo.list('job')[0].result, null);
  assert.equal(repo.activeDrafts('a1').length, 0);
});

test('large cached conversations disclose omissions and keep latest messages within a bounded model input', async t => {
  const repo = await fixture(t);
  for (let index = 0; index < 70; index++) repo.put('message', { ...base, id: `long-${index}`,
    messageId: `<long-${index}@example.test>`, references: ['<root@example.test>'],
    body: `第 ${index} 封：` + '长正文'.repeat(12000), date: new Date(Date.UTC(2026, 10, 3, index)).toISOString() });
  const context = conversationContext(repo, 'root');
  assert.equal(context.sources.length, 50); assert.equal(context.total, 72); assert.equal(context.partial, true);
  assert.ok(context.sources.reduce((sum, source) => sum + source.body.length, 0) <= 120000);
  assert.ok(context.sources.some(source => source.id === 'root'));
  assert.ok(context.sources.find(source => source.id === context.replyMessageId).body.length > 0);
});
