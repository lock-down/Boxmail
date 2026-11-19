import { randomUUID } from 'node:crypto';
import { conversationMembers } from './threads.js';
import { ServiceError } from './validation.js';
import { scheduleTime } from './send-queue.js';

export class FollowUps {
  constructor(repo) { this.repo = repo; }
  list() { return this.repo.list('followUp').sort((a, b) => (a.dueAt || a.createdAt).localeCompare(b.dueAt || b.createdAt)); }
  save(input, id) {
    const old = id ? this.repo.get('followUp', id) : null;
    if (id && !old) throw new ServiceError('跟进项不存在', 404);
    const message = this.repo.get('message', old?.messageId || input.messageId)
      || (old ? { id: old.messageId, accountId: old.accountId, subject: old.subject } : null);
    if (!message) throw new ServiceError('来源邮件不存在', 404);
    const sourceKey = !input.sourceKey || String(input.sourceKey).startsWith('mail:') ? 'mail' : input.sourceKey;
    const existing = !old && this.list().find(item => item.messageId === message.id && item.sourceKey === sourceKey);
    if (existing) return existing;
    const todo = input.todoId && message.summary?.todos.find(todo => todo.id === input.todoId);
    const state = input.state ?? old?.state ?? (todo?.done ? 'completed' : 'mine');
    if (!['mine', 'waiting', 'completed'].includes(state)) throw new ServiceError('跟进状态无效');
    const title = String(input.title ?? old?.title ?? todo?.title ?? message.subject).trim();
    if (!title) throw new ServiceError('请填写跟进标题');
    const dueAt = input.dueAt === undefined ? old?.dueAt || null : input.dueAt === null ? null : scheduleTime(input.dueAt);
    const snoozedUntil = input.snoozedUntil === undefined ? old?.snoozedUntil || null
      : input.snoozedUntil === null ? null : scheduleTime(input.snoozedUntil);
    const changedReminder = dueAt !== old?.dueAt || state !== old?.state || snoozedUntil !== old?.snoozedUntil;
    const saved = this.repo.put('followUp', { ...old, id: old?.id || randomUUID(), accountId: message.accountId,
      messageId: message.id, conversationId: this.repo.get('message', message.id) ? conversationMembers(this.repo, message.id).id : old.conversationId,
      sourceKey: old?.sourceKey || sourceKey, title, state, dueAt, snoozedUntil,
      dueText: old?.dueText ?? todo?.due ?? '', subject: message.subject,
      createdAt: old?.createdAt || new Date().toISOString(), updatedAt: new Date().toISOString(),
      waitingSince: state === 'waiting' ? old?.state === 'waiting' ? old.waitingSince : new Date().toISOString() : null,
      reminderCancelled: input.cancelReminder === true || (changedReminder ? false : old?.reminderCancelled || false),
      notifiedAt: changedReminder ? null : old?.notifiedAt || null,
    });
    this.updateSnooze(saved);
    return saved;
  }
  updateSnooze(item) {
    if (item.state === 'completed' || !item.snoozedUntil) { this.repo.remove('snooze', item.id); return; }
    if (!this.repo.get('message', item.messageId)) return;
    this.repo.put('snooze', { id: item.id, until: item.snoozedUntil, messageIds: conversationMembers(this.repo, item.messageId).members.map(message => message.id) });
  }
  remove(id) { this.repo.remove('snooze', id); this.repo.remove('followUp', id); return { ok: true }; }
  reconcileReplies() {
    for (const item of this.list()) this.updateSnooze(item);
    for (const item of this.list().filter(item => item.state === 'waiting' && !item.reminderCancelled)) {
      if (!this.repo.get('message', item.messageId)) continue;
      const account = this.repo.get('account', item.accountId);
      const own = new Set([account?.email, account?.username, ...(account?.aliases || [])].filter(Boolean).map(value => value.toLowerCase()));
      const incoming = conversationMembers(this.repo, item.messageId).members
        .map(header => this.repo.get('message', header.id))
        .find(message => message.folder !== 'sent' && !own.has(message.senderEmail.toLowerCase())
          && Date.parse(message.date) > Date.parse(item.waitingSince));
      if (incoming) this.repo.put('followUp', { ...item, reminderCancelled: true,
        replyMessageId: incoming.id, updatedAt: new Date().toISOString() });
    }
  }
  due(now = new Date()) {
    return this.list().filter(item => item.state !== 'completed' && !item.reminderCancelled
      && Date.parse(item.snoozedUntil || item.dueAt) <= now.getTime());
  }
}
