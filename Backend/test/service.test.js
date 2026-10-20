import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { startServer } from '../src/server.js';
import { Repository } from '../src/database.js';
import { syncAccount, sendDraft, updateMessage } from '../src/mail.js';
import { saveAttachment, extractText } from '../src/attachments.js';
import { runAgent, approveClassification, useReplyPreview } from '../src/agent.js';
import { REPLY_PRESETS } from '../src/reply-presets.js';
import { accountInput, aiConfig, recipients } from '../src/validation.js';
import ExcelJS from 'exceljs';

const token = 'test-session-token-0123456789';
const account = {
  id: 'a1',
  name: '测试',
  email: 'me@example.com',
  username: 'me@example.com',
  imapHost: 'localhost',
  imapPort: 993,
  imapTLS: true,
  smtpHost: 'localhost',
  smtpPort: 465,
  smtpTLS: true,
  isDemo: false,
};
const message = {
  id: 'm1',
  accountId: 'a1',
  folder: 'inbox',
  sender: '陈嘉禾',
  senderEmail: 'chen@example.com',
  to: 'me@example.com',
  cc: '',
  subject: '路线图评审',
  body: '周五前确认排期',
  preview: '周五前确认排期',
  date: new Date().toISOString(),
  category: '未分类',
  unread: true,
  starred: false,
  attachmentIds: [],
  summary: null,
};
async function fixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-test-'));
  const repo = new Repository(directory);
  t.after(async () => {
    repo.close();
    await rm(directory, { recursive: true, force: true });
  });
  return repo;
}
async function apiFixture(t) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-api-'));
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  });
  return {
    ...app,
    request: async (route, body, headers = {}) => {
      const r = await fetch(`http://127.0.0.1:${app.port}${route}`, {
        method: body ? 'POST' : 'GET',
        headers: {
          'X-Boxmail-Token': token,
          'Content-Type': 'application/json',
          ...headers,
        },
        body: body ? JSON.stringify(body) : undefined,
      });
      return { status: r.status, body: await r.json() };
    },
  };
}
async function mockAI(t, respond) {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    requests.push(body);
    res.setHeader('Content-Type', 'application/json');
    res.end(
      JSON.stringify({
        status: 'completed',
        output: [
          {
            type: 'message', role: 'assistant',
            content: [{ type: 'output_text', text:
                typeof respond === 'string'
                  ? respond
                  : JSON.stringify(respond(body)),
            }],
          },
        ],
      }),
    );
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => new Promise((r) => server.close(r)));
  return {
    requests,
    config: {
      baseURL: `http://127.0.0.1:${server.address().port}/v1`,
      model: 'test-model',
      timeout: 10,
      effort: 'high',
      enabled: true,
    },
  };
}

test('local API requires session token and rejects browser origins', async (t) => {
  const app = await apiFixture(t);
  assert.equal(
    (await app.request('/state', null, { 'X-Boxmail-Token': 'wrong' })).status,
    403,
  );
  assert.equal(
    (await app.request('/state', null, { Origin: 'http://evil.test' })).status,
    403,
  );
  assert.equal((await app.request('/state')).status, 200);
});
test('account credentials never enter database; invalid accounts are rejected', async (t) => {
  const app = await apiFixture(t);
  let r = await app.request('/accounts', {
    account: { ...account, password: 'secret-password' },
    password: 'secret-password',
  });
  assert.equal(r.status, 200);
  assert.equal(app.repo.get('account', 'a1').password, undefined);
  r = await app.request('/accounts', { account: { ...account, imapPort: -1 } });
  assert.equal(r.status, 400);
  const file = await readFile(path.join(app.repo.directory, 'boxmail.sqlite'));
  assert.equal(file.includes(Buffer.from('secret-password')), false);
});
test('drafts retain incomplete recipient input; sending requires confirmation', async (t) => {
  const app = await apiFixture(t);
  app.repo.put('account', account);
  const r = await app.request('/drafts', {
    accountId: 'a1',
    to: 'unfinished@',
    subject: '草稿',
    body: '正文',
    cc: '',
    bcc: '',
    attachmentIds: [],
  });
  assert.equal(r.status, 200);
  assert.equal(r.body.to, 'unfinished@');
  const sent = await app.request('/send', {
    draftId: r.body.id,
    password: 'secret',
    approved: false,
  });
  assert.equal(sent.status, 403);
  assert.equal(app.repo.get('draft', r.body.id).status, 'draft');
});
test('search includes Chinese attachment contents; star and delete survive restart', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const a = await saveAttachment(
    repo,
    'm1',
    '排期.txt',
    Buffer.from('设计交付时间：十一月中旬'),
    'text/plain',
  );
  repo.put('message', { ...message, attachmentIds: [a.id] });
  assert.equal(repo.search('十一月中旬')[0].id, 'm1');
  updateMessage(repo, 'm1', { starred: true, folder: 'trash' });
  const second = new Repository(repo.directory);
  assert.equal(second.get('message', 'm1').folder, 'trash');
  assert.equal(second.get('message', 'm1').starred, true);
  second.close();
});
test('AI summary produces persisted todos and sends untrusted mail as user data', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({
    points: ['需要在周五前确认排期'],
    todos: [{ title: '确认排期', due: '周五' }],
    keyInfo: [{ label: '截止', value: '周五' }],
  }));
  const job = await runAgent(repo, {
    task: 'summary',
    messageId: 'm1',
    config: ai.config,
    apiKey: 'test-key',
  });
  assert.equal(job.status, 'completed');
  assert.equal(repo.get('message', 'm1').summary.todos[0].done, false);
  assert.match(ai.requests[0].instructions, /待分析的数据/);
  assert.equal(ai.requests[0].model, 'test-model');
  assert.deepEqual(ai.requests[0].reasoning, { effort: 'high' });
  assert.equal(ai.requests[0].input[0].role, 'user');
  assert.equal(ai.requests[0].temperature, undefined);
  assert.equal(ai.requests[0].max_output_tokens, undefined);
});
test('compact summary contract persists next steps without executing suggested actions', async t => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({
    overview: '路线图评审需要在周五前确认排期。', todos: [{ title: '确认排期', due: '周五' }],
    nextSteps: [{ title: '起草排期回复', action: 'reply', prompt: '起草确认排期的回复，不声称已经确认。' }],
  }));
  const job = await runAgent(repo, { task: 'summary', messageId: message.id, config: ai.config });
  const summary = repo.get('message', message.id).summary;
  assert.equal(summary.overview, '路线图评审需要在周五前确认排期。');
  assert.equal(summary.nextSteps[0].action, 'reply');
  assert.equal(job.status, 'completed');
  assert.match(ai.requests[0].instructions, /内容概要、待处理、您可继续/);
  assert.match(ai.requests[0].instructions, /"overview"/);
  assert.equal(repo.list('draft').length, 0);
  assert.equal(repo.list('job').length, 1);
});

test('AI replies create reviewable drafts without sending', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({
    subject: 'Re: 路线图评审',
    body: '已收到，周五前确认。',
  }));
  const job = await runAgent(repo, {
    task: 'reply',
    messageId: 'm1',
    config: ai.config,
  });
  const draft = repo.get('draft', job.result.draftId);
  assert.equal(draft.to, 'chen@example.com');
  assert.equal(draft.status, 'draft');
  assert.equal(draft.sourceMessageId, 'm1');
  assert.equal(
    repo.list('message').filter((m) => m.folder === 'sent').length,
    0,
  );
});
test('three reply attitudes use distinct instructions and preview without creating drafts', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, (body) => {
    const context = JSON.parse(body.input[0].content[0].text);
    return { subject: 'Re: 路线图评审', body: `${context.replyIntent}的独立预览` };
  });
  assert.deepEqual(Object.keys(REPLY_PRESETS), ['interested', 'decline', 'thanks']);
  const custom = '回复时不使用客套开场白。'.padEnd(6000, '文');
  for (const [replyPreset, definition] of Object.entries(REPLY_PRESETS)) {
    const config = { ...ai.config, prompts: { reply: custom } };
    const job = await runAgent(repo, {
      task: 'reply', messageId: 'm1', replyPreset, preview: true,
      prompt: '控制在 100 字内', config, apiKey: 'test-key',
    });
    assert.equal(job.status, 'completed');
    assert.equal(job.preview, true);
    assert.equal(job.replyPreset, replyPreset);
    assert.equal(job.result.body, `${definition.title}的独立预览`);
    assert.equal(job.result.draftId, undefined);
    const request = ai.requests.at(-1);
    assert.ok(request.instructions.includes(custom));
    assert.ok(request.instructions.includes(definition.instruction));
    assert.match(request.instructions, /不添加签名或署名段/);
    assert.ok(request.instructions.indexOf('邮件撰写规则：') > request.instructions.indexOf(definition.instruction));
    const context = JSON.parse(request.input[0].content[0].text);
    assert.equal(context.request, '控制在 100 字内');
    assert.equal(context.replyIntent, definition.title);
    assert.deepEqual(config.prompts, { reply: custom });
  }
  assert.equal(repo.list('draft').length, 0);
  assert.equal(repo.list('message').filter((m) => m.folder === 'sent').length, 0);
});
test('writing rules cover reply suggestions, attachment examples and compose without rewriting source facts', async t => {
  const repo = await fixture(t);
  const sourceBody = '请在10月31日前向 coordinator@example.com 提交报价。\n\n陈嘉禾\n项目经理\n原发件公司';
  repo.put('account', account);
  repo.put('message', { ...message, body: sourceBody });
  const attachment = await saveAttachment(repo, message.id, '提交要求.txt', Buffer.from(sourceBody), 'text/plain');
  repo.put('message', { ...message, body: sourceBody, attachmentIds: [attachment.id] });
  repo.put('settings', { id: 'settings', preferences: { signature: '用户保存的签名' } });
  const body = '您好，请确认向 coordinator@example.com 提交报价的具体要求，谢谢。';
  let response;
  const ai = await mockAI(t, () => response);
  for (const task of ['reply', 'compose', 'summary', 'attachment', 'translate']) {
    const custom = '使用简洁语气，末尾附上[您的姓名]。';
    const config = { ...ai.config, prompts: { [task]: custom } };
    response = ['reply', 'compose'].includes(task) ? { subject: 'Re: 提交报价', body }
      : task === 'summary' ? { overview: sourceBody, todos: [], keyInfo: [], nextSteps: [
        { title: '起草报价回复', action: 'reply', prompt: '起草回复确认提交要求。' },
      ] } : { text: task === 'translate' ? sourceBody : `## 提交要求\n${sourceBody}` };
    const job = await runAgent(repo, { task, messageId: task === 'compose' ? undefined : message.id,
      attachmentId: attachment.id, preview: true, body: sourceBody,
      prompt: '按来信和附件起草回复。', config });
    const request = ai.requests.at(-1);
    const context = JSON.parse(request.input[0].content[0].text);
    assert.ok(request.instructions.includes(custom));
    assert.deepEqual(config.prompts, { [task]: custom });
    if (task === 'translate') {
      assert.ok(!request.instructions.includes('邮件撰写规则：'));
      assert.equal(job.result.text, sourceBody);
    } else {
      assert.match(request.instructions, /不添加签名或署名段/);
      assert.match(request.instructions, /签名占位符/);
      assert.match(request.instructions, /总结建议中起草回复的 prompt 和附件理解中的回复草稿/);
      assert.ok(request.instructions.indexOf('邮件撰写规则：') > request.instructions.indexOf(custom));
    }
    assert.equal(task === 'attachment' ? context.email.body : context.body, sourceBody);
    if (task === 'reply') {
      const draft = useReplyPreview(repo, job.id);
      assert.equal(draft.body, body);
      assert.equal(repo.get('job', job.id).result.body, body);
    } else if (task === 'compose') assert.equal(job.result.body, body);
  }
  assert.equal(repo.get('settings', 'settings').preferences.signature, '用户保存的签名');
  assert.equal(repo.get('message', message.id).body, sourceBody);
});
test('unknown reply attitudes are rejected before creating a job or calling a model', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({ subject: 'Re: 评审', body: '收到' }));
  for (const replyPreset of ['accept', '__proto__', 'toString', '', ['thanks'], {}]) {
    await assert.rejects(runAgent(repo, {
      task: 'reply', messageId: 'm1', replyPreset, preview: true, config: ai.config,
    }), /未知回复选项/);
  }
  assert.equal(ai.requests.length, 0);
  assert.equal(repo.list('job').length, 0);
});
test('custom reply previews use the editable reply prompt and retain successful results after failure', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  let empty = false;
  const ai = await mockAI(t, () => ({ subject: 'Re: 评审', body: empty ? '  ' : '确认收到，请告知下一步。' }));
  const job = await runAgent(repo, {
    task: 'reply', messageId: 'm1', preview: true, prompt: '询问下一步', config: ai.config,
  });
  assert.equal(job.replyPreset, null);
  assert.match(ai.requests[0].instructions, /不编造承诺/);
  assert.equal(JSON.parse(ai.requests[0].input[0].content[0].text).replyIntent, undefined);
  empty = true;
  await assert.rejects(runAgent(repo, {
    task: 'reply', messageId: 'm1', preview: true, config: ai.config,
  }), /草稿格式/);
  assert.equal(repo.get('job', job.id).result.body, '确认收到，请告知下一步。');
  assert.equal(repo.list('job').filter((j) => j.status === 'failed').length, 1);
  assert.equal(repo.list('draft').length, 0);
});
test('using a reply preview creates one editable draft and preserves edits on repeated use', async (t) => {
  const repo = await fixture(t);
  repo.put('message', { ...message, messageId: '<original@example.com>' });
  const ai = await mockAI(t, () => ({ subject: 'Re: 评审', body: '谢谢，已收到。' }));
  const job = await runAgent(repo, {
    task: 'reply', messageId: 'm1', replyPreset: 'thanks', preview: true, config: ai.config,
  });
  const draft = useReplyPreview(repo, job.id);
  assert.equal(draft.to, message.senderEmail);
  assert.equal(draft.accountId, message.accountId);
  assert.equal(draft.sourceMessageId, message.id);
  assert.equal(draft.inReplyTo, '<original@example.com>');
  assert.equal(draft.status, 'draft');
  assert.deepEqual(draft.attachmentIds, []);
  repo.put('draft', { ...draft, body: '用户修改的正文' });
  const reused = useReplyPreview(repo, job.id);
  assert.equal(reused.id, draft.id);
  assert.equal(reused.body, '用户修改的正文');
  assert.equal(repo.list('draft').length, 1);
  assert.equal(repo.get('job', job.id).result.draftId, draft.id);
  assert.equal(ai.requests.length, 1);
  assert.equal(repo.list('message').filter((m) => m.folder === 'sent').length, 0);
});
test('reply previews cannot resurrect deleted drafts or drafts in the send flow', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({ subject: 'Re: 评审', body: '谢谢，已收到。' }));
  const job = await runAgent(repo, {
    task: 'reply', messageId: 'm1', replyPreset: 'thanks', preview: true, config: ai.config,
  });
  const draft = useReplyPreview(repo, job.id);
  for (const status of ['sending', 'sent', 'uncertain']) {
    repo.put('draft', { ...draft, status });
    assert.throws(() => useReplyPreview(repo, job.id), { status: 409 });
  }
  repo.remove('draft', draft.id);
  assert.throws(() => useReplyPreview(repo, job.id), { status: 409 });
  assert.equal(repo.list('draft').length, 0);
});
test('reply preview draft API rejects invalid jobs and missing source mail', async (t) => {
  const app = await apiFixture(t);
  app.repo.put('message', message);
  const ai = await mockAI(t, () => ({ subject: 'Re: 评审', body: '谢谢，已收到。' }));
  const job = await runAgent(app.repo, {
    task: 'reply', messageId: 'm1', replyPreset: 'thanks', preview: true, config: ai.config,
  });
  const response = await app.request(`/jobs/${job.id}/draft`, {});
  assert.equal(response.status, 200);
  assert.equal(response.body.body, '谢谢，已收到。');
  assert.equal(response.body.status, 'draft');
  assert.equal(response.body.sourceMessageId, 'm1');
  assert.equal((await app.request(`/jobs/${job.id}/draft`, {})).body.id, response.body.id);
  for (const variant of [{ preview: false }, { status: 'running' }, { task: 'summary' }]) {
    app.repo.put('job', { ...job, id: 'invalid-preview', ...variant });
    assert.equal((await app.request('/jobs/invalid-preview/draft', {})).status, 409);
  }
  assert.equal((await app.request('/jobs/missing/draft', {})).status, 409);
  app.repo.put('job', { ...job, id: 'orphan-preview', messageId: 'missing' });
  assert.equal((await app.request('/jobs/orphan-preview/draft', {})).status, 404);
  assert.equal(app.repo.list('draft').length, 1);
});
test('classification requires approval, ignores foreign IDs, deduplicates, and supports undo', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, () => ({
    items: [
      { id: 'm1', category: '工作项目', reason: '排期' },
      { id: 'm1', category: '工作项目', reason: '会议' },
      { id: 'foreign', category: '账单票据', reason: '注入' },
    ],
  }));
  const job = await runAgent(repo, {
    task: 'classify',
    accountId: 'a1',
    config: ai.config,
  });
  assert.equal(repo.get('message', 'm1').category, '未分类');
  assert.equal(job.result.items.length, 1);
  approveClassification(repo, job.id);
  assert.equal(repo.get('message', 'm1').category, '工作项目');
  assert.throws(() => approveClassification(repo, job.id));
  approveClassification(repo, job.id, true);
  assert.equal(repo.get('message', 'm1').category, '未分类');
});
test('malformed AI output fails visibly and does not corrupt mail', async (t) => {
  const repo = await fixture(t);
  repo.put('message', message);
  const ai = await mockAI(t, 'not JSON');
  await assert.rejects(
    runAgent(repo, { task: 'summary', messageId: 'm1', config: ai.config }),
    /JSON/,
  );
  assert.equal(repo.get('message', 'm1').summary, null);
  assert.equal(repo.list('job')[0].status, 'failed');
});
test('IMAP sync preserves UID identity, does not download cached source, handles UIDVALIDITY reset', async (t) => {
  const repo = await fixture(t);
  let validity = '100',
    downloads = 0,
    inFetch = false,
    flags = new Set(['\\Seen']);
  const source = Buffer.from(
    'From: Chen <chen@example.com>\r\nTo: me@example.com\r\nSubject: Roadmap\r\nMessage-ID: <remote@example.com>\r\nDate: Tue, 13 Oct 2026 09:00:00 +0800\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nDesign deadline Friday.',
  );
  const fake = {
    mailbox: {},
    connect: async () => {},
    list: async () => [{ path: 'INBOX' }],
    logout: async () => {},
    getMailboxLock: async () => {
      fake.mailbox = { uidValidity: validity, exists: 1 };
      return { release() {} };
    },
    async *fetch() {
      inFetch = true;
      yield { uid: 7, size: source.length, flags, internalDate: new Date() };
      inFetch = false;
    },
    fetchOne: async () => {
      assert.equal(
        inFetch,
        false,
        'do not issue commands inside fetch iterator',
      );
      downloads++;
      return { source };
    },
    messageFlagsAdd: async () => {
      flags.add('\\Flagged');
    },
    messageFlagsRemove: async () => {},
  };
  repo.put('account', account);
  await syncAccount(repo, account, 'test', { clientFactory: () => fake });
  const first = repo.list('message')[0];
  assert.equal(first.unread, false);
  assert.equal(first.uid, 7);
  updateMessage(repo, first.id, { starred: true });
  await syncAccount(repo, account, 'test', { clientFactory: () => fake });
  assert.equal(downloads, 1);
  assert.equal(repo.list('mutation').length, 0);
  assert.equal(repo.get('message', first.id).starred, true);
  validity = '101';
  await syncAccount(repo, account, 'test', { clientFactory: () => fake });
  assert.equal(downloads, 2);
  assert.equal(repo.list('message').length, 1);
  assert.notEqual(repo.list('message')[0].id, first.id);
});
test('XLSX text extraction indexes sheet names and Chinese cell values', async () => {
  const wb = new ExcelJS.Workbook();
  wb.addWorksheet('排期').addRow(['陈嘉禾', '11 月中旬']);
  const buffer = Buffer.from(await wb.xlsx.writeBuffer());
  const text = await extractText(buffer, 'plan.xlsx');
  assert.match(text, /排期/);
  assert.match(text, /陈嘉禾/);
  assert.match(text, /11 月中旬/);
});
test('recipient and API endpoint validation', () => {
  assert.deepEqual(recipients('a@example.com，b@example.com'), [
    'a@example.com',
    'b@example.com',
  ]);
  assert.throws(() => recipients('a@example.com\r\nBcc: attacker@example.com'));
  assert.throws(() =>
    aiConfig({ baseURL: 'http://remote.example/v1', model: 'm' }),
  );
  assert.equal(
    aiConfig({ baseURL: 'http://127.0.0.1:11434/v1', model: 'm' }).timeout,
    120,
  );
  assert.throws(() => accountInput({ ...account, email: 'bad' }));
});
test('uncertain send is never retried automatically', async (t) => {
  const repo = await fixture(t);
  repo.put('account', account);
  repo.put('draft', {
    id: 'd1',
    accountId: 'a1',
    status: 'uncertain',
    to: 'a@example.com',
  });
  await assert.rejects(sendDraft(repo, 'd1', 'pw', true), /重复发送/);
});

test('preferences can be saved before choosing an AI model', async (t) => {
  const app = await apiFixture(t);
  const response = await app.request('/settings', {
    ai: { baseURL: 'https://api.openai.com/v1', model: '', enabled: true },
    preferences: { syncMinutes: 3, signature: '张明远' },
  });
  assert.equal(response.status, 200);
  assert.equal(app.repo.get('settings', 'settings').ai.model, '');
  assert.equal(app.repo.get('settings', 'settings').preferences.syncMinutes, 3);
});

test('moving a message retains local summary, categories and attachment text', async (t) => {
  const repo = await fixture(t);
  const source = Buffer.from(
    'From: Chen <chen@example.com>\r\nTo: me@example.com\r\nSubject: Roadmap\r\nMessage-ID: <move@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nFriday deadline.',
  );
  let moved = false;
  const fake = {
    mailbox: {},
    connect: async () => {},
    logout: async () => {},
    list: async () => [
      { path: 'INBOX' },
      { path: 'Trash', specialUse: '\\Trash' },
    ],
    getMailboxLock: async (path) => {
      fake.path = path;
      fake.mailbox = {
        uidValidity: path === 'INBOX' ? '10' : '20',
        exists: path === 'INBOX' ? (moved ? 0 : 1) : moved ? 1 : 0,
      };
      return { release() {} };
    },
    async *fetch() {
      if (fake.mailbox.exists)
        yield {
          uid: fake.path === 'INBOX' ? 1 : 2,
          size: source.length,
          flags: new Set(['\\Seen']),
        };
    },
    fetchOne: async () => ({ source }),
    messageMove: async () => {
      moved = true;
      return {
        destination: 'Trash',
        uidValidity: 20n,
        uidMap: new Map([[1, 2]]),
      };
    },
  };
  repo.put('account', account);
  await syncAccount(repo, account, 'pw', { clientFactory: () => fake });
  let original = repo.list('message')[0];
  const attachment = await saveAttachment(
    repo,
    original.id,
    'note.txt',
    Buffer.from('附件原文'),
  );
  original = {
    ...original,
    category: '工作项目',
    attachmentIds: [attachment.id],
    summary: { points: ['周五截止'], todos: [], keyInfo: [] },
    translation: '已保存译文',
  };
  repo.put('message', original);
  updateMessage(repo, original.id, { folder: 'trash' });
  await syncAccount(repo, account, 'pw', { clientFactory: () => fake });
  const next = repo.list('message')[0];
  assert.equal(next.folder, 'trash');
  assert.equal(next.category, '工作项目');
  assert.deepEqual(next.summary.points, ['周五截止']);
  assert.equal(next.translation, '已保存译文');
  assert.deepEqual(next.attachmentIds, [attachment.id]);
  assert.equal(repo.get('attachment', attachment.id).messageId, next.id);
  assert.equal(repo.list('relocation').length, 0);
});

test('app restart marks interrupted sends uncertain and interrupted agent tasks failed', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-restart-'));
  let app = await startServer({ directory, token, demo: false });
  app.repo.put('draft', { id: 'd1', status: 'sending' });
  app.repo.put('job', { id: 'j1', status: 'running' });
  await app.close();
  app = await startServer({ directory, token, demo: false });
  t.after(async () => {
    await app.close();
    await rm(directory, { recursive: true, force: true });
  });
  assert.equal(app.repo.get('draft', 'd1').status, 'uncertain');
  assert.equal(app.repo.get('job', 'j1').status, 'failed');
});
