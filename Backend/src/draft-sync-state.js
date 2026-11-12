export const DRAFT_READ_RETRY_MS = 60000;
const MAX_READ_FAILURES = 100;
const MAX_DELETION_CHECKS = 3;

// IMAP content is immutable for a UID. Cache content failures briefly, bounded
// by this mailbox identity, so a bad replacement doesn't get parsed every poll.
export class DraftReadFailures {
  constructor(saved, serverIdentity, validity, fetched) {
    this.serverIdentity = serverIdentity;
    this.validity = validity;
    const sizes = new Map(fetched.map(remote => [remote.uid, remote.size]));
    const items = saved?.serverIdentity === serverIdentity && saved?.validity === validity && Array.isArray(saved.items)
      ? saved.items.slice(0, MAX_READ_FAILURES) : [];
    this.items = new Map(items.filter(item => sizes.get(item.uid) === item.size
      && typeof item.error === 'string' && item.error.length <= 2000 && Number.isFinite(item.retryAfter))
      .map(item => [item.uid, item]));
  }
  cached(remote) {
    const item = this.items.get(remote.uid);
    return item?.size === remote.size && item.retryAfter > Date.now() ? item : null;
  }
  record(remote, error, identity = {}) {
    const item = { uid: remote.uid, size: remote.size, error: error.slice(0, 2000),
      retryAfter: Date.now() + DRAFT_READ_RETRY_MS, ...identity };
    if (!this.items.has(remote.uid) && this.items.size >= MAX_READ_FAILURES) this.items.delete(this.items.keys().next().value);
    this.items.set(remote.uid, item);
    return item;
  }
  remove(uid) { this.items.delete(uid); }
  snapshot() { return { serverIdentity: this.serverIdentity, validity: this.validity, items: [...this.items.values()] }; }
}

export function unresolvedDeletion(repo, deletion) {
  if (deletion.reviewRequired) return deletion;
  const checks = Math.min(MAX_DELETION_CHECKS, (deletion.verificationAttempts || 0) + 1);
  return repo.put('draftDeletion', { ...deletion, verificationAttempts: checks,
    reviewRequired: checks === MAX_DELETION_CHECKS });
}
