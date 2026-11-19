import { createIMAPClient } from './imap-connection.js';
import { accountReference, errorDiagnostic } from './diagnostics.js';

// IDLE only signals that a mailbox changed. The existing coordinator performs
// all downloads, UID reconciliation and mutation replay under its account lock.
export class RealtimeMail {
  constructor(repo, credentials, { synchronize, blocked = () => false, clientFactory = createIMAPClient }) {
    Object.assign(this, { repo, credentials, synchronize, blocked, clientFactory });
    this.watchers = new Map(); this.closing = false;
  }
  status(id, status, error = null) {
    this.repo.put('realtimeSync', { id, accountId: id, status, error, updatedAt: new Date().toISOString() });
  }
  async tick() {
    if (this.closing) return;
    const preferences = this.repo.get('settings', 'settings').preferences;
    const accounts = preferences.realtimeSync ? this.repo.list('account').filter(account => !account.isDemo) : [];
    const desired = new Set(accounts.map(account => account.id));
    for (const [id, watcher] of this.watchers) if (!desired.has(id)) {
      watcher.stopped = true; watcher.client?.close(); this.watchers.delete(id); this.status(id, 'stopped');
    }
    for (const account of accounts) {
      const identity = JSON.stringify([account.imapHost, account.imapPort, account.imapTLS, account.username,
        this.repo.get('settings', 'settings').credentialReferences?.[`mail-${account.id}`]]);
      let watcher = this.watchers.get(account.id);
      if (watcher && watcher.identity !== identity) {
        watcher.stopped = true; watcher.client?.close(); this.watchers.delete(account.id); watcher = null;
      }
      if (!watcher) {
        watcher = { identity, stopped: false, client: null, pending: false, synchronizing: null,
          connecting: null, retryAt: 0, unsupported: false };
        this.watchers.set(account.id, watcher);
      }
      if (!watcher.client && !watcher.connecting && !watcher.unsupported && Date.now() >= watcher.retryAt) {
        watcher.connecting = this.connect(account, watcher).finally(() => { watcher.connecting = null; });
      }
      if (watcher.pending && !watcher.synchronizing && !this.blocked(account.id)) {
        watcher.pending = false;
        try {
          watcher.synchronizing = this.synchronize(account.id).catch(() => { watcher.pending = true; })
            .finally(() => { watcher.synchronizing = null; });
        } catch { watcher.pending = true; }
      }
    }
  }
  async connect(account, watcher) {
    try {
      this.status(account.id, 'connecting');
      const client = this.clientFactory(account, this.credentials.mail(account.id));
      watcher.client = client;
      const disconnected = error => {
        if (watcher.client !== client || watcher.stopped || this.closing) return;
        watcher.client = null; client.close();
        watcher.retryAt = Date.now() + this.repo.get('settings', 'settings').preferences.syncMinutes * 60000;
        this.status(account.id, 'disconnected', '实时连接已断开，继续按设定周期同步并重连');
        if (error) this.repo.diagnostics?.record('imap.idle.failed', { account: accountReference(account.id), ...errorDiagnostic(error) });
      };
      client.on('error', disconnected); client.on('close', () => disconnected());
      await client.connect();
      if (watcher.stopped || this.closing) { client.close(); return; }
      if (!client.capabilities.has('IDLE')) {
        watcher.unsupported = true; watcher.client = null; client.close(); this.status(account.id, 'unsupported', '服务器未提供 IDLE，继续周期同步'); return;
      }
      await client.mailboxOpen(account.folders?.inbox || 'INBOX');
      let previous = client.mailbox.exists;
      client.on('exists', event => {
        if (event.count > previous) watcher.pending = true;
        previous = event.count;
      });
      this.status(account.id, 'listening');
      // ImapFlow automatically enters/re-enters IDLE when no command is active.
    } catch (error) {
      watcher.client?.close(); watcher.client = null;
      watcher.retryAt = Date.now() + this.repo.get('settings', 'settings').preferences.syncMinutes * 60000;
      if (!watcher.stopped && !this.closing) this.status(account.id, 'disconnected', error.message);
    }
  }
  async close() {
    this.closing = true;
    for (const watcher of this.watchers.values()) { watcher.stopped = true; watcher.client?.close(); }
    await Promise.allSettled([...this.watchers.values()].flatMap(watcher => [watcher.connecting, watcher.synchronizing]).filter(Boolean));
    this.watchers.clear();
  }
}
