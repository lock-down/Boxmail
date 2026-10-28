import { workerData } from 'node:worker_threads';
import { Socket } from 'node:net';
import { rmSync, writeSync } from 'node:fs';

// This tiny guard stays responsive even while the parser's JS/native code is
// busy. Its private descriptor reaches EOF when the backend owner disappears.
const lifetime = new Socket({ fd: workerData.fd, readable: true, writable: false });
const stop = () => {
  try { rmSync(workerData.directory, { recursive: true, force: true }); } catch {}
  try { process.kill(-process.pid, 'SIGKILL'); } catch { process.exit(1); }
};
lifetime.on('end', stop);
lifetime.on('error', stop);
lifetime.resume();
// V8 heap flags do not cover native canvas/image buffers. Check process RSS
// from this independent guard so a blocked parser cannot exhaust the whole Mac.
setInterval(() => {
  if (process.memoryUsage.rss() <= workerData.rssLimitBytes) return;
  try { writeSync(2, 'FATAL ERROR: parser memory budget exceeded\n'); } catch {}
  stop();
}, 100).unref();
