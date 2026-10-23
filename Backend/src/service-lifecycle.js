// Installed before opening SQLite, so the parent can disappear during startup too.
export function serviceLifecycle(close, { parentPID = process.ppid, shutdownMs = 3000, parentCheckMs = 1000,
  lifetimePipe = process.env.BOXMAIL_LIFETIME_PIPE === '1' } = {}) {
  let stopping;
  const stop = () => {
    if (stopping) return stopping;
    clearInterval(watchdog);
    // A stalled socket or SDK cleanup must not leave an orphan holding the lease.
    const deadline = setTimeout(() => process.exit(1), shutdownMs);
    stopping = Promise.resolve().then(close).then(() => {
      clearTimeout(deadline); process.exit(0);
    }, () => { clearTimeout(deadline); process.exit(1); });
    return stopping;
  };
  const watchdog = setInterval(() => {
    try {
      process.kill(parentPID, 0);
      // ppid is a startup snapshot in Node. The app owns the pipe's reader;
      // EPIPE detects its death even if another process has reused that PID.
      if (lifetimePipe) process.stdout.write('\n');
    } catch { stop(); }
  }, parentCheckMs).unref();
  if (lifetimePipe) process.stdout.on('error', stop);
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  return { stop };
}
