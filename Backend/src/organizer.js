import { textSlice } from './unicode.js';
import { randomUUID } from 'node:crypto';
import { aiConfig, ServiceError } from './validation.js';
import { completion } from './responses.js';
import { categoryCatalog } from './categories.js';
import { progressText } from './ai-progress.js';

export const REVIEWABLE = ['needsApproval', 'partial', 'paused'];

function publicError(error) {
  if (error instanceof ServiceError) return error.message;
  if (error.name === 'TimeoutError' || /TIMEOUT/.test(error.cause?.code || ''))
    return '本批分析超时，可重试未完成的邮件，或降低思考等级后重试。';
  return 'AI 连接中断，可重试未完成的邮件。';
}

export class Organizer {
  constructor(repo, { complete = completion, batchSize = 6, onProgress } = {}) {
    this.repo = repo;
    this.complete = complete;
    this.batchSize = batchSize;
    this.onProgress = onProgress;
    this.workers = new Map();
  }
  busy(accountId) {
    return [...this.workers.keys()].some(id => this.repo.get('job', id)?.accountId === accountId);
  }
  start(input, previousId) {
    const config = aiConfig(input.config);
    if (!config.enabled) throw new ServiceError('请先启用 AI 助手');
    if (!input.apiKey && !['localhost', '127.0.0.1', '[::1]'].includes(new URL(config.baseURL).hostname))
      throw new ServiceError('请在设置中填写 API Key');
    if (!this.repo.get('account', input.accountId)) throw new ServiceError('请选择邮箱账户');
    if (this.busy(input.accountId)) throw new ServiceError('该账户正在整理，请等待完成或暂停', 409);
    const previous = previousId ? this.repo.get('job', previousId) : null;
    if (previousId && (!previous || previous.task !== 'classify' || !['failed', 'partial', 'paused'].includes(previous.status)
      || previous.accountId !== input.accountId)) throw new ServiceError('该任务不能重试', 409);
    const scope = previous?.scope || (input.scope === 'inbox' ? 'inbox' : 'unclassified');
    const limit = Math.min(200, Math.max(1, Math.floor(Number(input.limit) || 50)));
    const messages = this.repo.list('message', { accountId: input.accountId }).filter(m => m.folder === 'inbox'
      && (scope === 'inbox' || m.category === '未分类')).sort((a,b) => b.date.localeCompare(a.date)).slice(0, limit);
    const messageIds = previous?.messageIds || messages.map(m => m.id);
    if (!messageIds.length) throw new ServiceError('所选范围内没有需要整理的邮件');
    const job = previous ? { ...previous, status: 'running', error: null } : {
      id: randomUUID(), task: 'classify', status: 'running', accountId: input.accountId,
      messageId: null, createdAt: new Date().toISOString(), error: null, scope, messageIds,
      completedIds: [], result: { items: [], previous: [] },
    };
    job.categories = previous?.categories || categoryCatalog(this.repo);
    job.progress = { total: messageIds.length, completed: job.completedIds.length, failed: 0,
      batchSize: this.batchSize, batch: 0 };
    this.repo.put('job', job);
    const controller = new AbortController();
    const worker = { controller, promise: null };
    this.workers.set(job.id, worker);
    worker.promise = Promise.resolve().then(() => this.run(job, config, input.apiKey, controller.signal))
      .catch(error => {
        job.status = controller.signal.aborted ? 'paused' : job.result.items.length ? 'partial' : 'failed';
        job.error = publicError(error);
        this.repo.put('job', job);
        return job;
      })
      .finally(() => {
        this.workers.delete(job.id);
        this.onProgress?.({ id: job.id, task: 'classify', status: job.status, accountId: job.accountId, text: '' });
      });
    return job;
  }
  async run(job, config, apiKey, signal) {
    const done = new Set(job.completedIds);
    const pending = job.messageIds.filter(id => !done.has(id));
    const errors = [];
    for (let offset = 0; offset < pending.length && !signal.aborted; offset += this.batchSize) {
      const batch = pending.slice(offset, offset + this.batchSize);
      const context = batch.map(id => this.repo.get('message', id))
        .filter(m => m && m.accountId === job.accountId && m.folder === 'inbox')
        .map(m => ({ id: m.id, subject: m.subject.slice(0, 240), sender: m.sender.slice(0, 100),
          body: m.body.replace(/https?:\/\/\S+/g, '').replace(/\s+/g, ' ').slice(0, 600) }));
      job.progress.batch++;
      this.repo.put('job', job);
      try {
        if (!context.length) throw new ServiceError('本批邮件已移动或删除');
        const live = { id: job.id, task: 'classify', accountId: job.accountId, status: 'running', text: '',
          stage: `正在分析第 ${job.progress.batch} 批…` };
        this.onProgress?.(live);
        const result = await this.complete(config, apiKey, 'classify', context, [], { signal, stream: true, categories: job.categories,
          diagnostics: this.repo.diagnostics,
          onProgress: partial => this.onProgress?.({ ...live, text: progressText('classify', partial) }) });
        if (signal.aborted) break;
        if (!Array.isArray(result.items)) throw new ServiceError('分类格式不正确', 502);
        const ids = new Set(context.map(m => m.id));
        const categories = new Set(job.categories.map(item => item.name));
        const valid = new Map(result.items.filter(item => item && ids.has(item.id) && categories.has(item.category))
          .map(item => [item.id, { id: item.id, category: item.category, reason: textSlice(String(item.reason || ''), 0, 300) }]));
        for (const [id, item] of valid) {
          job.result.items = job.result.items.filter(old => old.id !== id);
          job.result.items.push(item);
          done.add(id);
        }
        if (valid.size < batch.length) errors.push('部分邮件未返回有效分类，可重试补齐。');
      } catch (error) {
        if (signal.aborted) break;
        errors.push(publicError(error));
      }
      job.completedIds = [...done];
      job.progress.completed = done.size;
      job.progress.failed = offset + batch.length - (done.size - (job.messageIds.length - pending.length));
      this.repo.put('job', job);
      // Other requests can use the local API while a batch is running.
      if (errors.length && !job.result.items.length) break;
    }
    job.completedIds = [...done];
    job.progress.completed = done.size;
    job.progress.failed = signal.aborted ? 0 : job.messageIds.length - done.size;
    job.status = signal.aborted ? 'paused' : done.size === job.messageIds.length ? 'needsApproval'
      : done.size ? 'partial' : 'failed';
    job.error = signal.aborted ? '整理已暂停，已完成的建议已保留。'
      : errors.length ? [...new Set(errors)].join('\n') : null;
    this.repo.put('job', job);
    this.repo.event('organize', `已分析 ${done.size}/${job.messageIds.length} 封邮件，等待确认后应用分类`);
    return job;
  }
  async pause(id) {
    const worker = this.workers.get(id);
    if (!worker) throw new ServiceError('任务未在运行', 409);
    worker.controller.abort();
    await worker.promise;
    return this.repo.get('job', id);
  }
  async close() {
    for (const worker of this.workers.values()) worker.controller.abort();
    await Promise.allSettled([...this.workers.values()].map(worker => worker.promise));
  }
}
