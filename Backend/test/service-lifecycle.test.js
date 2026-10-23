import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const moduleURL = new URL('../src/service-lifecycle.js', import.meta.url).href;
async function child(t, close, options = {}) {
  const proc = spawn(process.execPath, ['--input-type=module', '-e', `
    import { serviceLifecycle } from ${JSON.stringify(moduleURL)};
    setInterval(() => {}, 1000);
    serviceLifecycle(${close}, ${JSON.stringify(options)});
    console.log('ready');
  `], { stdio: ['ignore', 'pipe', 'pipe'] });
  t.after(() => { if (proc.exitCode === null) proc.kill('SIGKILL'); });
  await once(proc.stdout, 'data');
  return proc;
}

test('service exits once after graceful cancellation even with repeated signals', { timeout: 5000 }, async t => {
  const proc = await child(t, 'async () => { await new Promise(resolve => setTimeout(resolve, 50)); }');
  const exited = once(proc, 'exit');
  proc.kill('SIGTERM'); proc.kill('SIGINT');
  assert.deepEqual(await exited, [0, null]);
});

test('stalled service cleanup has a deadline rather than retaining a directory forever', { timeout: 5000 }, async t => {
  const proc = await child(t, '() => new Promise(() => {})', { shutdownMs: 80 });
  const exited = once(proc, 'exit');
  proc.kill('SIGTERM');
  assert.deepEqual(await exited, [1, null]);
});

test('a missing parent shuts down its service', { timeout: 5000 }, async t => {
  const proc = await child(t, 'async () => {}', { parentPID: 2147483647, parentCheckMs: 50 });
  assert.deepEqual(await once(proc, 'exit'), [0, null]);
});

test('loss of the app lifetime pipe shuts down even while the parent PID still exists', { timeout: 5000 }, async t => {
  const proc = await child(t, 'async () => {}', { lifetimePipe: true, parentCheckMs: 50 });
  const exited = once(proc, 'exit');
  proc.stdout.destroy();
  assert.deepEqual(await exited, [0, null]);
});
