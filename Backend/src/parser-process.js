import { fork } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { ServiceError } from './validation.js';

export function fatalCategory(text) {
  if (/heap out of memory|allocation failed|out of memory|std::bad_alloc|memory budget exceeded/i.test(text)) return 'memory_limit';
  if (/assertion failed|assertion.*failed|CHECK failed|fatal runtime error/i.test(text)) return 'native_assertion';
  if (/uncaught|unhandled.*(?:exception|rejection)/i.test(text)) return 'unhandled_exception';
  if (/FATAL ERROR|SIGABRT|abort\(\)/i.test(text)) return 'fatal_abort';
  return 'process_exit';
}

// Native addons and V8 fatal errors can abort every worker thread in a process.
// Parsers get their own process, temp directory, heap budget and process group.
// The HTTP/SQLite process never imports PDF/canvas or office parsers to do work.
export class ParserProcess {
  constructor({ signal, timeoutMs = 60000, diagnostics, account,
    executable = new URL('./parser-runner.js', import.meta.url), rssLimitBytes = 512 * 1024 * 1024 } = {}) {
    this.signal = signal; this.timeoutMs = timeoutMs; this.diagnostics = diagnostics;
    this.account = account; this.executable = executable;
    this.rssLimitBytes = Math.min(512 * 1024 * 1024, Math.max(64 * 1024 * 1024, rssLimitBytes));
    this.child = null; this.busy = false;
  }
  async start() {
    this.signal?.throwIfAborted();
    if (this.child?.connected && this.child.exitCode === null && this.child.signalCode === null) return this.child;
    await this.close();
    this.signal?.throwIfAborted();
    const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-parser-'));
    this.directory = directory;
    this.signal?.throwIfAborted();
    const env = Object.fromEntries(['PATH', 'HOME', 'LANG', 'LC_ALL', 'TZ', 'BOXMAIL_PRESENTATION_RENDERER']
      .filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]]));
    env.TMPDIR = directory;
    env.BOXMAIL_PARSER_CHILD = '1';
    env.BOXMAIL_PARSER_RSS_LIMIT = String(this.rssLimitBytes);
    const child = fork(this.executable, [], { cwd: directory, env, detached: process.platform !== 'win32',
      execArgv: ['--max-old-space-size=192'], serialization: 'advanced',
      stdio: ['ignore', 'ignore', 'pipe', 'ipc', 'pipe'] });
    this.child = child;
    this.stderr = '';
    // Drain continuously but retain only a short private window for classification.
    // Raw stderr, filenames and document content are never written to diagnostics.
    child.stderr.on('data', chunk => { this.stderr = (this.stderr + chunk.toString('utf8')).slice(-16384); });
    child.on('error', () => {});
    this.closed = new Promise(resolve => child.once('close', resolve));
    return child;
  }
  async run(task, buffer, options = {}) {
    this.signal?.throwIfAborted();
    if (!['mime', 'docx', 'xlsx', 'pdf', 'presentation-text'].includes(task))
      throw new ServiceError('不支持此解析任务');
    if (this.busy) throw new ServiceError('解析任务正在运行，请稍后重试', 409);
    this.busy = true;
    const started = performance.now();
    let child, timer, abort, receive, failed, exited;
    const formats = new Set(['mime', 'pdf', 'docx', 'xlsx', 'ppt', 'pptx', 'pps', 'ppsx', 'presentation']);
    const details = { account: this.account, parser: task, format: formats.has(options.format) ? options.format : 'unknown',
      bytes: buffer.length, phase: 'parse' };
    try {
      child = await this.start();
      this.signal?.throwIfAborted();
      if (task !== 'mime') this.diagnostics?.record('parser.started', details);
      const result = await new Promise((resolve, reject) => {
        receive = message => {
          if (message?.type !== 'result') return;
          if (message.error) {
            const error = new ServiceError(message.error.message || '邮件或附件解析失败，已完成内容保留，可稍后重试。',
              message.error.status || 502);
            error.code = 'PARSER_INVALID_DOCUMENT'; reject(error);
          } else resolve(message.result);
        };
        failed = () => {
          const error = new ServiceError('无法启动附件解析进程，已保存此前进度，请重试。', 502);
          error.code = 'PARSER_START_FAILED'; reject(error);
        };
        exited = (code, signal) => {
          const reason = fatalCategory(this.stderr);
          const error = new ServiceError(reason === 'memory_limit'
            ? '邮件或附件解析超过内存预算，已完成内容保留，其余邮件继续同步。'
            : '邮件或附件解析进程意外退出，已完成内容保留，其余邮件继续同步。', 502);
          error.code = reason === 'memory_limit' ? 'PARSER_MEMORY_LIMIT' : 'PARSER_CRASH';
          error.parserExit = { exitCode: code, signal: signal || 'none', reason };
          reject(error);
        };
        abort = () => reject(this.signal.reason);
        // close follows stderr EOF; classifying on exit can miss the last fatal line.
        child.on('message', receive); child.once('error', failed); child.once('close', exited);
        this.signal?.addEventListener('abort', abort, { once: true });
        timer = setTimeout(() => {
          const error = new ServiceError('邮件或附件解析超时，已完成内容保留，可稍后重试。', 502);
          error.code = 'MAIL_PARSE_TIMEOUT'; reject(error);
        }, this.timeoutMs);
        child.send({ type: 'parse', task, buffer, options }, error => { if (error) failed(); });
        if (this.signal?.aborted) abort();
      });
      if (task !== 'mime') this.diagnostics?.record('parser.completed', { ...details, durationMs: performance.now() - started });
      return result;
    } catch (error) {
      if (!this.signal?.aborted) this.diagnostics?.record('parser.failed', { ...details, code: error.code || 'PARSER_FAILED',
        ...error.parserExit, durationMs: performance.now() - started });
      await this.close();
      throw error;
    } finally {
      clearTimeout(timer); this.signal?.removeEventListener('abort', abort);
      if (child) {
        if (receive) child.removeListener('message', receive);
        if (failed) child.removeListener('error', failed);
        if (exited) child.removeListener('close', exited);
      }
      this.busy = false;
    }
  }
  async close() {
    const child = this.child, closed = this.closed, directory = this.directory;
    this.child = null; this.directory = null;
    if (child) {
      // Kill only the group created for this parser, including its owned renderers.
      // No app/backend process or directory lease belongs to this group.
      try {
        if (process.platform !== 'win32' && child.pid) process.kill(-child.pid, 'SIGKILL');
        else child.kill('SIGKILL');
      } catch { /* It may have exited before cleanup. */ }
      await closed;
      child.stderr.destroy();
    }
    if (directory) await rm(directory, { recursive: true, force: true }).catch(() => {});
  }
}
