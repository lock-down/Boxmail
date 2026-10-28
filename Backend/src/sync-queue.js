// A background start acknowledges immediately. CPU-heavy work and IMAP sessions
// are bounded across all accounts, including callers outside the desktop client.
export class SyncQueue {
  constructor(limit = 2) { this.limit = Math.max(1, limit); this.active = 0; this.pending = []; }
  run(operation, signal) {
    return new Promise((resolve, reject) => {
      const item = { operation, resolve, reject, signal };
      item.abort = () => {
        const index = this.pending.indexOf(item);
        if (index < 0) return;
        this.pending.splice(index, 1);
        signal.removeEventListener('abort', item.abort);
        reject(signal.reason);
      };
      this.pending.push(item);
      signal?.addEventListener('abort', item.abort, { once: true });
      if (signal?.aborted) item.abort();
      this.drain();
    });
  }
  drain() {
    while (this.active < this.limit && this.pending.length) {
      const item = this.pending.shift();
      item.signal?.removeEventListener('abort', item.abort);
      this.active++;
      Promise.resolve().then(() => { item.signal?.throwIfAborted(); return item.operation(); })
        .then(item.resolve, item.reject).finally(() => { this.active--; this.drain(); });
    }
  }
}
