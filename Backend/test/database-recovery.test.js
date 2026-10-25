import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';

for (const committed of [false, true]) {
  test(`WAL recovery after SIGKILL ${committed ? 'retains committed' : 'rolls back uncommitted'} records and search state`, { timeout: 10000 }, async t => {
    const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-wal-recovery-'));
    let repo = new Repository(directory);
    t.after(async () => { if (repo.db.isOpen) repo.close(); await rm(directory, { recursive: true, force: true }); });
    repo.put('message', { id: 'm', accountId: 'a', subject: 'Original', body: 'original search text', attachmentIds: [] });
    repo.searchIndex.flush(); repo.close();
    const child = spawn(process.execPath, ['--input-type=module', '-e', `
      import { Repository } from ${JSON.stringify(new URL('../src/database.js', import.meta.url).href)};
      const repo = new Repository(process.env.BOXMAIL_RECOVERY_DATA);
      repo.db.exec('BEGIN IMMEDIATE');
      repo.put('message', { id: 'm', accountId: 'a', subject: 'Changed', body: 'changed search text', attachmentIds: ['f'] });
      repo.put('attachment', { id: 'f', messageId: 'm', name: 'Crash fixture', text: 'attachment search text' });
      repo.searchIndex.flush();
      if (${committed}) repo.db.exec('COMMIT');
      process.stdout.write('ready');
      setInterval(() => {}, 1000);
    `], { env: { ...process.env, BOXMAIL_RECOVERY_DATA: directory }, stdio: ['ignore', 'pipe', 'pipe'] });
    t.after(() => { if (child.exitCode === null) child.kill('SIGKILL'); });
    await once(child.stdout, 'data', { signal: AbortSignal.timeout(5000) });
    const exited = once(child, 'exit'); child.kill('SIGKILL');
    assert.deepEqual(await exited, [null, 'SIGKILL']);
    repo = new Repository(directory);
    assert.equal(repo.db.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
    assert.equal(repo.get('message', 'm').subject, committed ? 'Changed' : 'Original');
    assert.equal(repo.get('attachment', 'f') !== null, committed);
    assert.deepEqual(repo.get('message', 'm').attachmentIds, committed ? ['f'] : []);
    assert.equal(repo.search('changed search text').length, committed ? 1 : 0);
    assert.equal(repo.search('original search text').length, committed ? 0 : 1);
    assert.equal(repo.searchIndex.status().pending, 0);
  });
}
