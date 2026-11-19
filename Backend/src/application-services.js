import { SavedSearches } from './mail-query.js';
import { LocalCredentials } from './local-credentials.js';
import { FollowUps } from './follow-ups.js';
import { SendQueue } from './send-queue.js';
import { MailRules } from './mail-rules.js';
import { MailAssistant } from './mail-assistant.js';
import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';

const followUpNotificationId = item => `followUp-${item.id}-${item.snoozedUntil || item.dueAt}`;

// Composition root for long-lived local services. Domain objects remain in
// separate repositories/records and never share the lifecycle of an AI Job.
export class ApplicationServices {
  constructor(repo, { locks, onProgress, blocked = () => false, send, complete, agent, credentials } = {}) {
    this.repo = repo; this.blocked = blocked;
    this.credentials = credentials || new LocalCredentials(repo);
    this.savedSearches = new SavedSearches(repo);
    this.followUps = new FollowUps(repo);
    this.sendQueue = new SendQueue(repo, this.credentials, { send, blocked });
    this.rules = new MailRules(repo, this.credentials, { locks, onProgress, agent });
    this.assistant = new MailAssistant(repo, this.credentials, this.followUps, { complete, locks, onProgress });
    this.eventWorker = null; this.closing = false;
    for (const usage of repo.list('aiUsage').filter(item => item.status === 'running'))
      repo.put('aiUsage', { ...usage, status: 'interrupted' });
  }
  afterSync(accountId, messageIds) {
    this.followUps.reconcileReplies();
    const preferences = this.repo.get('settings', 'settings').preferences;
    if (preferences.newMailNotifications ?? preferences.notifications) for (const id of messageIds) {
      const message = this.repo.get('message', id);
      if (message) this.repo.put('localNotification', { id: `mail-${id}`, kind: 'mail', messageId: id, title: message.subject,
        createdAt: new Date().toISOString(), delivered: false });
    }
    if (messageIds.length) this.repo.put('newMailEvent', { id: randomUUID(), accountId, messageIds, status: 'pending' });
  }
  async tick() {
    if (this.closing || this.blocked()) return;
    const preferences = this.repo.get('settings', 'settings').preferences;
    if (preferences.followUpNotifications) for (const item of this.followUps.due()) {
      const id = followUpNotificationId(item);
      if (!this.repo.get('localNotification', id)) this.repo.put('localNotification', { id, kind: 'followUp',
        followUpId: item.id, messageId: item.messageId, title: item.title, createdAt: new Date().toISOString(), delivered: false });
    }
    await this.sendQueue.tick();
    if (this.closing || this.eventWorker) return;
    const event = this.repo.list('newMailEvent').find(event => event.status === 'pending');
    if (!event) return;
    this.eventWorker = this.rules.newMail(event.messageIds).then(() => {
      this.repo.put('newMailEvent', { ...event, status: 'completed' });
    }).catch(error => {
      this.repo.put('newMailEvent', { ...event, status: 'failed', error: error.message });
    }).finally(() => { this.eventWorker = null; });
  }
  get busy() { return !!(this.sendQueue.active || this.rules.worker || this.assistant.active.size || this.eventWorker); }
  async route(method, route, body, params) {
    const parts = route.split('/').filter(Boolean), [resource, id, action] = parts;
    if (resource === 'workspace-status' && method === 'GET') return { handled: true, result: {
      messageRevision: this.repo.messageRevision,
      snoozes: this.repo.list('snooze').filter(item => Date.parse(item.until) > Date.now()).map(item => `${item.id}:${item.until}`).sort(),
      sendPlans: this.sendQueue.list().map(item => `${item.id}:${item.status}`).sort(),
    } };
    if (resource === 'local-notifications') {
      if (method === 'GET') {
        const preferences = this.repo.get('settings', 'settings').preferences;
        const due = new Set(this.followUps.due().map(followUpNotificationId));
        return { handled: true, result: this.repo.list('localNotification').filter(item => !item.delivered
          && this.repo.get('message', item.messageId)
          && (item.kind === 'followUp' ? preferences.followUpNotifications && due.has(item.id)
            : preferences.newMailNotifications ?? preferences.notifications)) };
      }
      if (method === 'POST' && action === 'ack') {
        const item = this.repo.get('localNotification', id);
        if (item) this.repo.put('localNotification', { ...item, delivered: true });
        return { handled: true, result: { ok: true } };
      }
    }
    if (resource === 'saved-searches') {
      if (method === 'GET') return { handled: true, result: this.savedSearches.list() };
      if (method === 'POST') return { handled: true, result: this.savedSearches.save(body, id) };
      if (method === 'DELETE') return { handled: true, result: this.savedSearches.remove(id) };
    }
    if (resource === 'follow-ups') {
      if (method === 'GET') return { handled: true, result: this.followUps.list() };
      if (method === 'POST') return { handled: true, result: this.followUps.save(body, id) };
      if (method === 'DELETE') return { handled: true, result: this.followUps.remove(id) };
    }
    if (resource === 'send-plans') {
      if (method === 'GET') return { handled: true, result: this.sendQueue.list() };
      if (method === 'POST') return { handled: true, result: id ? this.sendQueue.change(id, body) : this.sendQueue.schedule(body) };
    }
    if (resource === 'mail-rules') {
      if (method === 'GET') return { handled: true, result: this.rules.list() };
      if (method === 'POST') return { handled: true, result: action === 'preview' ? this.rules.preview(id) : this.rules.save(body, id) };
      if (method === 'DELETE') return { handled: true, result: this.rules.remove(id) };
    }
    if (resource === 'rule-runs') {
      if (method === 'GET') return { handled: true, result: this.rules.listRuns() };
      if (method === 'POST' && action === 'run') return { handled: true, result: this.rules.start(id, body.approved) };
      if (method === 'POST' && action === 'pause') return { handled: true, result: await this.rules.pause(id) };
      if (method === 'POST' && action === 'undo') return { handled: true, result: this.rules.undo(id) };
    }
    if (resource === 'ai-usage' && method === 'GET') return { handled: true,
      result: this.repo.list('aiUsage').sort((a,b) => b.startedAt.localeCompare(a.startedAt)) };
    if (resource === 'assistant-sessions') {
      if (method === 'GET') return { handled: true, result: id ? this.assistant.get(id) : this.repo.list('assistantSession') };
      if (method === 'POST') {
        if (action === 'stop') return { handled: true, result: this.assistant.stop(id) };
        const result = action === 'ask' ? await this.assistant.ask(id, body.prompt)
          : action === 'apply' ? this.assistant.apply(id, body.turnId, body.actionId, body.approved)
          : this.assistant.create(body);
        return { handled: true, result };
      }
    }
    if (resource === 'assistant-search' && method === 'POST') return { handled: true, result: await this.assistant.plan(body) };
    if (resource === 'writing-styles') {
      if (method === 'GET') return { handled: true, result: this.repo.list('writingStyle') };
      if (method === 'POST') {
        if (!String(body.name || '').trim() || !String(body.instruction || '').trim()) throw new ServiceError('请填写风格名称和要求');
        return { handled: true, result: this.repo.put('writingStyle', { id: id || randomUUID(), name: body.name.trim(), instruction: body.instruction.trim() }) };
      }
      if (method === 'DELETE') { this.repo.remove('writingStyle', id); return { handled: true, result: { ok: true } }; }
    }
    return { handled: false };
  }
  async close() {
    this.closing = true;
    await Promise.allSettled([this.sendQueue.close(), this.rules.close(), this.assistant.close()]);
    await this.eventWorker;
  }
}
