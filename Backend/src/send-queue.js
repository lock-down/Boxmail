import { randomUUID } from 'node:crypto';
import { sendDraft } from './mail.js';
import { draftRevision } from './draft-state.js';
import { ServiceError } from './validation.js';

export function scheduleTime(value) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) throw new ServiceError('请选择有效日期时间');
  return new Date(value).toISOString();
}

export class SendQueue {
  constructor(repo, credentials, { send = sendDraft, blocked = () => false } = {}) {
    this.repo = repo; this.credentials = credentials; this.send = send; this.blocked = blocked;
    this.active = null;
    for (const plan of this.list().filter(plan => plan.status === 'submitting'))
      repo.put('sendPlan', { ...plan, status: 'uncertain', error: '应用退出中断了提交，请先核对已发送邮箱' });
  }
  list() { return this.repo.list('sendPlan').sort((a, b) => b.createdAt.localeCompare(a.createdAt)); }
  schedule(input) {
    if (input.approved !== true) throw new ServiceError('加入发送队列需要明确确认', 403);
    const draft = this.repo.get('draft', input.draftId);
    if (!draft || draft.status !== 'draft') throw new ServiceError('草稿不可发送，请重新打开后检查', 409);
    if (!draft.to?.trim()) throw new ServiceError('请填写收件人');
    const account = this.repo.get('account', draft.accountId);
    if (!account || account.isDemo) throw new ServiceError('请先添加真实邮箱');
    const plan = { id: randomUUID(), draftId: draft.id, accountId: draft.accountId,
      subject: draft.subject, to: draft.to, scheduledAt: scheduleTime(input.scheduledAt),
      timeZone: String(input.timeZone || ''), revision: draftRevision(draft), status: 'waiting',
      createdAt: new Date().toISOString(), error: null };
    this.repo.transaction(() => { this.repo.put('draft', { ...draft, status: 'queued' }); this.repo.put('sendPlan', plan); });
    return plan;
  }
  change(id, input) {
    const plan = this.repo.get('sendPlan', id);
    if (!plan || !['waiting', 'failed', 'paused'].includes(plan.status))
      throw new ServiceError('此投递已开始提交或已结束，不能取消或改期', 409);
    const draft = this.repo.get('draft', plan.draftId);
    if (!draft || !['draft', 'queued'].includes(draft.status)) throw new ServiceError('原草稿状态已变化，请核对发送结果', 409);
    const activePlan = this.repo.list('sendPlan').some(other =>
      other.id !== id && other.draftId === draft.id && ['waiting', 'submitting', 'paused'].includes(other.status));
    if (activePlan) throw new ServiceError('该草稿已有其他发送计划，请从当前计划管理投递', 409);
    const cancelled = input.cancel === true;
    const paused = input.pause === true && !cancelled;
    if (!cancelled && !paused) {
      if (draftRevision(draft) !== plan.revision)
        throw new ServiceError('草稿内容已变化，请取消后检查草稿，再重新安排发送', 409);
      if (!draft.to?.trim()) throw new ServiceError('请填写收件人');
      const account = this.repo.get('account', draft.accountId);
      if (!account || account.isDemo) throw new ServiceError('请先添加真实邮箱');
    }
    const updated = { ...plan, status: cancelled ? 'cancelled' : paused ? 'paused' : 'waiting',
      error: paused ? plan.error : null,
      ...(cancelled || paused ? {} : { scheduledAt: scheduleTime(input.scheduledAt), timeZone: String(input.timeZone || plan.timeZone) }) };
    this.repo.transaction(() => {
      this.repo.put('sendPlan', updated);
      this.repo.put('draft', { ...draft, status: cancelled ? 'draft' : 'queued' });
    });
    return updated;
  }
  async tick(now = new Date()) {
    if (this.active || this.blocked()) return;
    const plan = this.list().filter(plan => plan.status === 'waiting' && Date.parse(plan.scheduledAt) <= now.getTime())
      .sort((a, b) => a.scheduledAt.localeCompare(b.scheduledAt))[0];
    if (!plan) return;
    const run = async () => {
      let submitted = false;
      try {
        const draft = this.repo.get('draft', plan.draftId);
        if (!draft || draft.status !== 'queued' || draftRevision(draft) !== plan.revision)
          throw new ServiceError('草稿内容已变化，已停止此投递，请取消后重新检查');
        const password = this.credentials.mail(plan.accountId);
        this.repo.put('sendPlan', { ...plan, status: 'submitting', error: null });
        submitted = true;
        const result = await this.send(this.repo, plan.draftId, password, true, { fromQueue: true });
        this.repo.put('sendPlan', { ...plan, status: 'sent', completedAt: new Date().toISOString(),
          warning: result.warning || null, rejected: result.rejected || [], error: null });
      } catch (error) {
        const draft = this.repo.get('draft', plan.draftId);
        this.repo.put('sendPlan', { ...plan, status: draft?.status === 'uncertain' ? 'uncertain' : 'failed',
          // Submission may materialize borrowed attachments under new local IDs.
          revision: submitted && draft ? draftRevision(draft) : plan.revision, error: error.message });
      }
    };
    this.active = run();
    try { await this.active; } finally { this.active = null; }
  }
  async close() { await this.active; }
}
