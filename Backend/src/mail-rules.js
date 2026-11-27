import { createHash, randomUUID } from 'node:crypto';
import { setImmediate as yieldToRequests } from 'node:timers/promises';
import { ServiceError } from './validation.js';
import { mailQuery, ruleRevision } from './mail-query.js';
import { updateMessageBatch } from './mail-batch.js';
import { runAgent } from './agent.js';
import { categoryCatalog, organizationLabelMode } from './categories.js';
import { completion } from './responses.js';
import { parseSearch } from './search-query.js';

export const hasAutomaticAIActions = actions => ['summary', 'attachments', 'followUp', 'reply'].some(key => actions[key] === true);
export const automaticAIPauseReason = '包含 AI 动作。可改为普通邮箱规则，或在清单中单独开启新邮件自动整理。';
export function pausedAutomaticAIRule(rule) {
  return rule.automatic && hasAutomaticAIActions(rule.actions)
    ? { ...rule, automatic: false, automaticPauseReason: automaticAIPauseReason } : rule;
}

const ruleFolders = ['all', 'inbox', 'sent', 'archive', 'trash', 'spam'];
const fingerprint = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export class MailRules {
  constructor(repo, credentials, { locks = new Set(), agent = runAgent, onProgress, complete = completion } = {}) {
    this.repo = repo; this.credentials = credentials; this.locks = locks; this.agent = agent; this.onProgress = onProgress; this.complete = complete;
    this.drafting = new Set();
    this.draftController = new AbortController();
    for (const rule of repo.list('mailRule')) {
      const next = pausedAutomaticAIRule(rule);
      if (next !== rule) repo.put('mailRule', next);
    }
    this.worker = null; this.controller = new AbortController(); this.closing = false;
    for (const run of repo.list('ruleRun').filter(run => run.status === 'running'))
      repo.put('ruleRun', { ...run, status: 'paused', items: run.items.map(item => item.status === 'running'
        ? { ...item, status: 'failed', error: '应用退出中断了处理，可重试' } : item) });
  }
  list() { return this.repo.list('mailRule').sort((a, b) => a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id)); }
  listRuns() {
    const jobIds = new Set(this.repo.db.prepare("SELECT id FROM records WHERE kind='job'").all().map(row => row.id));
    return this.repo.list('ruleRun').sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .map(run => ({ ...run, items: run.items.map(item => ({
        ...item, jobIds: item.jobIds.filter(id => jobIds.has(id)),
      })) }));
  }
  save(input, id) {
    return this.repo.put('mailRule', this.validatedRule(input, id));
  }

  validatedRule(input, id) {
    const old = id && this.repo.get('mailRule', id);
    if (id && !old) throw new ServiceError('规则不存在', 404);
    const name = String(input.name || '').trim();
    if (!name) throw new ServiceError('请填写规则名称');
    const query = mailQuery(input.query);
    if (query.fixedScope && query.accountId && !this.repo.get('account', query.accountId))
      throw new ServiceError('规则邮箱不存在', 409);
    const actions = input.actions;
    if (!actions || typeof actions !== 'object' || Array.isArray(actions)
      || Object.keys(actions).some(key => !['category', 'starred', 'unread', 'archive', 'summary', 'attachments', 'followUp', 'reply'].includes(key))
      || !Object.keys(actions).length) throw new ServiceError('请选择规则动作');
    for (const [key, value] of Object.entries(actions))
      if (key === 'category' ? typeof value !== 'string' || !value.trim() : typeof value !== 'boolean') throw new ServiceError('规则动作格式无效');
    if (actions.category && !categoryCatalog(this.repo).some(item => item.name === actions.category))
      throw new ServiceError('分类不存在，请从现有分类中选择');
    const value = { id: old?.id || randomUUID(), name, intent: String(input.intent || ''), query, actions,
      enabled: input.enabled === true, automatic: input.automatic === true,
      createdAt: old?.createdAt || new Date().toISOString(), revision: ruleRevision(query, actions) };
    if (old?.automaticPauseReason && hasAutomaticAIActions(actions)) value.automaticPauseReason = automaticAIPauseReason;
    return pausedAutomaticAIRule(value);
  }
  async agentDraft({ messages, accountId, lockAccount, requestId }, disconnectSignal) {
    if (!Array.isArray(messages) || messages.at(-1)?.role !== 'user' || messages.some(item =>
      !['user', 'assistant'].includes(item?.role) || typeof item.text !== 'string' || !item.text.trim()))
      throw new ServiceError('请描述希望匹配的邮件和处理动作');
    if (accountId && !this.repo.get('account', accountId)) throw new ServiceError('当前邮箱不存在');
    const accounts = this.repo.list('account').map(({ id, name, email }) => ({ id, name, email }));
    const categories = categoryCatalog(this.repo);
    const labels = categories.filter(item => item.id !== 'unclassified').map(({ id, name }) => ({ id, name }));
    const { config, apiKey } = this.credentials.ai();
    const id = typeof requestId === 'string' && /^[0-9a-f-]{36}$/i.test(requestId) ? requestId : randomUUID();
    const signal = disconnectSignal ? AbortSignal.any([this.draftController.signal, disconnectSignal]) : this.draftController.signal;
    const trace = { id, task: 'ruleDraft', status: 'running', stage: 'waiting', text: '', thought: false, tools: [] };
    const publish = () => this.onProgress?.({ ...trace, tools: [...trace.tools] });
    const onTool = ({ name, ...tool }) => {
      const entry = { ...tool, name: name ?? 'unknown' };
      const index = trace.tools.findIndex(item => item.id === entry.id);
      if (index === -1) trace.tools.push(entry);
      else trace.tools[index] = entry;
      if (entry.status === 'running' || entry.status === 'requested') trace.stage = 'checking';
      publish();
    };
    const countMatches = query => {
      const { where, params } = this.repo.messageWhere(query);
      return this.repo.db.prepare(`SELECT count(*) AS total FROM records m WHERE ${where}`).get(...params).total;
    };
    const tools = [
      { name: 'list_labels', description: '读取本机现有标签的名称。', parameters: { type: 'object', properties: {}, additionalProperties: false },
        run: () => ({ labels, detail: `找到 ${labels.length} 个标签` }) },
      { name: 'preview_rule', description: '按当前选定邮箱预查搜索条件的命中数量。返回数量，不读取邮件正文或主题。',
        parameters: { type: 'object', properties: { query: { type: 'string' }, folder: { type: 'string', enum: ruleFolders } },
          required: ['query', 'folder'], additionalProperties: false },
        run: ({ query, folder }) => {
          const scope = this.agentQuery({ query, folder, accountId }, accounts);
          const total = countMatches(scope);
          return { total, detail: `当前匹配 ${total} 封邮件` };
        } },
    ];
    publish();
    const work = (async () => {
      try {
        const availableAccounts = lockAccount === true && accountId ? accounts.filter(account => account.id === accountId) : accounts;
        const response = await this.complete(config, apiKey, 'ruleDraft', { messages, currentAccountId: accountId ?? null,
          ...(lockAccount === true ? { accountScopeIsFixed: true } : {}), accounts: availableAccounts, categories: categories.map(item => item.name), labels }, [], {
          repository: this.repo, taskId: id, signal, tools, onTool,
          onModelRequest: () => { trace.stage = 'waiting'; publish(); },
          onThinkingSummary: delta => {
            trace.thought = true;
            trace.thinkingSummary = (trace.thinkingSummary || '') + delta;
            publish();
          },
          onThinking: active => {
            if (active) {
              trace.thought = true;
              trace.stage = 'thinking';
            } else if (trace.stage === 'thinking') trace.stage = trace.text ? 'writing' : 'waiting';
            publish();
          },
          onProgress: value => {
            const text = typeof value.question === 'string' && value.question.trim() ? value.question : value.explanation;
            if (typeof text !== 'string' || !text.trim() || text === trace.text) return;
            trace.text = text;
            trace.stage = 'writing';
            publish();
          },
        });
        signal.throwIfAborted();
        const explanation = typeof response?.explanation === 'string' ? response.explanation.trim() : undefined;
        if (typeof response?.question === 'string' && response.question.trim()) {
          trace.status = 'completed';
          return { question: response.question.trim(), explanation, trace };
        }
        if (response?.classification) {
          const { classification } = response;
          const target = lockAccount === true ? accountId : classification.accountId || accountId;
          if (target && !accounts.some(account => account.id === target))
            throw new ServiceError('标签方式包含无效的邮箱', 422);
          const proposal = organizationLabelMode(this.repo, classification, { allowEmpty: true });
          trace.status = 'completed';
          return { classification: { ...proposal, accountId: target || null }, explanation, trace };
        }
        const draft = response?.draft;
        if (!draft || typeof draft.name !== 'string' || !draft.actions
          || Object.keys(draft.actions).some(key => !['category', 'starred', 'unread', 'archive'].includes(key))
          || draft.actions.archive === false) throw new ServiceError('模型没有返回可执行的规则，请补充条件或动作', 502);
        const targetAccount = lockAccount === true ? accountId : Object.hasOwn(draft.query ?? {}, 'accountId') ? draft.query.accountId : accountId;
        const query = this.agentQuery({ ...draft.query, accountId: targetAccount }, accounts);
        const rule = this.validatedRule({ ...draft, enabled: true, query,
          intent: messages.filter(item => item.role === 'user').map(item => item.text).join('\n') });
        onTool({ id: 'local-samples', name: 'local_samples', status: 'running' });
        const { where, params } = this.repo.messageWhere(rule.query);
        const total = countMatches(rule.query);
        const samples = this.repo.db.prepare(`SELECT m.id, coalesce(json_extract(m.data,'$.subject'),'') AS subject,
          coalesce(json_extract(m.data,'$.sender'),'') AS sender FROM records m WHERE ${where}
          ORDER BY json_extract(m.data,'$.date') DESC,m.id LIMIT 5`).all(...params);
        onTool({ id: 'local-samples', name: 'local_samples', status: 'completed', detail: `当前匹配 ${total} 封邮件` });
        trace.status = 'completed';
        return { rule, total, samples, explanation, trace };
      } catch (error) {
        trace.status = signal.aborted ? 'cancelled' : 'failed';
        throw error;
      } finally { publish(); }
    })();
    this.drafting.add(work);
    try { return await work; }
    finally { this.drafting.delete(work); }
  }

  agentQuery(input, accounts) {
    if (typeof input.query !== 'string' || !ruleFolders.includes(input.folder)
      || input.accountId != null && !accounts.some(account => account.id === input.accountId)
      || parseSearch(input.query).conditions.some(({ field }) => field === 'account' || field === 'folder'))
      throw new ServiceError('规则包含无效的账户、文件夹或搜索条件', 422);
    return mailQuery({ ...input, fixedScope: true });
  }

  confirmAgentDraft({ rule, approved }) {
    if (approved !== true || typeof rule?.id !== 'string' || !/^[0-9a-f-]{36}$/i.test(rule.id) || rule.query?.fixedScope !== true)
      throw new ServiceError('请先核对规则草案并确认', 403);
    if (!rule.actions || Object.keys(rule.actions).some(key => !['category', 'starred', 'unread', 'archive'].includes(key)))
      throw new ServiceError('规则包含无法创建的动作');
    const actions = Object.fromEntries(Object.entries(rule.actions).sort(([a], [b]) => a.localeCompare(b)));
    const next = this.validatedRule({ ...rule, actions });
    const saved = this.repo.get('mailRule', rule.id);
    if (saved) {
      if (saved.revision !== next.revision || saved.name !== next.name || saved.intent !== next.intent
        || saved.enabled !== next.enabled || saved.automatic !== next.automatic)
        throw new ServiceError('此规则已保存并修改，请从列表中打开', 409);
      return saved;
    }
    return this.repo.put('mailRule', { ...next, id: rule.id });
  }

  remove(id) { this.repo.remove('mailRule', id); return { ok: true }; }
  preview(id, ids) {
    const rule = this.repo.get('mailRule', id);
    if (!rule) throw new ServiceError('规则不存在', 404);
    const { where, params } = this.repo.messageWhere(rule.query);
    const matches = this.repo.db.prepare(`SELECT m.id, json_extract(m.data,'$.accountId') AS accountId,
      json_extract(m.data,'$.subject') AS subject, json_extract(m.data,'$.category') AS category,
      json_extract(m.data,'$.starred') AS starred, json_extract(m.data,'$.unread') AS unread,
      json_extract(m.data,'$.folder') AS folder
      FROM records m WHERE ${where} ORDER BY json_extract(m.data,'$.date') DESC,m.id`).all(...params);
    const selected = ids ? new Set(ids) : null;
    const run = { id: randomUUID(), ruleId: id, name: rule.name, revision: rule.revision,
      query: rule.query, actions: rule.actions, createdAt: new Date().toISOString(), status: 'preview',
      items: matches.filter(row => !selected || selected.has(row.id)).map(message => {
        const { id } = message;
        message.starred = !!message.starred; message.unread = !!message.unread;
        return { id, accountId: message.accountId, subject: message.subject, status: 'pending',
          reason: rule.intent || rule.query.query || '符合所选账户、文件夹及筛选条件',
          expected: Object.fromEntries(['category', 'starred', 'unread', 'folder'].map(key => [key, message[key]])),
          error: null, jobIds: [], suggestions: [] };
      }) };
    return this.repo.put('ruleRun', run);
  }
  start(id, approved) {
    if (approved !== true) throw new ServiceError('运行规则需要确认预览', 403);
    if (this.worker) throw new ServiceError('规则正在执行，请等待完成', 409);
    const run = this.repo.get('ruleRun', id);
    if (!run || !['preview', 'partial', 'failed', 'paused'].includes(run.status)) throw new ServiceError('此记录不能运行', 409);
    const rule = this.repo.get('mailRule', run.ruleId);
    if (!rule || rule.revision !== run.revision) throw new ServiceError('规则已修改，请重新预览', 409);
    this.controller = new AbortController(); this.activeRunId = run.id;
    run.status = 'running'; this.repo.put('ruleRun', run);
    this.worker = this.execute(run).catch(error => {
      run.status = 'failed'; run.error = error.message; this.repo.put('ruleRun', run);
    }).finally(() => { this.worker = null; });
    this.worker.catch(() => {});
    return run;
  }
  async execute(run) {
    const config = this.repo.get('settings', 'settings').ai;
    for (const item of run.items.filter(item => !['completed', 'existing'].includes(item.status))) {
      await yieldToRequests();
      if (this.controller.signal.aborted || !this.repo.get('mailRule', run.ruleId)?.enabled && run.automatic) {
        run.status = 'paused'; break;
      }
      const key = fingerprint([run.ruleId, run.revision, item.identity || item.id, config]);
      if (this.repo.get('ruleReceipt', key)?.status === 'completed') { item.status = 'existing'; continue; }
      item.status = 'running'; this.repo.put('ruleRun', run);
      try {
        if (this.locks.has(item.accountId)) throw new ServiceError('来源账户正在同步，请完成后重试');
        const message = this.repo.get('message', item.id);
        if (!message) throw new ServiceError('来源邮件已移除');
        const actions = run.actions;
        const changes = {};
        for (const field of ['category', 'starred', 'unread']) if (actions[field] !== undefined) changes[field] = actions[field];
        if (actions.archive) changes.folder = 'archive';
        if (Object.keys(changes).length) {
          const result = updateMessageBatch(this.repo, { updates: [{ id: item.id, changes, expected: item.expected }] }, this.locks);
          if (result.undo.length) item.undo = result.undo;
          item.expected = Object.fromEntries(['category', 'starred', 'unread', 'folder'].map(key => [key, this.repo.get('message', item.id)[key]]));
          this.repo.put('ruleRun', run);
        }
        const generate = async (task, extra = {}) => {
          const jobId = `rule-${fingerprint([key, task, extra.attachmentId || null])}`;
          const previous = this.repo.get('job', jobId);
          if (previous?.status === 'completed') {
            if (!item.jobIds.includes(jobId)) item.jobIds.push(jobId);
            return previous;
          }
          if (this.locks.has('agent')) throw new ServiceError('AI 正在执行其他任务，请完成后重试');
          let job;
          const connection = this.credentials.ai();
          if (fingerprint(connection.config) !== fingerprint(config)) throw new ServiceError('模型配置已切换，请重新预览后运行');
          this.locks.add('agent');
          try { job = await this.agent(this.repo, { ...connection, task, messageId: item.id, accountId: message.accountId,
            preview: true, signal: this.controller.signal, onProgress: this.onProgress, ...extra }, { jobId }); }
          finally {
            this.locks.delete('agent');
            if (!item.jobIds.includes(jobId) && this.repo.get('job', jobId)) item.jobIds.push(jobId);
          }
          this.repo.put('ruleRun', run);
          return job;
        };
        if ((actions.summary || actions.followUp) && !this.repo.get('message', item.id).summary) await generate('summary');
        if (actions.attachments) for (const attachmentId of message.attachmentIds) {
          const file = this.repo.get('attachment', attachmentId);
          if (file && !file.analysis) await generate('attachment', { attachmentId });
        }
        if (actions.followUp) item.suggestions = this.repo.get('message', item.id).summary?.todos || [];
        if (actions.reply) await generate('reply');
        item.status = 'completed'; item.error = null;
        this.repo.put('ruleReceipt', { id: key, status: 'completed', runId: run.id, messageId: item.id });
      } catch (error) { item.status = 'failed'; item.error = error.message; if (this.controller.signal.aborted) run.status = 'paused'; }
      this.repo.put('ruleRun', run);
    }
    if (run.status !== 'paused') run.status = run.items.some(item => item.status === 'failed') ? 'partial' : 'completed';
    return this.repo.put('ruleRun', run);
  }
  async pause(id) {
    if (this.activeRunId !== id || !this.worker) throw new ServiceError('此规则记录没有正在执行', 409);
    this.controller.abort(); await this.worker;
    return this.repo.get('ruleRun', id);
  }
  undo(id) {
    const run = this.repo.get('ruleRun', id);
    if (!run || run.status === 'running') throw new ServiceError('请等待此规则停止后撤销', 409);
    if (run.status === 'undone') return run;
    this.repo.transaction(() => {
      const reverted = new Set();
      for (const item of run.items.toReversed()) {
        if (!item.undo?.length) continue;
        updateMessageBatch(this.repo, { updates: item.undo }, this.locks);
        reverted.add(item.id);
        if (item.identity) reverted.add(item.identity);
      }
      if (reverted.size) {
        this.repo.db.prepare(`DELETE FROM records WHERE kind='ruleReceipt' AND json_extract(data,'$.runId')=?
          AND json_extract(data,'$.messageId') IN (SELECT value FROM json_each(?))`).run(id, JSON.stringify([...reverted]));
      }
      run.status = 'undone'; this.repo.put('ruleRun', run);
    });
    return run;
  }
  async newMail(ids) {
    for (const rule of this.list().filter(rule => rule.enabled && rule.automatic)) {
      if (this.worker) await this.worker;
      if (this.closing) break;
      const current = this.repo.get('mailRule', rule.id);
      if (!current?.enabled || !current.automatic) continue;
      const run = this.preview(rule.id, ids);
      if (!run.items.length) { this.repo.remove('ruleRun', run.id); continue; }
      run.automatic = true; this.repo.put('ruleRun', run);
      this.start(run.id, true);
      const { signal } = this.controller;
      await this.worker;
      if (signal.aborted) break;
    }
  }
  async close() {
    this.closing = true;
    this.controller.abort();
    this.draftController.abort();
    await Promise.allSettled([this.worker, ...this.drafting]);
  }
}
