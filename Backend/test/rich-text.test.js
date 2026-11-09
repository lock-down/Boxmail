import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import MailComposer from 'nodemailer/lib/mail-composer/index.js';
import { simpleParser } from 'mailparser';
import { richContent, richFromHTML, safeLink } from '../src/rich-text.js';
import { draftContent, forwardText } from '../src/forward-content.js';
import { startServer } from '../src/server.js';

const document = { blocks: [
  { kind: 'paragraph', runs: [{ text: '中文 <正文>', bold: true, fontSize: 24, color: '#B42318' },
    { text: '查看', link: 'https://example.test/?a=1&b=2', fontSize: 12.75, color: '#3567AF' }] },
  { kind: 'bullet', runs: [{ text: '核对合同' }] },
  { kind: 'numbered', runs: [{ text: '确认期限', italic: true }] },
  { kind: 'numbered', runs: [{ text: '回复' }] },
] };

test('rich text keeps semantic bold, lists, links and readable plain-text alternatives', () => {
  const rich = richContent(document);
  assert.equal(rich.body, '中文 <正文>查看\n• 核对合同\n1. 确认期限\n2. 回复');
  assert.match(rich.bodyHTML, /<strong>中文 &lt;正文&gt;<\/strong>/);
  assert.match(rich.bodyHTML, /<ul><li[^>]*><span[^>]*>核对合同<\/span><\/li><\/ul><ol>/);
  assert.match(rich.bodyHTML, /href="https:\/\/example.test\/\?a=1&amp;b=2"/);
  assert.deepEqual(richFromHTML(rich.bodyHTML), rich);
  const sent = draftContent({ ...rich, forwardedHTML: '<blockquote>原文</blockquote>', forwardedText: '原文' });
  assert.equal(sent.text, rich.body + '\n\n原文');
  assert.equal(sent.html, rich.bodyHTML + '<blockquote>原文</blockquote>');
});

test('HTML import never exposes active markup or external resources to the editor', () => {
  const rich = richFromHTML('<head><style>@import url(https://example.test);</style></head><p onclick="x()">正文'
    + '<img src="https://example.test/private.png"><a href="javascript:alert(1)">链接</a></p><script>secret()</script>');
  assert.equal(rich.body, '正文链接');
  assert.doesNotMatch(rich.bodyHTML, /script|onclick|img|style|javascript|secret/);
  for (const url of ['javascript:alert(1)', 'file:///etc/passwd', 'data:text/html,x', '//example.test', 'https://x\n.test'])
    assert.equal(safeLink(url), null);
  assert.throws(() => richContent({ blocks: [{ kind: 'paragraph', runs: [{ text: 'x', link: 'javascript:bad' }] }] }), /链接/);
  assert.throws(() => richContent({ blocks: [{ kind: 'paragraph', runs: [{ text: 'x'.repeat(500001) }] }] }), /500,000/);
});

test('inline sizes and colors survive MIME alternatives without merging differently styled runs', async () => {
  const rich = richContent(document);
  assert.match(rich.bodyHTML, /<span style="font-size:24pt;color:#B42318"><strong>/);
  assert.match(rich.bodyHTML, /<a href="[^"]+" style="font-size:12.75pt;color:#3567AF">查看<\/a>/);
  const parsed = await simpleParser(await new MailComposer({
    from: 'me@example.test', to: 'you@example.test', ...draftContent(rich),
  }).compile().build());
  assert.equal(parsed.text.replace(/\r\n/g, '\n').trimEnd(), rich.body);
  assert.deepEqual(richFromHTML(parsed.html), rich);
  const normalized = richContent({ blocks: [{ kind: 'paragraph', runs: [
    { text: '默认', fontSize: 14, color: '#232d3d' }, { text: '正文' },
    { text: '红色', fontSize: 18, color: '#b42318' }, { text: '红色', fontSize: 18, color: '#B42318' },
    { text: '其他字号', fontSize: 24, color: '#B42318' },
  ] }] });
  assert.equal(normalized.richText.blocks[0].runs.length, 3);
  assert.equal(normalized.richText.blocks[0].runs[0].text, '默认正文');
  assert.equal(normalized.richText.blocks[0].runs[1].text, '红色红色');
  assert.equal(normalized.richText.blocks[0].runs[0].fontSize, undefined);
  assert.equal(normalized.richText.blocks[0].runs[0].color, undefined);
});

test('HTML list markers inherit item size while mixed runs and empty items keep their intended sizes', async () => {
  const rich = richContent({ blocks: [
    { kind: 'numbered', runs: [{ text: '大字号', fontSize: 28, color: '#B42318' }, { text: '默认正文' }] },
    { kind: 'numbered', runs: [{ text: '继续', fontSize: 28 }] },
    { kind: 'numbered', runs: [] },
    { kind: 'bullet', runs: [{ text: '项目符号', fontSize: 36 }] },
  ] });
  assert.match(rich.bodyHTML, /<li style="font-size:28pt;color:#B42318">/);
  assert.match(rich.bodyHTML, /<span style="font-size:14pt;color:#232D3D">默认正文<\/span>/);
  assert.match(rich.bodyHTML, /<li style="font-size:28pt;color:#232D3D"><br \/><\/li>/);
  assert.match(rich.bodyHTML, /<ul><li style="font-size:36pt;color:#232D3D">/);
  assert.deepEqual(richFromHTML(rich.bodyHTML), rich);
  const parsed = await simpleParser(await new MailComposer({
    from: 'me@example.test', to: 'you@example.test', ...draftContent(rich),
  }).compile().build());
  assert.deepEqual(richFromHTML(parsed.html), rich);
});

test('server HTML imports only safe literal styles and scopes inheritance to the matching element', () => {
  const imported = richFromHTML('<div style="font-size:24px;color:#b42318">'
    + '<strong>重点</strong><span style="font-size:32pt;color:rgb(53, 103, 175)">大字</span>恢复'
    + '<span style="font-size:14pt;color:#232d3d">默认</span></div>'
    + '<p><font size="5" color="#abc">旧格式</font>'
    + '<span style="font-size:999pt;color:url(https://example.test)">普通</span></p>');
  const runs = imported.richText.blocks[0].runs;
  assert.deepEqual(runs.map(run => [run.fontSize, run.color]), [[18, '#B42318'], [32, '#3567AF'], [18, '#B42318'], [undefined, undefined]]);
  assert.equal(runs[0].bold, true);
  assert.deepEqual(imported.richText.blocks[1].runs.map(run => [run.fontSize, run.color]), [[18, '#AABBCC'], [undefined, undefined]]);
  assert.doesNotMatch(imported.bodyHTML, /url\(|999|<font/);
  for (const color of ['expression(alert(1))', '#fff;display:none', 'transparent', 'constructor', '__proto__']) {
    assert.throws(() => richContent({ blocks: [{ kind: 'paragraph', runs: [{ text: '正文', color }] }] }), /颜色/);
    assert.doesNotMatch(richFromHTML(`<p style="color:${color}">正文</p>`).bodyHTML, /url\(|expression|display|constructor|__proto__/);
  }
  for (const fontSize of [0, 7, 73, Infinity, NaN, '24', {}])
    assert.throws(() => richContent({ blocks: [{ kind: 'paragraph', runs: [{ text: '正文', fontSize }] }] }), /字号/);
});

test('draft API retains rich bodies and forward snapshots, rejects stale edits and keeps lightweight state/search', async t => {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-rich-draft-'));
  const token = 'boxmail-rich-text-fixture-20261109';
  const app = await startServer({ directory, token, demo: false });
  t.after(async () => { await app.close(); await rm(directory, { recursive: true, force: true }); });
  app.repo.put('account', { id: 'a1', name: '本人', email: 'me@example.test', isDemo: true });
  const request = async (route, body) => {
    const response = await fetch(`http://127.0.0.1:${app.port}${route}`, { method: body ? 'POST' : 'GET',
      headers: { 'X-Boxmail-Token': token, 'Content-Type': 'application/json' }, ...(body ? { body: JSON.stringify(body) } : {}) });
    return { status: response.status, body: await response.json() };
  };
  const input = { id: 'd1', accountId: 'a1', to: '', body: '', richText: document,
    forwardedHTML: '<blockquote>转发原文</blockquote>', forwardedText: '转发原文', attachmentIds: [] };
  const saved = await request('/drafts', input);
  assert.equal(saved.status, 200); assert.match(saved.body.bodyHTML, /<strong>/);
  assert.equal(saved.body.forwardedText, '转发原文'); assert.ok(saved.body.revision);
  const opened = await request('/drafts/d1');
  assert.deepEqual(opened.body.richText, richContent(document).richText);
  const edited = { ...saved.body, richText: undefined, bodyHTML: undefined, body: '新编辑' };
  const next = await request('/drafts', edited); assert.equal(next.status, 200);
  assert.equal((await request('/drafts', edited)).status, 200, 'lost acknowledgement can retry identical content');
  const stale = await request('/drafts', { ...saved.body, subject: '迟到的修改' });
  assert.equal(stale.status, 409); assert.equal(app.repo.get('draft', 'd1').body, '新编辑');
  await request('/drafts', { ...next.body, richText: document, body: '' });
  const state = await request('/state?compact=1');
  for (const key of ['richText', 'bodyHTML', 'forwardedHTML', 'forwardedText', 'remoteDraft', 'remotePending'])
    assert.equal(state.body.drafts[0][key], undefined);
  const search = await request('/messages?folder=drafts&q=核对合同');
  assert.equal(search.body.total, 1);
  assert.equal(search.body.messages[0].body, ''); assert.equal(search.body.messages[0].html, undefined);
  const original = { id: 'mail', accountId: 'a1', sender: '原发件人', senderEmail: 'sender@example.test',
    date: '2026-11-09T00:00:00Z', subject: '原主题', body: '引用原文' };
  app.repo.put('message', original);
  app.repo.put('draft', { id: 'legacy', accountId: 'a1', to: '', cc: '', bcc: '', subject: 'Fwd: 原主题',
    body: '转发说明\n\n' + forwardText(original), sourceMessageId: 'mail', attachmentIds: [],
    status: 'draft', updatedAt: new Date().toISOString() });
  const legacy = await request('/drafts/legacy');
  assert.equal(legacy.body.body, '转发说明');
  const upgraded = await request('/drafts', { ...legacy.body, body: '修改后的说明' });
  assert.equal(upgraded.status, 200, 'legacy snapshot upgrades do not falsely conflict with their own editor revision');
  assert.equal(upgraded.body.body, '修改后的说明'); assert.match(upgraded.body.forwardedText, /引用原文/);
});
