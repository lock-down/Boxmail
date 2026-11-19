import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';
import { syncSession } from './sync-session.js';
import { accountReference, errorDiagnostic } from './diagnostics.js';

export class AccountSyncCoordinator {
  constructor(repo, { locks, tasks, queue, diagnostics, mailSync, stallTimeoutMs, credentials, afterSync }) {
    Object.assign(this, { repo, locks, tasks, queue, diagnostics, mailSync, stallTimeoutMs, credentials, afterSync });
  }
  start(body, requestID = randomUUID()) {
    const { repo, locks, diagnostics, mailSync, tasks: syncTasks, queue: syncQueue, stallTimeoutMs: syncStallTimeoutMs } = this;
    if (body.folder && !['inbox','sent','trash','drafts','archive','spam'].includes(body.folder))
      throw new ServiceError('请选择有效的邮件文件夹');
    const a = repo.get('account', body.accountId);
    if (!a || a.isDemo) throw new ServiceError('请先添加真实邮箱');
    if (locks.has(a.id)) throw new ServiceError('该账户正在同步', 409);
    locks.add(a.id);
    const previousIds = new Set(repo.messageGraphHeaders({ accountId: a.id }).map(item => item.id));
    const controller = new AbortController();
    const task = { status: 'queued', phase: 'queued', controller, requestID };
    syncTasks.set(a.id, task);
    diagnostics.record('sync.queued', { account: accountReference(a.id), requestID, queued: syncQueue.pending.length + 1,
      active: syncQueue.active });
    const run = async () => {
      task.status = 'running'; task.phase = 'connect'; task.startedAt = new Date().toISOString();
      task.lastProgress = performance.now();
      diagnostics.record('sync.started', { account: accountReference(a.id), requestID });
      const watchdog = setInterval(() => {
        if (performance.now() - task.lastProgress < syncStallTimeoutMs || controller.signal.aborted) return;
        const error = new ServiceError('同步长时间没有进展，已暂停本次任务并保留已下载邮件，请检查网络后重试。', 504);
        error.code = 'SYNC_STALLED';
        diagnostics.record('sync.stalled', { account: accountReference(a.id), phase: task.phase,
          durationMs: performance.now() - task.lastProgress, code: error.code });
        controller.abort(error);
      }, Math.min(1000, Math.max(10, syncStallTimeoutMs / 4)));
      watchdog.unref();
      try {
        const result = await syncSession(repo, a, body.password ?? this.credentials().mail(a.id), {
          syncBatch: mailSync, folder: body.folder || undefined, signal: controller.signal, requestID });
        task.status = result.partial ? 'paused' : 'completed'; return result;
      } finally { clearInterval(watchdog); }
    };
    task.promise = syncQueue.run(run, controller.signal).catch(error => {
      const stalled = controller.signal.reason?.code === 'SYNC_STALLED';
      task.status = controller.signal.aborted && !stalled ? 'paused' : 'failed';
      task.error = stalled ? controller.signal.reason.message
        : controller.signal.aborted ? '同步已停止，已下载邮件已保留'
          : error instanceof ServiceError ? error.message : '同步未完成，请检查网络与邮箱配置后重试';
      diagnostics.record('sync.failed', { account: accountReference(a.id), phase: task.phase, requestID,
        ...errorDiagnostic(error) });
      throw error;
    }).finally(() => {
      locks.delete(a.id);
      this.afterSync(a.id, repo.messageGraphHeaders({ accountId: a.id }).filter(item => !previousIds.has(item.id) && item.folder === 'inbox').map(item => item.id));
      diagnostics.record(`sync.${task.status}`, { account: accountReference(a.id), phase: task.phase, requestID });
    });
    return task;
  }
}
