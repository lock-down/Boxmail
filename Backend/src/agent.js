import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { completion } from './responses.js';
import { modelAttachment } from './attachments.js';
import { REVIEWABLE } from './organizer.js';
import { REPLY_PRESETS } from './reply-presets.js';
import { buildReplyDraft } from './reply.js';
import { summaryResult } from './summary.js';
import { categoryCatalog } from './categories.js';
import { progressText } from './ai-progress.js';
import { translationDocument } from './translation.js';
export { completion } from './responses.js';

export async function runAgent(repo, input, { jobId = randomUUID() } = {}) {
  const message = input.messageId ? repo.get('message', input.messageId) : null;
  if (input.messageId && !message) throw new ServiceError('邮件不存在', 404);
  if (message && input.accountId && message.accountId !== input.accountId)
    throw new ServiceError('邮件不属于当前账户', 400);
  const task = input.task;
  const translation = task === 'translate' && message ? translationDocument(message) : null;
  const preset = task === 'reply' && typeof input.replyPreset === 'string'
    ? Object.hasOwn(REPLY_PRESETS, input.replyPreset) && REPLY_PRESETS[input.replyPreset] : null;
  if (task === 'reply' && input.replyPreset != null && !preset)
    throw new ServiceError('未知回复选项');
  let context;
  if (['summary', 'reply', 'translate'].includes(task)) {
    if (!message) throw new ServiceError('请选择邮件');
    context = {
      sender: message.sender,
      subject: message.subject,
      date: message.date,
      body: message.body,
      request: input.prompt || '',
      ...(preset ? { replyIntent: preset.title } : {}),
      attachments: message.attachmentIds.map((id) => {
        const a = repo.get('attachment', id);
        return { name: a?.name, text: a?.text?.slice(0, 16000), analysis: a?.analysis?.slice(0, 16000),
          textTruncated: (a?.text?.length || 0) > 16000, analysisTruncated: (a?.analysis?.length || 0) > 16000 };
      }),
    };
    if (translation) context = { subject: message.subject, segments: translation.segments };
  } else if (task === 'classify') {
    context = repo
      .list('message')
      .filter(
        (m) =>
          m.folder === 'inbox' &&
          (!input.accountId || m.accountId === input.accountId),
      )
      .slice(0, 80)
      .map((m) => ({
        id: m.id,
        subject: m.subject,
        sender: m.sender,
        body: m.body.slice(0, 1000),
      }));
  } else if (task === 'attachment') {
    const a = repo.get('attachment', input.attachmentId);
    if (!a) throw new ServiceError('附件不存在', 404);
    if (message && (!message.attachmentIds.includes(a.id) || a.messageId !== message.id))
      throw new ServiceError('该附件不属于当前邮件', 400);
    context = {
      name: a.name,
      text: a.text.slice(0, 60000),
      textTruncated: a.text.length > 60000,
      request: input.prompt || '',
      email: message ? { subject: message.subject, sender: message.sender, body: message.body.slice(0, 5000) } : undefined,
    };
  } else
    context = {
      request: input.prompt || '',
      body: input.body || '',
      tone: input.tone || '正式',
      length: input.length || '适中',
    };
  const job = {
    id: jobId,
    task,
    status: 'running',
    accountId: input.accountId || message?.accountId || null,
    messageId: input.messageId || (task === 'attachment' ? repo.get('attachment', input.attachmentId)?.messageId : null) || null,
    attachmentId: input.attachmentId || null,
    ...(input.parentJobId ? { parentJobId: input.parentJobId } : {}),
    ...(task === 'reply' ? { replyPreset: input.replyPreset || null, preview: input.preview === true } : {}),
    createdAt: new Date().toISOString(),
    result: null,
    error: null,
  };
  repo.put('job', job);
  let live = { id: job.id, task, status: 'running', accountId: job.accountId,
    messageId: job.messageId, attachmentId: job.attachmentId, parentJobId: input.parentJobId || null,
    text: '', stage: task === 'attachment' ? '正在读取附件内容…' : '正在等待模型输出…' };
  const publish = changes => { live = { ...live, ...changes }; input.onProgress?.(live); };
  publish({});
  try {
    input.signal?.throwIfAborted();
    let images = [];
    let extractedText;
    if (task === 'attachment') {
      const prepared = await modelAttachment(repo, input.attachmentId, { signal: input.signal });
      images = prepared.images;
      context.inputKind = prepared.kind;
      if (prepared.text !== undefined) {
        extractedText = prepared.text;
        context.text = extractedText.slice(0, 60000);
        context.textTruncated = extractedText.length > 60000;
      }
      if (prepared.pages) {
        context.pages = prepared.pages;
        context.pageOrder = '输入图片按照文档页码从第 1 页开始依次排列';
      }
    }
    input.signal?.throwIfAborted();
    publish({ stage: '正在等待模型输出…' });
    const result = translation && !translation.segments.length ? { segments: [] } : await completion(input.config, input.apiKey, task, context, images,
      { additionalInstructions: preset?.instruction, stream: true, signal: input.signal,
        diagnostics: repo.diagnostics,
        onProgress: partial => {
          const rendered = translation ? translation.render(partial) : null;
          publish({ text: rendered?.text ?? progressText(task, partial),
            ...(rendered?.html ? { html: rendered.html } : {}), stage: '正在生成…' });
        },
        ...(task === 'classify' ? { categories: categoryCatalog(repo) } : {}) });
    input.signal?.throwIfAborted();
    if (task === 'summary') {
      const summary = summaryResult(result, message);
      const current = repo.get('message', message.id);
      if (!current)
        throw new ServiceError('邮件已移动，请在新文件夹中重新总结', 409);
      repo.put('message', { ...current, summary, summaryHidden: false });
      job.result = summary;
    } else if (['reply', 'compose'].includes(task)) {
      if (typeof result.body !== 'string' || !result.body.trim() || typeof result.subject !== 'string')
        throw new ServiceError('邮件草稿格式不正确', 502);
      job.result = { subject: result.subject, body: result.body };
      if (task === 'reply' && !job.preview) {
        const draft = replyDraft(message, result, repo.get('account', message.accountId));
        repo.put('draft', draft);
        job.result.draftId = draft.id;
      }
    } else if (task === 'classify') {
      const ids = new Set(context.map((m) => m.id));
      const categories = categoryCatalog(repo).map(item => item.name);
      if (!Array.isArray(result.items))
        throw new ServiceError('分类格式不正确', 502);
      const unique = new Map(
        result.items
          .filter((i) => ids.has(i.id) && categories.includes(i.category))
          .map((i) => [
            i.id,
            { id: i.id, category: i.category, reason: String(i.reason || '') },
          ]),
      );
      job.result = { items: [...unique.values()], previous: [] };
      job.status = 'needsApproval';
    } else if (task === 'translate') {
      const rendered = translation.render(result, true);
      const current = repo.get('message', message.id);
      if (!current) throw new ServiceError('邮件已移动，请重新打开邮件', 409);
      repo.put('message', { ...current, translation: rendered.text, translationHTML: rendered.html || null });
      job.result = { text: rendered.text };
    } else {
      if (typeof result.text !== 'string' || !result.text.trim())
        throw new ServiceError('解析内容格式不正确', 502);
      job.result = { text: result.text };
      if (task === 'attachment') {
        const a = repo.get('attachment', input.attachmentId);
        const current = repo.get('message', repo.get('job', job.id)?.messageId);
        if (!a || (message && (!current?.attachmentIds.includes(a.id) || a.messageId !== current.id)))
          throw new ServiceError('附件已移动或移除，请重新打开邮件后重试。', 409);
        job.messageId = current?.id || job.messageId;
        repo.put('attachment', { ...a, ...(extractedText !== undefined ? { text: extractedText, parseError: '' } : {}), analysis: result.text });
      }
    }
    if (job.status !== 'needsApproval') job.status = 'completed';
    repo.put('job', job);
    repo.event('agent', `${task}：${job.status}`);
    publish({ status: job.status });
    return job;
  } catch (e) {
    job.status = 'failed';
    job.error = e.message;
    repo.put('job', job);
    publish({ status: 'failed', text: '', html: null });
    throw e;
  }
}
function replyDraft(message, result, account) {
  return buildReplyDraft(message, account, { subject: result.subject, body: result.body });
}

export function useReplyPreview(repo, id) {
  const job = repo.get('job', id);
  if (!job || job.task !== 'reply' || !job.preview || job.status !== 'completed'
    || typeof job.result?.body !== 'string' || !job.result.body.trim())
    throw new ServiceError('该回复预览尚不可使用', 409);
  return repo.transaction(() => {
    if (job.result.draftId) {
      const existing = repo.get('draft', job.result.draftId);
      if (!existing || existing.status !== 'draft') throw new ServiceError('该草稿已删除或已进入发送流程，请重新生成', 409);
      return existing;
    }
    const message = repo.get('message', job.messageId);
    if (!message) throw new ServiceError('原邮件不存在，请重新打开邮件生成回复', 404);
    const draft = replyDraft(message, job.result, repo.get('account', message.accountId));
    repo.put('draft', draft);
    job.result.draftId = draft.id;
    repo.put('job', job);
    repo.event('draft', '已将 AI 回复预览保存为待审核草稿');
    return draft;
  });
}
export function approveClassification(repo, id, undo = false) {
  const job = repo.get('job', id);
  if (
    !job ||
    job.task !== 'classify' ||
    !job.result?.items?.length ||
    !(undo ? job.status === 'applied' : REVIEWABLE.includes(job.status))
  )
    throw new ServiceError('该整理任务不能执行此操作', 409);
  repo.transaction(() => {
    if (undo) {
      const applied = new Map(job.result.items.map(item => [item.id, item.category]));
      for (const p of job.result.previous || []) {
        if (p.category === applied.get(p.id)) continue;
        const m = repo.get('message', p.id);
        if (m) {
          if (m.category !== applied.get(p.id))
            throw new ServiceError('邮件分类已更改，未覆盖后续修改，无法撤销本次整理', 409);
          repo.put('message', { ...m, category: p.category });
        }
      }
      job.status = 'undone';
    } else {
      job.result.previous = [];
      for (const item of job.result.items) {
        const m = repo.get('message', item.id);
        if (m) {
          job.result.previous.push({ id: m.id, category: m.category });
          repo.put('message', { ...m, category: item.category });
        }
      }
      job.status = 'applied';
    }
    repo.put('job', job);
    repo.event('organize', undo ? '已撤销邮件分类' : '已确认邮件分类');
  });
  return job;
}
