import { createHash } from 'node:crypto';
import { mkdir, appendFile, rename, rm, chmod, lstat } from 'node:fs/promises';
import path from 'node:path';

const fields = new Set(['account', 'phase', 'folder', 'status', 'method', 'route', 'code', 'errorType',
  'durationMs', 'upstreamStatus', 'downloaded', 'total', 'remaining', 'metadataCount', 'metadataRequests',
  'statusCount', 'uidCount', 'metadataMissingCount', 'sourceRequests', 'sourceRetryRequests', 'failedCount', 'count',
  'repaired', 'skipped', 'queued', 'active', 'rssMB', 'lagMs', 'cpuMs', 'protocol', 'task',
  'parser', 'format', 'bytes', 'exitCode', 'signal', 'reason', 'requestID', 'field', 'record', 'recordKind',
  'expectedType', 'actualType', 'action', 'responseBytes']);
const knownErrors = new Set(['Error', 'ServiceError', 'AbortError', 'TimeoutError', 'TypeError',
  'SyntaxError', 'APIError', 'APIConnectionError', 'APIConnectionTimeoutError', 'AuthenticationError']);
export const accountReference = id => createHash('sha256').update(String(id)).digest('hex').slice(0, 12);
export function errorDiagnostic(error) {
  const code = error?.originalCode || error?.code;
  return { errorType: knownErrors.has(error?.name) ? error.name : 'Error',
    ...(typeof code === 'string' && /^[A-Z][A-Z0-9_]{1,48}$/.test(code) ? { code } : {}),
    ...(Number.isInteger(error?.status) ? { status: error.status } : {}),
    ...(Number.isInteger(error?.upstreamStatus) ? { upstreamStatus: error.upstreamStatus } : {}) };
}
// Route IDs and all query parameters can contain addresses, subjects or API keys.
export function diagnosticRoute(raw) {
  const literals = new Set(['health', 'state', 'messages', 'sync', 'sync-status', 'cancel', 'accounts',
    'test', 'settings', 'ai', 'events', 'models', 'refresh', 'agent', 'jobs', 'attachments', 'metadata',
    'download', 'search', 'rebuild', 'configuration', 'export', 'import', 'inspect', 'backups', 'create',
    'restore', 'trash', 'empty', 'drafts', 'send', 'organizer', 'categories', 'todos', 'conversation']);
  return '/' + String(raw).split('?')[0].split('/').filter(Boolean).slice(0, 6)
    .map(part => literals.has(part) ? part : ':id').join('/');
}

export class Diagnostics {
  constructor(directory, { maxBytes = 1024 * 1024, copies = 2 } = {}) {
    this.directory = path.join(directory, 'logs');
    this.file = path.join(this.directory, 'backend.jsonl');
    this.maxBytes = maxBytes; this.copies = copies;
    this.pending = 0; this.chain = Promise.resolve(); this.dropped = 0;
    this.coalesced = new Map();
  }
  recordCoalesced(event, details) {
    const key = JSON.stringify([event, details.phase, details.route, details.field, details.record,
      details.expectedType, details.actualType]);
    let entry = this.coalesced.get(key);
    if (!entry) {
      if (this.coalesced.size >= 256) {
        const oldest = this.coalesced.keys().next().value;
        const removed = this.coalesced.get(oldest);
        if (removed.count) this.record(removed.event, { ...removed.details, count: removed.count });
        this.coalesced.delete(oldest);
      }
      entry = { event, details, count: 0, emittedAt: performance.now() };
      this.coalesced.set(key, entry);
      this.record(event, { ...details, count: 1 });
    } else {
      entry.details = details;
      entry.count++;
      if (performance.now() - entry.emittedAt >= 30000) this.flushCoalesced();
    }
  }
  flushCoalesced() {
    for (const entry of this.coalesced.values()) if (entry.count) {
      this.record(entry.event, { ...entry.details, count: entry.count });
      entry.count = 0; entry.emittedAt = performance.now();
    }
  }
  record(event, details = {}) {
    if (!/^[a-z][a-z0-9_.]{1,64}$/.test(event)) return;
    if (this.pending >= 256) { this.dropped++; return; }
    const entry = { time: new Date().toISOString(), source: 'backend', event };
    for (const [key, value] of Object.entries(details)) if (fields.has(key)) {
      if (typeof value === 'number' && Number.isFinite(value)) entry[key] = Math.round(value);
      else if (typeof value === 'boolean') entry[key] = value;
      else if (typeof value === 'string' && value.length <= 160) entry[key] = value;
    }
    const line = JSON.stringify(entry) + '\n';
    this.pending++;
    this.chain = this.chain.then(async () => {
      await mkdir(this.directory, { recursive: true, mode: 0o700 });
      // Refuse symlinks, including preexisting files, so logging cannot overwrite credentials.
      const directory = await lstat(this.directory);
      if (!directory.isDirectory() || directory.isSymbolicLink()) return;
      const info = await lstat(this.file).catch(error => { if (error.code !== 'ENOENT') throw error; });
      if (info && (!info.isFile() || info.isSymbolicLink())) return;
      if (info?.size + Buffer.byteLength(line) > this.maxBytes) {
        await rm(`${this.file}.${this.copies}`, { force: true });
        for (let index = this.copies - 1; index >= 1; index--)
          await rename(`${this.file}.${index}`, `${this.file}.${index + 1}`).catch(error => {
            if (error.code !== 'ENOENT') throw error;
          });
        await rename(this.file, `${this.file}.1`);
      }
      await appendFile(this.file, line, { mode: 0o600 });
      await chmod(this.file, 0o600);
    }).catch(() => {}).finally(() => { this.pending--; });
  }
  async flush() {
    this.flushCoalesced(); await this.chain;
    if (this.dropped && this.pending < 256) {
      const count = this.dropped; this.dropped = 0;
      this.record('diagnostics.dropped', { count });
      await this.chain;
    }
  }
}
