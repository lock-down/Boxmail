import { createHash, randomUUID } from 'node:crypto';
import { completion, modelConnection } from './responses.js';
import { createIMAPClient } from './imap-connection.js';
import { imapOperation, mailboxUIDNext } from './mail-sync.js';
import { categoryCatalog } from './categories.js';
import { addMatchedLabels } from './mail-labels.js';
import { FollowUps } from './follow-ups.js';
import { summaryResult } from './summary.js';
import { ServiceError } from './validation.js';

const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const jobId = message => 'organization-' + digest([message.accountId, message.id]);
const mailIdentity = account => digest([account.id, account.imapHost, account.imapPort, account.imapTLS, account.username]);
const sameInbox = (a, b) => a?.path?.toUpperCase() === b?.path?.toUpperCase() && a?.validity === b?.validity;
const matchingVersion = ({ id, revision, enabledAt }) => ({ id, revision, enabledAt });
const sourceVersion = message => digest([message.subject, message.body, message.sender, message.senderEmail]);

async function inboxStart(account, password) {
  const client = createIMAPClient(account, password);
  const path = account.folders?.inbox || 'INBOX';
  try {
    await imapOperation(client, () => client.connect());
    const status = await imapOperation(client, () => client.status(path, { uidValidity: true, uidNext: true }));
    return { path, validity: String(status?.uidValidity), uidNext: mailboxUIDNext(status?.uidNext) };
  } finally { client.close(); }
}

export class MailOrganization {
  constructor(repo, credentials, { complete = completion, baseline = inboxStart } = {}) {
    Object.assign(this, { repo, credentials, complete, baseline });
    this.processing = null;
    this.trials = new Set();
    this.controller = new AbortController();
    for (const job of this.jobs('running')) this.repo.put('job', { ...job, status: 'failed', error: '应用退出中断了整理，请检查后重试。' });
  }

  jobs(status) {
    return this.repo.db.prepare(`SELECT data FROM records WHERE kind='job'
      AND json_extract(data,'$.task')='mailOrganization' AND json_extract(data,'$.status')=?
      ORDER BY json_extract(data,'$.createdAt'),json_extract(data,'$.uid'),id`).all(status).map(row => JSON.parse(row.data));
  }

  policy(accountId) {
    const value = this.repo.get('mailOrganizationPolicy', accountId);
    return value || { id: accountId, mode: 'undecided', labelRules: {} };
  }

  connection() {
    const connection = this.credentials.ai();
    modelConnection(connection.config, connection.apiKey);
    return connection;
  }

  async savePolicy({ accountId, mode, labelId, enabled, confirmed }) {
    const account = this.repo.get('account', accountId);
    if (!account) throw new ServiceError('请选择有效的邮箱账户');
    const previous = this.policy(accountId);
    if (labelId !== undefined) {
      const tag = categoryCatalog(this.repo).find(item => item.id === labelId && item.match);
      if (typeof enabled !== 'boolean' || enabled && !tag) throw new ServiceError('请先保存此标签的匹配条件');
      const labelRules = { ...previous.labelRules };
      if (enabled && !labelRules[labelId]) labelRules[labelId] = randomUUID();
      if (!enabled) delete labelRules[labelId];
      return this.repo.put('mailOrganizationPolicy', { ...previous, labelRules });
    }
    if (mode === 'manual') {
      return this.repo.put('mailOrganizationPolicy', { id: accountId, mode, labelRules: previous.labelRules });
    }
    if (mode !== 'automatic' || confirmed !== true || account.isDemo)
      throw new ServiceError('请在真实邮箱中明确确认开启自动整理');
    if (previous.mode === 'automatic') return previous;
    this.connection();
    const grant = randomUUID();
    this.repo.put('mailOrganizationPolicy', { id: accountId, mode, grant, confirmedAt: Date.now(), identity: mailIdentity(account),
      labelRules: previous.labelRules });
    try {
      const point = await this.baseline(account, this.credentials.mail(accountId));
      if (this.policy(accountId).grant === grant && point) this.observeInbox(account, point);
    } catch {
      // The next successful inbox sync can establish the point while this account is offline.
    }
    return this.policy(accountId);
  }

  observeInbox(account, { path, validity, uidNext, observedAt = Date.now() }) {
    const policy = this.policy(account.id);
    const next = Number(mailboxUIDNext(uidNext));
    if (policy.mode !== 'automatic' || policy.identity !== mailIdentity(account) || observedAt < policy.confirmedAt
      || !path || !/^\d+$/.test(validity) || !Number.isSafeInteger(next) || next < 1) return;
    if (sameInbox(policy.point, { path, validity })) return;
    this.repo.put('mailOrganizationPolicy', { ...policy, point: { path, validity, uidNext: next } });
  }

  afterInboxSync(accountId, observed) {
    const policy = this.policy(accountId);
    const account = this.repo.get('account', accountId);
    const point = policy.point;
    if (policy.mode !== 'automatic' || !point || !observed || !account
      || policy.identity !== mailIdentity(account) || (observed.observedAt ?? Date.now()) < policy.confirmedAt || !sameInbox(observed, point)) return;
    const messages = this.repo.db.prepare(`SELECT m.id, json_extract(m.data,'$.uid') AS uid
      FROM records m WHERE kind='message' AND json_extract(data,'$.accountId')=?
      AND json_extract(data,'$.remotePath')=? AND json_extract(data,'$.uidValidity')=?
      AND json_extract(data,'$.folder')='inbox' AND json_extract(data,'$.uid')>=?
      AND json_extract(data,'$.bodyVersion')=1 AND NOT coalesce(json_extract(data,'$.oversized'),0)
      AND NOT coalesce(json_extract(data,'$.organizationRetained'),0)
      ORDER BY uid`).all(accountId, observed.path, point.validity, point.uidNext);
    this.repo.transaction(() => {
      for (const { id, uid } of messages) {
        const receipt = digest([accountId, point.path, point.validity, uid]);
        if (this.repo.get('mailOrganizationReceipt', receipt)) continue;
        this.repo.put('mailOrganizationReceipt', { id: receipt, accountId, messageId: id });
        this.queue({ id, accountId, uid }, { grant: policy.grant, point });
      }
    });
  }

  candidates(accountId, query, offset) {
    if (!this.repo.get('account', accountId) || !Number.isSafeInteger(offset) || offset < 0)
      throw new ServiceError('请选择有效邮箱及页码');
    const { where, params } = this.repo.messageWhere({ query });
    const rows = this.repo.db.prepare(`SELECT m.id, json_extract(m.data,'$.subject') AS subject,
      json_extract(m.data,'$.sender') AS sender, json_extract(m.data,'$.date') AS date
      FROM records m WHERE ${where} AND json_extract(m.data,'$.accountId')=?
      AND json_extract(m.data,'$.folder')<>'trash' AND NOT coalesce(json_extract(m.data,'$.oversized'),0)
      AND (json_extract(m.data,'$.uid') IS NULL OR json_extract(m.data,'$.bodyVersion')=1)
      ORDER BY date DESC,m.id LIMIT 51 OFFSET ?`).all(...params, accountId, offset);
    return { messages: rows.slice(0, 50), nextOffset: rows.length > 50 ? offset + 50 : null };
  }

  messages(accountId, ids) {
    if (!this.repo.get('account', accountId)) throw new ServiceError('请选择有效邮箱');
    if (!Array.isArray(ids) || !ids.length || ids.length > 1000 || ids.some(id => typeof id !== 'string'))
      throw new ServiceError('请选择 1 至 1000 封已缓存的邮件');
    return [...new Set(ids)].map(id => this.message(accountId, id));
  }

  message(accountId, id) {
    const message = this.repo.get('message', id);
    if (!message || message.accountId !== accountId || message.oversized || message.folder === 'trash'
      || (message.uid != null && message.bodyVersion !== 1)) throw new ServiceError('所选邮件已移动、删除或正文未缓存，请重新选择', 409);
    return message;
  }

  queue(message, { grant, point, force, manualRules } = {}) {
    const id = jobId(message);
    const old = this.repo.get('job', id);
    if (old?.status === 'running' || old?.status === 'completed' && !force) return old;
    if (old?.status === 'pending' && (grant || !old.grant)) return old;
    if (grant && old && old.grant !== grant && !['paused', 'failed'].includes(old.status)) return old;
    return this.repo.put('job', { id, task: 'mailOrganization', accountId: message.accountId,
      messageId: message.id, uid: message.uid, status: 'pending', createdAt: new Date().toISOString(), grant, point, manualRules, result: null, error: null });
  }

  organize({ accountId, messageIds, force, expectedLabelIds }, previousRules) {
    const messages = this.messages(accountId, messageIds);
    const rules = this.rules(accountId);
    if (expectedLabelIds !== undefined && (!Array.isArray(expectedLabelIds)
      || JSON.stringify(expectedLabelIds) !== JSON.stringify(rules.map(rule => rule.id).sort())))
      throw new ServiceError('已启用的标签发生变化，请重新打开选信对话框核对提交范围', 409);
    const manualRules = previousRules ?? rules.map(matchingVersion);
    this.connection();
    return this.repo.transaction(() => messages.map(message => this.queue(message, { force: force === true, manualRules })));
  }

  retry(id) {
    const old = this.repo.get('job', id);
    if (old?.task !== 'mailOrganization' || !['failed', 'paused'].includes(old.status))
      throw new ServiceError('此整理任务无法重试', 409);
    return this.organize({ accountId: old.accountId, messageIds: [old.messageId], force: true }, old.manualRules)[0];
  }

  rules(accountId) {
    const { labelRules } = this.policy(accountId);
    return categoryCatalog(this.repo).filter(item => item.match && labelRules?.[item.id]).map(item => ({
      id: item.id, condition: item.match, revision: item.matchRevision, enabledAt: labelRules[item.id],
    }));
  }

  async tick() {
    if (this.processing || this.controller.signal.aborted) return;
    for (const job of this.jobs('pending')) {
      if (job.grant) {
        const policy = this.policy(job.accountId);
        const account = this.repo.get('account', job.accountId);
        if (!account || policy.grant !== job.grant || policy.identity !== mailIdentity(account)
          || !sameInbox(policy.point, job.point)) {
          this.repo.put('job', { ...job, status: 'paused', error: '此邮箱的自动整理授权或收件箱起点已改变。' });
          continue;
        }
      }
      this.processing = this.run(job).finally(() => { this.processing = null; });
      await this.processing;
      break;
    }
  }

  async run(job) {
    try {
      const source = this.message(job.accountId, job.messageId);
      if (job.grant && (source.folder !== 'inbox' || !sameInbox({ path: source.remotePath, validity: source.uidValidity }, job.point)))
        throw new ServiceError('邮件已离开授权的收件箱', 409);
      const rules = this.rules(job.accountId).filter(rule => !job.manualRules || job.manualRules.some(expected =>
        expected.id === rule.id && expected.revision === rule.revision && expected.enabledAt === rule.enabledAt));
      const connection = this.connection();
      this.repo.put('job', { ...job, status: 'running' });
      const needsAttachment = !source.body?.trim() && source.attachmentIds?.length > 0;
      const raw = needsAttachment ? { overview: '需查看原邮件附件', todos: [], labelIds: [] } : await this.request(
        connection, 'mailOrganization', source, rules, job.id);
      const matched = this.matches(raw, rules);
      this.repo.transaction(() => {
        const current = this.message(job.accountId, job.messageId);
        if (sourceVersion(current) !== sourceVersion(source)) throw new ServiceError('邮件内容已变化，请重新整理', 409);
        const latest = this.rules(job.accountId);
        const ids = matched.filter(id => latest.some(rule => {
          const used = rules.find(rule => rule.id === id);
          return rule.id === id && rule.revision === used.revision && rule.enabledAt === used.enabledAt;
        }));
        const summary = summaryResult(raw, current);
        new FollowUps(this.repo).linkLegacyTodos(current);
        const labeled = ids.length ? addMatchedLabels(categoryCatalog(this.repo), current, ids) : current;
        this.repo.put('message', { ...labeled, summary, summaryHidden: current.summaryHidden ?? false,
          ...(current.summary?.context && !current.previousAttachmentSummary ? { previousAttachmentSummary: current.summary } : {}) });
        this.repo.put('job', { ...job, status: 'completed', result: null });
      });
    } catch (error) {
      this.repo.put('job', { ...job, status: 'failed',
        error: error instanceof ServiceError ? error.message : '整理未完成，请检查模型连接后重试。' });
    }
  }

  request({ config, apiKey }, task, message, rules, taskId) {
    const content = { subject: message.subject, body: message.body || '',
      ...(rules.length ? { sender: { name: message.sender, address: message.senderEmail },
        conditions: rules.map(({ id, condition }) => ({ id, condition })) } : {}) };
    return this.complete(config, apiKey, task, content, [], { repository: this.repo, taskId, signal: this.controller.signal });
  }

  matches(raw, rules) {
    if (!Array.isArray(raw?.labelIds) || raw.labelIds.some(id => !rules.some(rule => rule.id === id)))
      throw new ServiceError('模型返回了无效的标签，未保存本次结果', 502);
    return [...new Set(raw.labelIds)];
  }

  async trial({ accountId, messageIds, labelId }) {
    const tag = categoryCatalog(this.repo).find(item => item.id === labelId && item.match);
    if (!tag) throw new ServiceError('请先保存匹配条件');
    const messages = this.messages(accountId, messageIds);
    const connection = this.connection();
    const id = randomUUID();
    const worker = (async () => {
      const matches = [];
      for (const source of messages) {
        const rules = [{ id: tag.id, condition: tag.match }];
        const raw = await this.request(connection, 'labelMatch', source, rules, id);
        if (this.matches(raw, rules).includes(tag.id)) matches.push({ messageId: source.id,
          subject: source.subject, version: sourceVersion(source) });
      }
      this.repo.put('mailLabelTrial', { id, accountId, labelId, revision: tag.matchRevision, matches });
      return { id, matches: matches.map(({ messageId, subject }) => ({ messageId, subject })) };
    })();
    this.trials.add(worker);
    try { return await worker; }
    finally { this.trials.delete(worker); }
  }

  applyTrial({ id, approved }) {
    return this.repo.transaction(() => {
      const trial = this.repo.get('mailLabelTrial', id);
      const catalog = categoryCatalog(this.repo);
      const tag = trial && catalog.find(item => item.id === trial.labelId && item.match && item.matchRevision === trial.revision);
      if (approved !== true || !tag || trial.applied) throw new ServiceError('匹配条件或预览已变化，请重新试用', 409);
      const sources = trial.matches.map(match => {
        const source = this.message(trial.accountId, match.messageId);
        if (sourceVersion(source) !== match.version) throw new ServiceError('邮件已更新，请重新试用', 409);
        return source;
      });
      for (const source of sources) this.repo.put('message', addMatchedLabels(catalog, source, [tag.id]));
      this.repo.put('mailLabelTrial', { ...trial, applied: true });
      return { ok: true };
    });
  }

  async close() {
    this.controller.abort();
    await Promise.allSettled([this.processing, ...this.trials]);
  }
}
