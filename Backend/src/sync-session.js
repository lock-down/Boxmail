import { setImmediate as yieldToRequests } from 'node:timers/promises';
import { ServiceError } from './validation.js';
import { MailContentWorker } from './mail-content-worker.js';
import { accountReference } from './diagnostics.js';

// One user request owns the session; each underlying pass retains its download
// budget and checkpoint. Rotate unfinished folders instead of asking for another click.
export async function syncSession(repo, account, password, { syncBatch, folder, signal }) {
  const pending = [folder], failures = new Set();
  const deferredSources = new Set();
  const sourceFailureStreaks = new Map();
  const inventories = new Map();
  const contentWorker = new MailContentWorker({ signal, diagnostics: repo.diagnostics, account: accountReference(account.id) });
  let recoveryAttempted = false;
  const result = { count: 0, repaired: 0, skipped: 0, ok: true, partial: false };
  const progressFor = scope => repo.list('sync', { accountId: account.id })
    .filter(progress => !scope || progress.folder === scope);
  try {
    while (pending.length) {
      signal?.throwIfAborted();
      const scope = pending.shift();
      const before = new Map(progressFor(scope).map(progress => [progress.id, progress]));
      const deferredBefore = deferredSources.size;
      let batch;
      try {
        batch = await syncBatch(repo, repo.get('account', account.id) || account, password,
          { folder: scope, signal, deferredSources, sourceFailureStreaks, inventories, contentWorker });
        for (const key of ['count', 'repaired', 'skipped']) result[key] += batch?.[key] || 0;
      } catch (error) {
        if (signal?.aborted) throw error;
        failures.add(error instanceof ServiceError ? error.message : '同步未完成，请检查网络与邮箱配置后重试');
      }
      signal?.throwIfAborted();
      for (const progress of progressFor(scope)) {
        if (progress.status !== 'partial' || !progress.hasMore) continue;
        const previous = before.get(progress.id);
        const advanced = batch?.count > 0 || batch?.repaired > 0
          || deferredSources.size > deferredBefore
          || progress.downloaded > (previous?.downloaded ?? 0)
          || (previous?.remaining != null && progress.remaining < previous.remaining);
        if (!advanced) {
          result.partial = true;
          repo.put('sync', { ...progress, status: 'paused',
            lastError: '服务器暂未返回部分邮件，自动同步已暂停，已下载邮件已保留，可稍后重试。',
            updatedAt: new Date().toISOString() });
          continue;
        }
        if (!pending.includes(progress.folder)) pending.push(progress.folder);
      }
      // Once healthy history is complete, give isolated missing bodies one final
      // recovery pass. Never retry an unreachable mailbox in an unbounded loop.
      if (!pending.length && !recoveryAttempted && deferredSources.size && result.count + result.repaired > 0) {
        recoveryAttempted = true;
        const retry = progressFor(folder).filter(progress => progress.status === 'paused'
          && progress.hasMore && progress.source?.deferredOnly);
        if (retry.length) {
          deferredSources.clear();
          sourceFailureStreaks.clear();
          pending.push(...retry.map(progress => progress.folder));
        }
      }
      if (pending.length) await yieldToRequests(undefined, { signal });
    }
  } finally {
    await contentWorker.close();
    if (signal?.aborted) for (const progress of progressFor(folder)) {
      if (!['running', 'partial'].includes(progress.status)) continue;
      repo.put('sync', { ...progress, status: signal.reason?.code === 'SYNC_STALLED' ? 'failed' : 'paused',
        lastError: signal.reason?.code === 'SYNC_STALLED' ? signal.reason.message
          : '同步已停止，已下载邮件已保留，下次同步会自动继续。', updatedAt: new Date().toISOString() });
    }
  }
  if (failures.size) throw new ServiceError([...failures].join('\n'), 502);
  result.partial = progressFor(folder).some(progress => progress.hasMore && progress.status === 'paused');
  return result;
}
