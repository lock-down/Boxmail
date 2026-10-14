import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { completion } from './responses.js';
import { modelAttachment } from './attachments.js';
export { completion } from './responses.js';

function strings(v) {
  return Array.isArray(v)
    ? v.filter((x) => typeof x === 'string').slice(0, 12)
    : [];
}
export async function runAgent(repo, input) {
  const message = input.messageId ? repo.get('message', input.messageId) : null;
  const task = input.task;
  let context;
  if (['summary', 'reply', 'translate'].includes(task)) {
    if (!message) throw new ServiceError('请选择邮件');
    context = {
      sender: message.sender,
      subject: message.subject,
      date: message.date,
      body: message.body,
      request: input.prompt || '',
      attachments: message.attachmentIds.map((id) => {
        const a = repo.get('attachment', id);
        return { name: a?.name, text: a?.text?.slice(0, 16000), analysis: a?.analysis?.slice(0, 16000) };
      }),
    };
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
    context = {
      name: a.name,
      text: a.text.slice(0, 60000),
      textTruncated: a.text.length > 60000,
      request: input.prompt || '',
    };
  } else
    context = {
      request: input.prompt || '',
      body: input.body || '',
      tone: input.tone || '正式',
      length: input.length || '适中',
    };
  const job = {
    id: randomUUID(),
    task,
    status: 'running',
    accountId: input.accountId || message?.accountId || null,
    messageId: input.messageId || null,
    createdAt: new Date().toISOString(),
    result: null,
    error: null,
  };
  repo.put('job', job);
  try {
    let images = [];
    if (task === 'attachment') {
      const prepared = await modelAttachment(repo, input.attachmentId);
      images = prepared.images;
      context.inputKind = prepared.kind;
      if (prepared.pages) {
        context.pages = prepared.pages;
        context.pageOrder = '输入图片按照文档页码从第 1 页开始依次排列';
      }
    }
    const result = await completion(input.config, input.apiKey, task, context, images);
    if (task === 'summary') {
      if (!strings(result.points).length)
        throw new ServiceError('摘要格式不正确', 502);
      const summary = {
        points: strings(result.points),
        todos: Array.isArray(result.todos)
          ? result.todos
              .filter((t) => typeof t.title === 'string')
              .slice(0, 12)
              .map((t) => ({
                id: randomUUID(),
                title: t.title,
                due: String(t.due || ''),
                done: false,
              }))
          : [],
        keyInfo: Array.isArray(result.keyInfo)
          ? result.keyInfo
              .filter(
                (x) =>
                  typeof x.label === 'string' && typeof x.value === 'string',
              )
              .slice(0, 10)
          : [],
      };
      const current = repo.get('message', message.id);
      if (!current)
        throw new ServiceError('邮件已移动，请在新文件夹中重新总结', 409);
      repo.put('message', { ...current, summary });
      job.result = summary;
    } else if (['reply', 'compose'].includes(task)) {
      if (typeof result.body !== 'string' || typeof result.subject !== 'string')
        throw new ServiceError('邮件草稿格式不正确', 502);
      job.result = { subject: result.subject, body: result.body };
      if (task === 'reply') {
        const draft = {
          id: randomUUID(),
          accountId: message.accountId,
          to: message.senderEmail,
          cc: '',
          bcc: '',
          subject: result.subject,
          body: result.body,
          attachmentIds: [],
          inReplyTo: message.messageId || '',
          status: 'draft',
          updatedAt: new Date().toISOString(),
          sourceMessageId: message.id,
        };
        repo.put('draft', draft);
        job.result.draftId = draft.id;
      }
    } else if (task === 'classify') {
      const ids = new Set(context.map((m) => m.id));
      const categories = [
        '工作项目',
        '订阅资讯',
        '账单票据',
        '社交通知',
        '个人往来',
        '未分类',
      ];
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
    } else {
      if (typeof result.text !== 'string')
        throw new ServiceError('解析内容格式不正确', 502);
      job.result = { text: result.text };
      if (task === 'attachment') {
        const a = repo.get('attachment', input.attachmentId);
        repo.put('attachment', { ...a, analysis: result.text });
      }
    }
    if (job.status !== 'needsApproval') job.status = 'completed';
    repo.put('job', job);
    repo.event('agent', `${task}：${job.status}`);
    return job;
  } catch (e) {
    job.status = 'failed';
    job.error = e.message;
    repo.put('job', job);
    throw e;
  }
}
export function approveClassification(repo, id, undo = false) {
  const job = repo.get('job', id);
  if (
    !job ||
    job.task !== 'classify' ||
    job.status !== (undo ? 'applied' : 'needsApproval')
  )
    throw new ServiceError('该整理任务不能执行此操作', 409);
  repo.transaction(() => {
    if (undo) {
      for (const p of job.result.previous) {
        const m = repo.get('message', p.id);
        if (m) repo.put('message', { ...m, category: p.category });
      }
      job.status = 'undone';
    } else {
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
