import { createHash } from 'node:crypto';
import { ServiceError } from './validation.js';
import { conversationContext, requireFreshConversation } from './conversation-ai.js';

const fingerprint = message => createHash('sha256').update(JSON.stringify([message.subject, message.body, message.html])).digest('hex');

export function writingPreview(repo, input, message) {
  const scope = input.writingScope;
  if (!['selection', 'body', 'new', 'source', 'thread'].includes(scope))
    throw new ServiceError('请选择写作范围');
  const expected = { selection: 'compose', body: 'compose', new: 'compose', source: 'reply', thread: 'conversationReply' };
  if (expected[scope] !== input.task || (['source', 'thread'].includes(scope) && (!message || input.preview !== true))
    || (['selection', 'body', 'new'].includes(scope) && message))
    throw new ServiceError('写作请求与原草稿范围不符');
  const request = typeof input.prompt === 'string' ? input.prompt.trim() : '';
  if (!request) throw new ServiceError('请填写写作要求');
  const context = { request, tone: input.tone || '正式', length: input.length || '适中',
    outputLanguage: input.outputLanguage || '跟随来信', writingStyle: input.writingStyle || '' };
  const source = scope === 'source' ? fingerprint(message) : null;
  const conversation = scope === 'thread' ? conversationContext(repo, message.id, { includeAttachments: false }) : null;
  if (conversation) {
    Object.assign(context, { messages: conversation.sources.map(({ id, subject, body }) => ({ id, subject, body })),
      total: conversation.total, partial: conversation.partial, cachedOnly: true, replyMessageId: message.id });
    conversation.replyMessageId = message.id;
  } else if (scope === 'source') {
    Object.assign(context, { subject: message.subject, body: message.body });
  } else if (scope === 'new') {
    context.subject = typeof input.subject === 'string' ? input.subject : '';
  } else {
    if (typeof input.body !== 'string' || !input.body.trim()) throw new ServiceError('请输入要修改的文字');
    context.body = input.body;
  }
  return { context, source, conversation };
}

export function validateWritingPreview(repo, job) {
  if (!job?.writingScope || job.status !== 'completed') throw new ServiceError('写作候选已失效，请重新生成', 409);
  if (job.writingScope === 'thread') requireFreshConversation(repo, job);
  if (job.writingScope === 'source') {
    const message = repo.get('message', job.messageId);
    if (!message || message.accountId !== job.accountId || fingerprint(message) !== job.writingSource)
      throw new ServiceError('原邮件内容已变化，请重新生成', 409);
  }
  return { ok: true };
}
