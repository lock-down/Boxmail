const key = binding => binding && JSON.stringify([binding.path, binding.uidValidity, binding.uid]);
class Lookup {
  values = new Map();
  add(key, id) { if (!key) return; if (!this.values.has(key)) this.values.set(key, new Set()); this.values.get(key).add(id); }
  remove(key, id) { const ids = this.values.get(key); ids?.delete(id); if (!ids?.size) this.values.delete(key); }
  ids(key) { return this.values.get(key) || []; }
}
// Track concurrent saves/deletes without reparsing all bodies after every await.
export class DraftSyncIndex {
  drafts = new Map(); deletions = new Map();
  uid = new Lookup(); token = new Lookup(); message = new Lookup(); pending = new Lookup();
  deletedUID = new Lookup(); deletedToken = new Lookup(); deletedMessage = new Lookup();
  constructor(repo, accountId) {
    this.repo = repo; this.accountId = accountId;
    this.reset();
    this.listener = change => change ? this.update(change.kind, change.id, change.value) : this.reset();
    repo.recordObservers.add(this.listener);
  }
  reset() {
    for (const id of this.drafts.keys()) this.update('draft', id, null);
    for (const id of this.deletions.keys()) this.update('draftDeletion', id, null);
    for (const draft of this.repo.draftSyncHeaders(this.accountId)) this.update('draft', draft.id, draft);
    for (const deletion of this.repo.list('draftDeletion', { accountId: this.accountId })) this.update('draftDeletion', deletion.id, deletion);
  }
  update(kind, id, value) {
    if (!['draft', 'draftDeletion'].includes(kind)) return;
    const draft = kind === 'draft', records = draft ? this.drafts : this.deletions;
    const indexes = draft ? [this.uid, this.token, this.message, this.pending] : [this.deletedUID, this.deletedToken, this.deletedMessage];
    const keys = record => { const binding = draft ? record.remoteDraft : record;
      return [key(binding), binding?.token, binding?.messageId, record.remotePending?.token]; };
    const old = records.get(id);
    if (old) keys(old).forEach((key, i) => indexes[i]?.remove(key, id));
    records.delete(id);
    if (!value || value.accountId !== this.accountId || draft && value.status === 'sent') return;
    // No body/rich-text copies are retained by the index.
    const header = draft ? { id, accountId: value.accountId, remoteDraft: value.remoteDraft, remotePending: value.remotePending, status: value.status } : value;
    records.set(id, header);
    keys(header).forEach((key, i) => indexes[i]?.add(key, id));
  }
  direct(path, validity, uid) { return this.drafts.get([...this.uid.ids(key({path,uidValidity:validity,uid}))][0]); }
  deletion(path, validity, uid, token, messageId) {
    const ids = new Set([...this.deletedUID.ids(key({path,uidValidity:validity,uid})), ...this.deletedToken.ids(token), ...this.deletedMessage.ids(messageId)]);
    return [...ids].map(id => this.deletions.get(id)).find(item => item.path === path);
  }
  candidates(token, messageId) { return [...new Set([...this.pending.ids(token), ...this.token.ids(token), ...this.message.ids(messageId)])].map(id => this.drafts.get(id)); }
  close() { this.repo.recordObservers.delete(this.listener); }
}
