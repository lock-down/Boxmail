import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { modelConnection } from './responses.js';

const languages = new Map([
  ['zh-Hans', '简体中文'], ['zh-Hant', '繁體中文'], ['en', '英语'], ['ja', '日语'], ['ko', '韩语'],
  ['fr', '法语'], ['de', '德语'], ['es', '西班牙语'], ['pt', '葡萄牙语'], ['it', '意大利语'], ['ru', '俄语'],
]);

export function translationLanguage(code) {
  if (!languages.has(code)) throw new ServiceError('请选择支持的译文语言');
  return languages.get(code);
}

export function cachedTranslation(message, code) {
  return message.translations?.[code] || (code === 'zh-Hans' && typeof message.translation === 'string'
    ? { text: message.translation, html: message.translationHTML ?? null } : null);
}

export class MailTranslation {
  constructor(repo, agent, onProgress) {
    Object.assign(this, { repo, agent, onProgress });
    this.work = new Map();
  }

  preference(accountId, change) {
    if (!this.repo.get('account', accountId)) throw new ServiceError('来源邮箱不存在', 404);
    const previous = this.repo.get('translationPreference', accountId) || { id: accountId, auto: false, language: 'zh-Hans' };
    if (!change) return previous;
    const next = { ...previous };
    if (change.language !== undefined) {
      translationLanguage(change.language);
      next.language = change.language;
    }
    if (change.auto !== undefined) {
      if (typeof change.auto !== 'boolean') throw new ServiceError('自动翻译设置无效');
      next.auto = change.auto;
    }
    return this.repo.put('translationPreference', next);
  }

  start(input, configuration) {
    const { messageId, targetLanguage, auto } = input;
    translationLanguage(targetLanguage);
    const message = this.repo.get('message', messageId);
    if (!message || message.accountId !== input.accountId) throw new ServiceError('来源邮件不存在', 404);
    if (auto === true) {
      const preference = this.preference(message.accountId);
      if (!preference.auto || preference.language !== targetLanguage) throw new ServiceError('此账户的翻译设置已变化', 409);
    }
    const key = JSON.stringify([messageId, targetLanguage]);
    const cached = cachedTranslation(message, targetLanguage);
    const job = { id: randomUUID(), task: 'translate', messageId, targetLanguage,
      accountId: message.accountId, status: 'running', createdAt: new Date().toISOString() };
    if (cached) return { ...job, status: 'completed', result: cached };
    const existing = this.work.get(key);
    if (existing) return this.repo.get('job', existing.id) ?? existing.job;
    const config = configuration();
    modelConnection(config, input.apiKey);
    const controller = new AbortController();
    this.repo.put('job', job);
    const worker = { id: job.id, job, controller };
    this.work.set(key, worker);
    worker.promise = Promise.resolve().then(() => this.agent(this.repo, {
      ...input, task: 'translate', config, signal: controller.signal, onProgress: this.onProgress,
    }, { jobId: job.id })).catch(error => {
      const current = this.repo.get('job', job.id) || job;
      this.repo.put('job', { ...current, status: 'failed', error: current.error || (error instanceof ServiceError
        ? error.message : '翻译未完成，请检查模型连接后重试。') });
    }).finally(() => { this.work.delete(key); });
    return job;
  }

  async close() {
    for (const worker of this.work.values()) worker.controller.abort();
    await Promise.allSettled([...this.work.values()].map(worker => worker.promise));
  }
}
