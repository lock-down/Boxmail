import { createHash, randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { mailQuery, ruleRevision } from './mail-query.js';
import { updateMessageBatch } from './mail-batch.js';
import { runAgent } from './agent.js';
import { categoryCatalog } from './categories.js';

const fingerprint = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
export class MailRules {
  constructor(repo, credentials, { locks = new Set(), agent = runAgent, onProgress } = {}) {
    this.repo = repo; this.credentials = credentials; this.locks = locks; this.agent = agent; this.onProgress = onProgress;
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
    const old = id && this.repo.get('mailRule', id);
    if (id && !old) throw new ServiceError('规则不存在', 404);
    const name = String(input.name || '').trim();
    if (!name) throw new ServiceError('请填写规则名称');
    const query = mailQuery(input.query);
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
    return this.repo.put('mailRule', value);
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
    this.repo.transaction(() => {
      for (const item of [...run.items].reverse()) if (item.undo?.length) updateMessageBatch(this.repo, { updates: item.undo }, this.locks);
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
  async close() { this.closing = true; this.controller.abort(); await this.worker; }
}
