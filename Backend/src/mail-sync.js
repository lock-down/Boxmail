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

export class MessageSourceError extends ServiceError {
  constructor() {
    super('服务器暂未返回完整邮件正文，已下载邮件已保留，稍后同步会重试。', 502);
  }
}

export async function messageSource(client, remote, options = {}) {
  const maximum = 25 * 1024 * 1024;
  // Retry missing / late answers without combining INTERNALDATE with the source.
  // A response for another UID or another byte offset must never enter the MIME.
  const read = async (source, start) => {
    let foreign = false;
    for (let attempt = 0; attempt < 3; attempt++) {
      options.signal?.throwIfAborted();
      options.onSource?.({ requests: 1, retryRequests: attempt ? 1 : 0, lastUID: remote.uid,
        expectedBytes: remote.size });
      let response;
      try {
        response = await imapOperation(client, () => client.fetchOne(remote.uid,
          { source, ...(attempt === 0 && (!start || source === true) ? { internalDate: true } : {}) },
          { uid: true }), options);
      } catch (error) {
        if (!options.signal?.aborted && ['NO', 'BAD'].includes(error.responseStatus) && attempt < 2) continue;
        throw error;
      }
      options.signal?.throwIfAborted();
      const origin = response?.partialOrigins?.get('');
      if ((response?.uid != null && response.uid !== remote.uid)
        || (origin != null && origin !== (start ?? 0))) { foreign = true; continue; }
      retainInternalDate(remote, response);
      if (!Buffer.isBuffer(response?.source)) continue;
      if (source === true && remote.size > 0 && !response.source.length) continue;
      options.onSource?.({ receivedBytes: response.source.length });
      if (response.source.length > maximum) throw new MessageSourceError();
      return response.source;
    }
    if (foreign) throw new MessageSourceError();
  };
  if (remote.size <= 1024 * 1024) return read(true);

  const chunks = [], chunkSize = 256 * 1024;
  let downloaded = 0;
  try {
    // Ask for a complete window even at the advertised end. RFC822.SIZE may be
    // inaccurate; a short final window (or an empty EOF) confirms the real end.
    while (downloaded <= maximum) {
      const bytes = await read({ start: downloaded, maxLength: chunkSize }, downloaded);
      if (!bytes || bytes.length > chunkSize) break;
      if (downloaded + bytes.length > maximum) throw new MessageSourceError();
      chunks.push(bytes);
      downloaded += bytes.length;
      if (bytes.length < chunkSize) {
        if (downloaded === remote.size) return Buffer.concat(chunks, downloaded);
        break;
      }
      if (downloaded > remote.size) break;
    }
  } catch (error) {
    // Deadlines and connection errors already close the socket. Only a response
    // compatibility problem is recoverable with another command on this session.
    if ((!(error instanceof MessageSourceError) && !['NO', 'BAD'].includes(error.responseStatus))
      || options.signal?.aborted) throw error;
  }
  // Some servers ignore ranges, repeat the first chunk or report another size.
  // Replace all partial bytes with one complete BODY.PEEK[] response; never append it.
  chunks.length = 0;
  options.onSource?.({ fullFallbacks: 1 });
  const full = await read(true);
  if (!full?.length) throw new MessageSourceError();
  return full;
}
