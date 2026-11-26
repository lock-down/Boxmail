import { randomUUID } from 'node:crypto';
import { conversationMembers } from './threads.js';
import { ServiceError } from './validation.js';
import { scheduleTime } from './send-queue.js';
import { todoSourceKey } from './summary.js';

function matchesTodo(item, todo) {
  if (item.todoId) return item.todoId === todo.id;
  return item.sourceKey === todoSourceKey(todo)
    || typeof item.sourceKey === 'string' && item.sourceKey.startsWith('rule:') && item.sourceKey.endsWith(`:${todo.id}`);
}

export class FollowUps {
  constructor(repo) { this.repo = repo; }
  list() { return this.repo.list('followUp').sort((a, b) => (a.dueAt || a.createdAt).localeCompare(b.dueAt || b.createdAt)); }
  forMessage(message) {
    return this.repo.list('followUp', { accountId: message.accountId, messageId: message.id }).sort((a, b) =>
      Number(!!b.todoId) - Number(!!a.todoId) || b.updatedAt.localeCompare(a.updatedAt) || a.id.localeCompare(b.id));
  }
  linkLegacyTodos(message) {
    if (!message.summary?.todos?.length) return;
    for (const item of this.forMessage(message)) {
      if (item.todoId) continue;
      const todo = message.summary.todos.find(todo => matchesTodo(item, todo));
      if (todo) this.repo.put('followUp', { ...item, todoId: todo.id });
    }
  }
  saveSuggestion(input) {
    const message = this.repo.get('message', input.messageId);
    const todo = message?.summary?.todos.find(todo => todo.id === input.todoId);
    if (!todo || message.accountId !== input.accountId || message.summaryHidden || message.folder === 'trash')
      throw new ServiceError('待办已变更，请刷新清单后重试', 409);
    return this.save({ ...input, sourceKey: todoSourceKey(todo) }, null, { suggestion: true });
  }
  setTodoDone(message, todo, done) {
    if (!message?.summary) throw new ServiceError('邮件没有待办');
    if (!todo) return message;
    const item = this.forMessage(message).find(item => matchesTodo(item, todo));
    if (item) {
      this.save({ state: done ? 'completed' : 'mine' }, item.id);
    } else {
      this.save({ messageId: message.id, todoId: todo.id, sourceKey: todoSourceKey(todo),
        state: done ? 'completed' : 'mine' }, null, { suggestion: true });
    }
    return this.repo.get('message', message.id);
  }
  save(input, id, { suggestion = false } = {}) {
    return this.repo.transaction(() => this.saveItem(input, id, suggestion));
  }
  saveItem(input, id, suggestion) {
    const editing = id ? this.repo.get('followUp', id) : null;
    if (id && !editing) throw new ServiceError('跟进项不存在', 404);
    const cached = this.repo.get('message', editing?.messageId || input.messageId);
    const message = cached || (editing ? { id: editing.messageId, accountId: editing.accountId, subject: editing.subject } : null);
    if (!message) throw new ServiceError('来源邮件不存在', 404);
    const sourceKey = typeof input.sourceKey === 'string' && input.sourceKey && !input.sourceKey.startsWith('mail:')
      ? input.sourceKey : 'mail';
    const todo = message.summary?.todos.find(todo => editing ? matchesTodo(editing, todo) : todo.id === input.todoId);
    const old = editing || this.forMessage(message).find(item => item.sourceKey === sourceKey || todo && matchesTodo(item, todo));
    let collected = old?.collected ?? !suggestion;
    if (old && !editing && !suggestion) {
      if (!todo || (old.collected !== false && old.todoId && !old.dismissed)) return old;
      collected = true;
      input = { dismissed: false };
    }
    const state = input.state ?? old?.state ?? (todo?.done ? 'completed' : 'mine');
    if (!['mine', 'waiting', 'completed'].includes(state)) throw new ServiceError('跟进状态无效');
    const title = String(input.title ?? old?.title ?? todo?.title ?? message.subject).trim();
    if (!title) throw new ServiceError('请填写跟进标题');
    const dueAt = input.dueAt === undefined ? old?.dueAt || null : input.dueAt === null ? null : scheduleTime(input.dueAt);
    const snoozedUntil = input.snoozedUntil === undefined ? old?.snoozedUntil || null
      : input.snoozedUntil === null ? null : scheduleTime(input.snoozedUntil);
    const dismissed = input.dismissed ?? old?.dismissed ?? false;
    if (typeof dismissed !== 'boolean' || dismissed && !(todo || old?.todoId)) throw new ServiceError('待办状态无效');
    const changedReminder = dueAt !== old?.dueAt || state !== old?.state || snoozedUntil !== old?.snoozedUntil;
    const saved = this.repo.put('followUp', { ...old, id: old?.id || randomUUID(), accountId: message.accountId,
      messageId: message.id, conversationId: cached ? conversationMembers(this.repo, message.id).id : old.conversationId,
      sourceKey: old?.sourceKey || sourceKey, title, state, dueAt, snoozedUntil,
      ...(todo || old?.todoId ? { todoId: todo?.id ?? old.todoId, collected, dismissed } : {}),
      dueText: old?.dueText ?? todo?.due ?? '', subject: message.subject,
      createdAt: old?.createdAt || new Date().toISOString(), updatedAt: new Date().toISOString(),
      waitingSince: state === 'waiting' ? old?.state === 'waiting' ? old.waitingSince : new Date().toISOString() : null,
      reminderCancelled: input.cancelReminder === true || (changedReminder ? false : old?.reminderCancelled || false),
      notifiedAt: changedReminder ? null : old?.notifiedAt || null,
    });
    if (todo && todo.done !== (state === 'completed')) {
      const todos = cached.summary.todos.map(item => item.id === todo.id ? { ...item, done: state === 'completed' } : item);
      this.repo.put('message', { ...cached, summary: { ...cached.summary, todos } });
    }
    this.updateSnooze(saved);
    return saved;
  }
  updateSnooze(item) {
    if (item.state === 'completed' || !item.snoozedUntil || !this.active(item)) { this.repo.remove('snooze', item.id); return; }
    if (!this.repo.get('message', item.messageId)) return;
    this.repo.put('snooze', { id: item.id, until: item.snoozedUntil, messageIds: conversationMembers(this.repo, item.messageId).members.map(message => message.id) });
  }
  active(item) {
    if (item.dismissed) return false;
    if (item.collected !== false) return true;
    const message = this.repo.get('message', item.messageId);
    return !!message?.summary && !message.summaryHidden && message.folder !== 'trash';
  }
  remove(id) {
    return this.repo.transaction(() => {
      this.repo.remove('snooze', id);
      this.repo.remove('followUp', id);
      return { ok: true };
    });
  }
  reconcileReplies() {
    for (const item of this.list()) this.updateSnooze(item);
    for (const item of this.list().filter(item => item.state === 'waiting' && !item.reminderCancelled && this.active(item))) {
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
      && Date.parse(item.snoozedUntil || item.dueAt) <= now.getTime() && this.active(item));
  }
}
