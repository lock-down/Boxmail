import { randomUUID } from 'node:crypto';
import { completion } from './responses.js';
import { mailQuery } from './mail-query.js';
import { prepareAssistantContext } from './assistant-context.js';
import { ASSISTANT_FOLDERS, readAssistantSource } from './assistant-sources.js';
import { updateMessageBatch } from './mail-batch.js';
import { createReplyDraft } from './reply.js';
import { categoryCatalog } from './categories.js';
import { ServiceError } from './validation.js';

export class MailAssistant {
  constructor(repo, credentials, followUps, { complete = completion, locks = new Set(), onProgress } = {}) {
    this.repo = repo; this.credentials = credentials; this.followUps = followUps; this.complete = complete; this.locks = locks;
    this.controller = new AbortController(); this.active = new Map();
    this.onProgress = onProgress;
  }
  create(input) {
    const scope = input.scope;
    if (!scope || !['folder', 'message', 'conversation', 'search', 'attachments'].includes(scope.kind)) throw new ServiceError('请选择问答范围');
    if (scope.kind === 'folder') {
      const { accountId, folder } = scope.query ?? {};
      if (!ASSISTANT_FOLDERS.includes(folder)) throw new ServiceError('请选择要查阅的邮件文件夹');
      scope.query = mailQuery({ accountId, folder });
    } else if (scope.kind === 'search') scope.query = mailQuery(scope.query);
    else if (scope.kind === 'attachments') {
      if (!Array.isArray(scope.attachmentIds) || new Set(scope.attachmentIds).size < 2 || !String(scope.relationship || '').trim())
        throw new ServiceError('请选择至少两个附件，并说明它们的比较关系');
      scope.attachmentIds = [...new Set(scope.attachmentIds)];
      const messages = new Set(scope.attachmentIds.map(id => this.repo.get('attachment', id)?.messageId));
      if (messages.has(undefined) || messages.size < 2) throw new ServiceError('跨邮件比较需要不同邮件的附件');
    } else if (!this.repo.get('message', scope.messageId)) throw new ServiceError('来源邮件不存在', 404);
    return this.repo.put('assistantSession', { id: randomUUID(), scope, createdAt: new Date().toISOString(), turns: [] });
  }
  async plan(input) {
    const id = randomUUID(), request = this.planQuery(input);
    this.active.set(id, { promise: request });
    try { return await request; } finally { this.active.delete(id); }
  }
  async planQuery(input) {
    const ai = this.credentials.ai();
    const result = await this.complete(ai.config, ai.apiKey, 'searchPlan', {
      request: String(input.prompt || ''), current: mailQuery(input.query),
      accounts: this.repo.list('account').map(({ id, email }) => ({ id, email })),
      syntax: 'from: to: cc: subject: after:YYYY-MM-DD before:YYYY-MM-DD is:unread/read/starred has:attachment account: folder: category:',
    }, [], { repository: this.repo, signal: this.controller.signal });
    return { query: mailQuery({ ...input.query, query: result.query }), explanation: String(result.explanation || '') };
  }
  get(id) {
    const session = this.repo.get('assistantSession', id);
    if (!session) throw new ServiceError('问答记录不存在', 404);
    return session;
  }
  async ask(id, prompt) {
    if (this.active.has(id)) throw new ServiceError('本轮正在回答，请等待完成', 409);
    if (!String(prompt || '').trim()) throw new ServiceError('请填写问题');
    const session = this.get(id);
    const controller = new AbortController();
    const signal = AbortSignal.any([this.controller.signal, controller.signal]);
    const output = { id: `assistant-${id}`, task: session.scope.kind === 'attachments' ? 'compare' : 'question',
      status: 'running', text: '', stage: '正在查阅邮件与附件…' };
    const publish = changes => { Object.assign(output, changes); this.onProgress?.({ ...output }); };
    publish({});
    const promise = this.answer(session, prompt, publish, signal);
    this.active.set(id, { promise, controller });
    try {
      const answered = await promise;
      publish({ status: 'completed', text: answered.turns.at(-1).text });
      return answered;
    } catch (error) {
      publish({ status: controller.signal.aborted ? 'cancelled' : 'failed', text: '', stage: error.message });
      throw error;
    } finally { this.active.delete(id); }
  }
  stop(id) {
    this.active.get(id)?.controller?.abort(new ServiceError('已停止回答', 409));
    return { ok: true };
  }
  async answer(session, prompt, publish, signal) {
    const { scope } = session;
    const ai = this.credentials.ai();
    const task = scope.kind === 'attachments' ? 'compare' : 'question';
    const run = async compact => {
      publish({ stage: compact ? '正在缩减上下文并重新查询…' : '正在本机查找相关邮件…' });
      const context = await prepareAssistantContext(this.repo, ai.config, session, prompt, { signal, publish, compact });
      signal.throwIfAborted();
      this.validateSources(context.original, scope);
      publish({ stage: '正在等待模型输出…' });
      const result = await this.complete(ai.config, ai.apiKey, task, context.content, context.images, {
        ...context.options, repository: this.repo, signal, taskId: `assistant-${session.id}`,
        onProgress: partial => publish({ text: typeof partial.text === 'string' ? partial.text : '', stage: '正在回答…' }),
      });
      signal.throwIfAborted();
      this.validateSources(context.original, scope);
      return { ...context, result };
    };
    let answer;
    try { answer = await run(false); }
    catch (error) {
      if (error.code !== 'MODEL_CONTEXT_LIMIT' || signal.aborted) throw error;
      answer = await run(true);
    }
    const { content, original, result, sources } = answer;
    if (typeof result.text !== 'string' || !result.text.trim()) throw new ServiceError('模型未返回有效回答', 502);
    const evidence = new Map(content.documents.map(document => [document.id, new Set(document.attachments.map(file => file.id))]));
    const citations = (Array.isArray(result.citations) ? result.citations : []).filter(item => item
      && evidence.has(item.messageId) && (!item.attachmentId || evidence.get(item.messageId).has(item.attachmentId)));
    if (!citations.length) throw new ServiceError('回答缺少范围内的有效来源，请缩小范围后重试', 502);
    const actionable = new Set(sources.filter(source => !source.draft).map(source => source.id));
    const actions = (Array.isArray(result.actions) ? result.actions : []).filter(action =>
      action && ['category', 'draft', 'followUp'].includes(action.kind) && Array.isArray(action.messageIds)
      && action.messageIds.length && action.messageIds.every(id => actionable.has(id))
      && (action.kind !== 'category' || categoryCatalog(this.repo).some(item => item.name === action.category))
      && (action.kind !== 'followUp' || typeof action.title === 'string' && action.title.trim()))
      .map(action => ({ id: randomUUID(), kind: action.kind, messageIds: [...new Set(action.messageIds)],
        category: action.category || null, title: action.title || null, status: 'proposed',
        expected: Object.fromEntries(action.messageIds.map(id => [id, { category: original.get(id).category }])) }));
    session.turns.push({ id: randomUUID(), prompt, text: result.text, scope, sources, citations, actions,
      createdAt: new Date().toISOString(), cachedOnly: true, contextCoverage: content.contextCoverage });
    return this.repo.put('assistantSession', session);
  }
  validateSources(original, scope) {
    for (const [id, source] of original) {
      const current = readAssistantSource(this.repo, id);
      if (!current || current.body !== source.body || current.html !== source.html
        || (scope.kind === 'folder' && (current.folder !== source.folder
          || scope.query.folder === 'starred' && !current.starred))
        || (scope.kind !== 'attachments' && current.attachmentIds.length !== source.attachments.length)
        || source.attachments.some(([id, path, size]) => {
          const file = this.repo.get('attachment', id);
          return !current.attachmentIds.includes(id) || file?.path !== path || file?.size !== size;
        })) throw new ServiceError('来源邮件或附件在回答期间已变化，请按当前范围重新查询', 409);
    }
  }
  apply(id, turnId, actionId, approved) {
    if (approved !== true) throw new ServiceError('采用建议需要明确确认', 403);
    const session = this.get(id), turn = session.turns.find(turn => turn.id === turnId);
    const action = turn?.actions.find(action => action.id === actionId);
    if (!action) throw new ServiceError('建议不存在', 404);
    if (action.status === 'applied') return session;
    this.repo.transaction(() => {
      for (const id of action.messageIds) if (!this.repo.get('message', id)) throw new ServiceError('来源邮件已移除，请重新查询', 409);
      if (action.kind === 'category') {
        action.result = updateMessageBatch(this.repo, { updates: action.messageIds.map(id => ({ id, changes: { category: action.category }, expected: action.expected?.[id] })) }, this.locks);
      } else if (action.kind === 'followUp') action.result = action.messageIds.map(messageId => this.followUps.save({
        messageId, title: action.title, sourceKey: `assistant:${action.id}`, state: 'mine' }));
      else action.result = action.messageIds.map(id => createReplyDraft(this.repo, id));
      action.status = 'applied'; this.repo.put('assistantSession', session);
    });
    return session;
  }
  async close() {
    this.controller.abort();
    await Promise.allSettled([...this.active.values()].map(({ promise }) => promise));
  }
}
