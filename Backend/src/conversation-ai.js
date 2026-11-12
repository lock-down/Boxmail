import { createHash } from 'node:crypto';
import { conversationMembers, conversationFingerprint } from './threads.js';
import { ServiceError } from './validation.js';
import { textSlice } from './unicode.js';

const bodyHash = message => createHash('sha256').update(JSON.stringify([message.body, message.html])).digest('hex');

export function conversationContext(repo, messageId) {
  const thread = conversationMembers(repo, messageId);
  const chronological = [...thread.members].sort((a, b) => (Date.parse(b.date) || 0) - (Date.parse(a.date) || 0) || a.id.localeCompare(b.id));
  const included = chronological.slice(0, 50);
  if (!included.some(message => message.id === messageId)) included[included.length - 1] = thread.members[0];
  const attachmentIDs = [...new Set(included.flatMap(message => (message.attachmentIds || []).slice(0,20)))];
  const names = new Map(repo.db.prepare("SELECT id,json_extract(data,'$.name') AS name FROM records WHERE kind='attachment' AND id IN (SELECT value FROM json_each(?))").all(JSON.stringify(attachmentIDs)).map(row => [row.id,row.name]));
  let remaining = 120000;
  const sources = included.map(header => {
    const message = repo.get('message', header.id);
    const body = textSlice(message.body || '', 0, Math.max(0, Math.min(16000, remaining)));
    remaining -= body.length;
    return { id: message.id, sender: message.sender, senderEmail: message.senderEmail, to: message.to,
      subject: message.subject, date: message.date, body, bodyTruncated: body.length < (message.body?.length || 0),
      attachments: (message.attachmentIds || []).slice(0, 20).map(id => {
        const name = names.get(id);
        return typeof name === 'string' ? textSlice(name, 0, 256) : null;
      }).filter(Boolean),
      attachmentsTruncated: (message.attachmentIds?.length || 0) > 20,
      contentHash: bodyHash(message) };
  }).reverse();
  return { conversationId: thread.id, contextFingerprint: conversationFingerprint(repo, thread),
    replyMessageId: chronological[0].id, sources, total: thread.members.length,
    partial: thread.partial || sources.length < thread.members.length
      || sources.some(source => source.bodyTruncated || source.attachmentsTruncated) };
}

export function conversationResult(result, context, task) {
  const ids = new Set(context.sources.map(source => source.id));
  const citations = value => {
    if (!Array.isArray(value) || !value.length || value.length > 50
      || value.some(id => typeof id !== 'string' || !ids.has(id)))
      throw new ServiceError('会话结果缺少有效的依据邮件，未保存该结果，请重新生成。', 502);
    return [...new Set(value)];
  };
  let answer;
  if (task === 'conversationReply') {
    if (typeof result.body !== 'string' || !result.body.trim() || result.body.length > 500000
      || typeof result.subject !== 'string' || result.subject.length > 2000)
      throw new ServiceError('会话回复格式不正确，未保存草稿。', 502);
    answer = { subject: result.subject, body: result.body, sourceIds: citations(result.sourceIds) };
  } else {
    answer = {};
    for (const key of ['progress', 'openItems', 'nextSteps']) {
      if (!Array.isArray(result[key]) || result[key].length > 20)
        throw new ServiceError('会话总结格式不正确，未保存该结果。', 502);
      answer[key] = result[key].map(item => {
        if (!item || typeof item.text !== 'string' || !item.text.trim() || item.text.length > 4000)
          throw new ServiceError('会话总结条目无效，未保存该结果。', 502);
        return { text: item.text, messageIds: citations(item.messageIds) };
      });
    }
    if (!answer.progress.length && !answer.openItems.length && !answer.nextSteps.length)
      throw new ServiceError('会话总结为空，请重新生成。', 502);
  }
  const { nextSteps, ...fields } = answer;
  return { ...fields, ...(nextSteps ? { conversationNextSteps: nextSteps } : {}),
    conversationId: context.conversationId, contextFingerprint: context.contextFingerprint,
    replyMessageId: context.replyMessageId, partial: context.partial, total: context.total,
    sourceMessages: context.sources.map(({ body, attachments, bodyTruncated, ...source }) => source) };
}

export function requireFreshConversation(repo, job) {
  const current = conversationMembers(repo, job.messageId);
  if (conversationFingerprint(repo, current) !== job.result?.contextFingerprint
    || !Array.isArray(job.result?.sourceMessages) || job.result.sourceMessages.some(source => {
      const message = repo.get('message', source.id);
      return !message || message.accountId !== job.accountId || bodyHash(message) !== source.contentHash;
    })) throw new ServiceError('会话已有新邮件或内容变化，请刷新会话回复预览后再使用。', 409);
}
