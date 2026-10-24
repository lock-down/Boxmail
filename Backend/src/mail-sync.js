import { ServiceError } from './validation.js';

// Socket inactivity alone cannot bound a command that keeps receiving partial data.
export async function imapOperation(client, operation, { signal, timeoutMs = 45000 } = {}) {
  signal?.throwIfAborted();
  let timer, onAbort;
  const deadline = new Promise((resolve, reject) => {
    const stop = error => {
      reject(error);
      try { client.close?.(); } catch { /* A failed cleanup must not hide the deadline. */ }
    };
    timer = setTimeout(() => stop(new ServiceError('IMAP 操作超时，已保存已完成的邮件，可继续同步。', 502)), timeoutMs);
    onAbort = () => stop(signal.reason);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
  try { return await Promise.race([Promise.resolve().then(operation), deadline]); }
  finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', onAbort);
  }
}

// An empty iterator is not proof of an empty mailbox. Validate an independent UID
// inventory and every metadata page before allowing cache reconciliation.
export async function mailboxMetadata(client, remotePath, options = {}) {
  const validity = client.mailbox?.uidValidity;
  const selectedCount = client.mailbox?.exists ?? null;
  if (validity == null || !/^\d+$/.test(String(validity))
    || (client.mailbox.path && client.mailbox.path !== remotePath))
    throw new ServiceError('服务器未确认邮件文件夹，本机缓存已保留，请重试同步。', 502);
  const status = await imapOperation(client,
    () => client.status(remotePath, { messages: true, uidValidity: true }), options);
  options.onInventory?.({ selectedCount, statusCount: status?.messages ?? null });
  if (!Number.isSafeInteger(status?.messages) || status.messages < 0
    || (status.uidValidity != null && String(status.uidValidity) !== String(validity)))
    throw new ServiceError('服务器未确认文件夹邮件数量或身份，本机缓存已保留，请重试同步。', 502);
  const uids = await imapOperation(client, () => client.search({ all: true }, { uid: true }), options);
  options.onInventory?.({ uidCount: Array.isArray(uids) ? uids.length : null });
  if (!Array.isArray(uids) || !uids.every(uid => Number.isSafeInteger(uid) && uid > 0)
    || new Set(uids).size !== uids.length || uids.length !== status.messages)
    throw new ServiceError('服务器返回的邮件 UID 清单不完整，本机缓存已保留，请重试同步。', 502);
  const fetched = [];
  const inventory = { metadataRequests: 0, metadataRetryRequests: 0, metadataRecoveredCount: 0 };
  const report = pending => options.onInventory?.({ ...inventory, metadataCount: fetched.length,
    metadataMissingCount: pending.size, metadataMissingUIDs: [...pending].slice(0, 20) });
  const fetchPage = async (page, pending, retry = false) => {
    const requested = new Set(page);
    inventory.metadataRequests++;
    if (retry) inventory.metadataRetryRequests++;
    try {
      await imapOperation(client, async () => {
        // ENVELOPE and INTERNALDATE can make otherwise successful bulk requests
        // silently omit messages. Reconciliation only needs these lightweight fields.
        for await (const remote of client.fetch(page, { uid: true, flags: true, size: true }, { uid: true })) {
          options.signal?.throwIfAborted();
          if (!requested.has(remote?.uid) || !(remote.flags instanceof Set)
            || !Number.isSafeInteger(remote.size) || remote.size < 0 || !pending.delete(remote.uid))
            throw new ServiceError('服务器返回的邮件清单不完整，本机缓存已保留，请重试同步。', 502);
          fetched.push(remote);
          if (retry) inventory.metadataRecoveredCount++;
        }
      }, options);
    } finally { report(pending); }
  };
  for (let offset = 0; offset < uids.length; offset += 200) {
    const page = uids.slice(offset, offset + 200);
    const pending = new Set(page);
    await fetchPage(page, pending);
    // Retry only missing UIDs, down to individual messages, with a separate
    // deadline per command and a finite request budget for an unresponsive server.
    let retries = 0;
    for (const size of [50, 10, 1]) {
      const missing = [...pending];
      for (let start = 0; start < missing.length && retries < 24; start += size) {
        retries++;
        await fetchPage(missing.slice(start, start + size), pending, true);
      }
      if (!pending.size) break;
    }
    if (pending.size)
      throw new ServiceError('服务器返回的邮件清单不完整，本机缓存已保留，请重试同步。', 502);
  }
  options.signal?.throwIfAborted();
  report(new Set());
  return { fetched, validity: String(validity) };
}

function retainInternalDate(remote, response) {
  if (response?.internalDate instanceof Date && Number.isFinite(response.internalDate.getTime()))
    remote.internalDate = response.internalDate;
}

export async function messageSource(client, remote, options) {
  // Small messages need one round trip. Large messages use bounded partial FETCH
  // commands so slow, active transfers do not hold one command past its deadline.
  if (remote.size <= 1024 * 1024) {
    const full = await imapOperation(client,
      () => client.fetchOne(remote.uid, { source: true, internalDate: true }, { uid: true }), options);
    retainInternalDate(remote, full);
    return full?.source;
  }
  const chunks = [], chunkSize = 256 * 1024;
  let downloaded = 0;
  while (downloaded < remote.size) {
    const full = await imapOperation(client, () => client.fetchOne(remote.uid,
      { source: { start: downloaded, maxLength: Math.min(chunkSize, remote.size - downloaded) },
        ...(downloaded === 0 ? { internalDate: true } : {}) }, { uid: true }), options);
    if (downloaded === 0) retainInternalDate(remote, full);
    if (!full?.source && !downloaded) return undefined;
    const bytes = full?.source;
    if (!Buffer.isBuffer(bytes) || !bytes.length || downloaded + bytes.length > remote.size)
      throw new ServiceError('服务器未完整返回邮件正文，已完成的邮件已保存，请继续同步。', 502);
    chunks.push(bytes);
    downloaded += bytes.length;
  }
  return Buffer.concat(chunks, downloaded);
}
