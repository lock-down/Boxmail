import { spawn } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { parseMailContent } from '../../src/mail-content-worker.js';
import { Worker } from 'node:worker_threads';
new Worker(new URL('../../src/parser-owner-watch.js', import.meta.url), {
  workerData: { fd: 4, directory: process.env.TMPDIR, rssLimitBytes: Number(process.env.BOXMAIL_PARSER_RSS_LIMIT) },
}).unref();
process.on('disconnect', () => { try { process.kill(-process.pid, 'SIGKILL'); } catch { process.exit(0); } });
process.on('message', async ({ task, buffer, options }) => {
  const marker = buffer.toString();
  if (marker === 'SYNTHETIC_ABORT') {
    process.stderr.write('Assertion failed: synthetic native failure; private-document-content\n', () => process.abort());
    return;
  }
  if (marker === 'SYNTHETIC_HANG') {
    const helper = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' });
    writeFileSync(options.pidFile, String(helper.pid));
    return;
  }
  if (marker === 'SYNTHETIC_BUSY') {
    writeFileSync(options.readyFile, String(process.pid));
    while (true) { /* The lifetime guard must still work while this event loop is blocked. */ }
  }
  if (marker === 'SYNTHETIC_NATIVE_MEMORY') {
    globalThis.nativeBytes = Buffer.alloc(192 * 1024 * 1024, 1);
    while (true) { /* Simulate a native buffer outside the V8 heap limit. */ }
  }
  if (marker === 'SYNTHETIC_WARM_MEMORY') {
    globalThis.retainedBytes = Buffer.alloc(128 * 1024 * 1024, 1);
    process.send({ type: 'result', result: { text: 'healthy but memory remains resident' }, rss: process.memoryUsage.rss() });
    return;
  }
  if (marker === 'SYNTHETIC_ENV') {
    const privateKeys = ['BOXMAIL_TOKEN', 'BOXMAIL_ENV_FILE', 'OPENAI_API_KEY', 'NODE_OPTIONS', 'NODE_PATH'];
    process.send({ type: 'result', result: { text: privateKeys.some(key => process.env[key]) ? 'leaked' : 'clean' } });
    return;
  }
  const result = task === 'mime' ? await parseMailContent(task, buffer) : { text: 'healthy synthetic attachment' };
  process.send({ type: 'result', result });
});
