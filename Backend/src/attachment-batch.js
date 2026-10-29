import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { aiConfig, ServiceError } from './validation.js';
import { runAgent } from './agent.js';
import { isPresentation } from './presentations.js';
import { unicodeJSON, textSlice } from './unicode.js';

const finished = new Set(['completed', 'existing', 'unsupported']);
export const MAX_BATCH_ATTACHMENTS = 100;
const imageTypes = new Set(['image/jpeg', 'image/png', 'image/gif', 'image/webp']);
function supported(file) {
  return !!file.text?.trim() || isPresentation(file) || file.contentType === 'application/pdf' || imageTypes.has(file.contentType)
    || ['.pdf', '.jpg', '.jpeg', '.png', '.gif', '.webp'].includes(path.extname(file.name).toLowerCase());
}
function publicError(error) {
  if (error instanceof ServiceError) return error.message;
  if (error.name === 'TimeoutError') return '理解超时，可重试这个附件。';
  return '附件理解未完成，请检查文件或 AI 连接后重试。';
}

// One durable task per email; each file keeps its own successful result and retry state.
export class AttachmentBatch {
  constructor(repo, { run = runAgent, onProgress } = {}) {
    this.repo = repo;
    this.runAgent = run;
    this.onProgress = onProgress;
    this.workers = new Map();
    this.savedItems = new Map();
  }
  busy(accountId) {
    return [...this.workers.keys()].some(id => this.repo.get('job', id)?.accountId === accountId);
  }
  active(messageId) {
    return [...this.workers.keys()].map(id => this.repo.get('job', id)).find(job => job?.messageId === messageId);
  }
  start(input, previousId) {
    const previous = previousId ? this.repo.get('job', previousId) : null;
    if (previousId && (!previous || previous.task !== 'attachmentBatch'
      || !['partial', 'failed', 'paused'].includes(previous.status)))
      throw new ServiceError('该附件任务不能重试', 409);
    const message = this.repo.get('message', previous?.messageId || input.messageId);
    if (!message) throw new ServiceError('邮件不存在，请重新打开邮件', 404);
    if (input.accountId && input.accountId !== message.accountId)
      throw new ServiceError('邮件不属于当前账户');
    if (!this.repo.get('account', message.accountId)) throw new ServiceError('邮箱账户不存在', 404);
    const active = this.active(message.id);
    if (active) return active;
    const config = aiConfig(input.config);
    if (!config.enabled) throw new ServiceError('请先启用 AI 助手');
    if (!input.apiKey && !['localhost', '127.0.0.1', '[::1]'].includes(new URL(config.baseURL).hostname))
      throw new ServiceError('请在设置中填写 API Key');
    const selected = previous ? previous.attachmentItems?.map(item => item.id) ?? []
      : input.attachmentIds ?? message.attachmentIds ?? [];
    if (!Array.isArray(selected) || selected.length > MAX_BATCH_ATTACHMENTS
      || previous?.attachmentItems?.length > MAX_BATCH_ATTACHMENTS)
      throw new ServiceError('每次最多理解 100 个附件，请选择不超过 100 个附件分批处理。');
    const ids = [...new Set(selected)];
    if (ids.some(id => !(message.attachmentIds || []).includes(id))) throw new ServiceError('附件不属于本封邮件');
    if (!ids.length) throw new ServiceError('本封邮件没有附件');
    const attachmentItems = previous ? previous.attachmentItems.map(item => finished.has(item.status)
      ? { ...item } : { ...item, status: 'pending', error: null }) : ids.map(id => {
      const file = this.repo.get('attachment', id);
      const item = { id, name: textSlice(file?.name || '附件不可用', 0, 256), status: 'pending', error: null };
      if (!file || file.messageId !== message.id) return { ...item, status: 'failed', error: '附件不属于本封邮件或已移除。' };
      if (file.analysis?.trim() && input.force !== true) return { ...item, status: 'existing' };
      if (!supported(file)) return { ...item, status: 'unsupported', error: file.parseError || '此格式暂不支持 AI 理解，可预览或下载原文件。' };
      return item;
    });
    const job = {
      ...(previous || { id: randomUUID(), task: 'attachmentBatch', createdAt: new Date().toISOString() }),
      accountId: message.accountId, messageId: message.id, status: 'running', error: null, attachmentItems,
    };
    this.save(job);
    const controller = new AbortController();
    const worker = { controller, promise: null };
    this.workers.set(job.id, worker);
    worker.promise = Promise.resolve().then(() => this.run(job, config, input.apiKey, controller.signal))
      .catch(error => {
        job.status = controller.signal.aborted ? 'paused' : 'failed';
        for (const item of job.attachmentItems.filter(item => item.status === 'running')) item.status = 'pending';
        job.error = controller.signal.aborted ? '批量理解已暂停，已完成的结果已保留。' : publicError(error);
        this.save(job);
      })
      .finally(() => { this.workers.delete(job.id); this.savedItems.delete(job.id); });
    return job;
  }
  save(job) {
    // Reconciliation may move the mail or copy shared attachments while the model works.
    const current = this.repo.get('job', job.id);
    job.messageId = current?.messageId || job.messageId;
    // A durable batch keeps its item order. Mutate in place so the active loop follows new ids.
    for (const [index, item] of job.attachmentItems.entries()) {
      item.name = textSlice(item.name || '附件', 0, 256);
      if (item.error) item.error = textSlice(item.error, 0, 1000);
      const id = current?.attachmentItems?.[index]?.id;
      if (!id || item.id === id) continue;
      item.id = id;
      // A formerly foreign file is now valid and can join the remainder of this batch.
      if (item.status === 'failed') { item.status = 'pending'; item.error = null; }
    }
    job.progress = {
      total: job.attachmentItems.length,
      completed: job.attachmentItems.filter(item => ['completed', 'existing'].includes(item.status)).length,
      failed: job.attachmentItems.filter(item => item.status === 'failed').length,
      batchSize: 1, batch: job.attachmentItems.filter(item => item.status === 'completed').length,
    };
    const items = job.attachmentItems.map(item => unicodeJSON(item));
    const saved = this.savedItems.get(job.id);
    if (!current || !saved) this.repo.put('job', job);
    else {
      // Persist only changed item values and small counters. The 100-item hard
      // limit also bounds SQLite's JSON row update and legacy reconciliation.
      const changes = [['$.status', job.status], ['$.error', job.error],
        ['$.messageId', job.messageId], ['$.progress', job.progress]];
      const params = [];
      const paths = [];
      for (const [key, value] of changes) { paths.push('?,json(?)'); params.push(key, unicodeJSON(value)); }
      for (const [index, value] of items.entries()) if (value !== saved[index]) {
        paths.push('?,json(?)'); params.push(`$.attachmentItems[${index}]`, value);
      }
      this.repo.db.prepare(`UPDATE records SET data=json_set(data,${paths.join(',')}) WHERE kind='job' AND id=?`)
        .run(...params, job.id);
      this.repo.searchIndex.schedule();
    }
    this.savedItems.set(job.id, items);
  }
  async run(job, config, apiKey, signal) {
    for (const item of job.attachmentItems) {
      if (signal.aborted) break;
      if (finished.has(item.status) || item.status === 'failed') continue;
      item.status = 'running';
      this.save(job);
      try {
        const message = this.repo.get('message', job.messageId);
        const file = this.repo.get('attachment', item.id);
        if (!message || message.accountId !== job.accountId || !message.attachmentIds.includes(item.id)
          || file?.messageId !== message.id) throw new ServiceError('附件已移动或移除，请重新打开邮件后重试。', 409);
        await this.runAgent(this.repo, {
          task: 'attachment', accountId: job.accountId, messageId: message.id, attachmentId: item.id,
          parentJobId: job.id, config, apiKey, signal, onProgress: this.onProgress,
        });
        signal.throwIfAborted();
        if (!this.repo.get('attachment', item.id)?.analysis?.trim())
          throw new ServiceError('AI 没有返回有效的附件理解结果，可重试。', 502);
        item.status = 'completed';
        item.error = null;
      } catch (error) {
        item.status = signal.aborted ? 'pending' : 'failed';
        item.error = signal.aborted ? null : publicError(error);
      }
      this.save(job);
    }
    const failed = job.attachmentItems.filter(item => item.status === 'failed').length;
    const completed = job.attachmentItems.filter(item => ['completed', 'existing'].includes(item.status)).length;
    job.status = signal.aborted ? 'paused' : failed ? completed ? 'partial' : 'failed' : 'completed';
    job.error = signal.aborted ? '批量理解已暂停，已完成的结果已保留。'
      : failed ? `${failed} 个附件理解失败，其余结果已保存，可只重试失败附件。` : null;
    this.save(job);
    this.repo.event('attachmentBatch', `本封邮件附件理解：${completed}/${job.attachmentItems.length} 个已完成`);
    return job;
  }
  async pause(id) {
    const worker = this.workers.get(id);
    if (!worker) throw new ServiceError('附件任务未在运行', 409);
    worker.controller.abort();
    await worker.promise;
    return this.repo.get('job', id);
  }
  async close() {
    for (const worker of this.workers.values()) worker.controller.abort();
    await Promise.allSettled([...this.workers.values()].map(worker => worker.promise));
  }
}
