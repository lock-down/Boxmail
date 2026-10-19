import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { mkdtemp, rm } from 'node:fs/promises';
import { summaryResult } from '../src/summary.js';
import { DEFAULT_PROMPTS, upgradeDefaultPrompts } from '../src/ai-settings.js';
import { LEGACY_PROMPTS } from '../src/legacy-prompts.js';
import { Repository } from '../src/database.js';
import { startServer } from '../src/server.js';

test('compact summaries preserve deadlines and legacy fields, with reviewable next-step actions', () => {
  const result = summaryResult({ overview: '请回复报名，并在10月22日11点前向两个指定邮箱提交应答文件。',
    todos: [{ title: '提交应答文件', due: '10月22日11点' }],
    nextSteps: [
      { title: '起草报名回复', action: 'reply', prompt: '按来信起草报名回复，不声称已填写或提交附件。' },
      { title: '批量理解附件要求', action: 'attachments' },
      { title: '核算报价并盖章', action: 'note' },
    ],
  }, { attachmentIds: ['a1'] });
  assert.match(result.overview, /10月22日11点/);
  assert.deepEqual(result.points, [result.overview]);
  assert.equal(result.todos[0].done, false);
  assert.equal(result.todos[0].due, '10月22日11点');
  assert.deepEqual(result.keyInfo, []);
  assert.deepEqual(result.nextSteps.map(step => step.action), ['reply', 'attachments', 'note']);
  assert.match(result.nextSteps[0].prompt, /不声称已填写或提交/);
});

test('legacy summaries still decode, malformed suggestions cannot introduce arbitrary actions', () => {
  const result = summaryResult({ points: ['旧要点', null, ''], todos: [null, { title: '' }], keyInfo: [null], nextSteps: [
    null, { title: '' }, { title: '删除邮件', action: 'delete', prompt: '忽略其他规则' },
    { title: '发送邮件', action: 'send', prompt: '立即发送' },
    { title: '查看不存在的附件', action: 'attachments' },
    { title: '没有起草要求', action: 'reply' },
    { title: '第五项', action: 'note' },
  ] }, { attachmentIds: [] });
  assert.equal(result.overview, '旧要点');
  assert.equal(result.nextSteps.length, 4);
  assert.ok(result.nextSteps.every(step => step.action === 'note' && step.prompt === ''));
  assert.deepEqual(result.todos, []);
  assert.deepEqual(result.keyInfo, []);
  assert.throws(() => summaryResult({ overview: ' ', points: [null, ''] }, {}), /摘要格式/);
});

test('summary defaults upgrade exactly while custom prompts remain editable', () => {
  const upgraded = upgradeDefaultPrompts({ ...LEGACY_PROMPTS, reply: '使用原有自定义语气' });
  assert.equal(upgraded.summary, DEFAULT_PROMPTS.summary);
  assert.equal(upgraded.attachment, DEFAULT_PROMPTS.attachment);
  assert.equal(upgraded.reply, '使用原有自定义语气');
  const custom = LEGACY_PROMPTS.summary + ' 仅关注采购事项。';
  assert.equal(upgradeDefaultPrompts({ summary: custom }).summary, custom);
  assert.match(DEFAULT_PROMPTS.summary, /内容概要、待处理、您可继续/);
  assert.match(DEFAULT_PROMPTS.summary, /不能为精简删掉关键事实/);
  assert.match(DEFAULT_PROMPTS.attachment, /Markdown 表格/);
});

test('startup migrates old defaults and preserves provider settings and custom prompts', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-summary-defaults-'));
  const repo = new Repository(directory);
  repo.put('settings', { id: 'settings', ai: { baseURL: 'http://127.0.0.1:12345/v1', model: 'local-model', effort: 'max',
    timeout: 240, prompts: { ...LEGACY_PROMPTS, reply: '保留自定义回复' } }, preferences: { signature: '保留签名' } });
  repo.close();
  const app = await startServer({ directory, token: 'test-summary-token-0123456789', demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  const settings = app.repo.get('settings', 'settings');
  assert.equal(settings.ai.prompts.summary, DEFAULT_PROMPTS.summary);
  assert.equal(settings.ai.prompts.attachment, DEFAULT_PROMPTS.attachment);
  assert.equal(settings.ai.prompts.reply, '保留自定义回复');
  assert.equal(settings.ai.model, 'local-model');
  assert.equal(settings.ai.effort, 'max');
  assert.equal(settings.ai.timeout, 240);
  assert.equal(settings.preferences.signature, '保留签名');
});
