import { createHash, randomUUID } from 'node:crypto';
import { completion, modelConnection } from './responses.js';
import { createIMAPClient } from './imap-connection.js';
import { imapOperation, mailboxUIDNext } from './mail-sync.js';
import { categoryCatalog, organizationCategory, organizationLabelMode } from './categories.js';
import { addMatchedLabels } from './mail-labels.js';
import { FollowUps } from './follow-ups.js';
import { summaryResult } from './summary.js';
import { setImmediate as yieldToRequests } from 'node:timers/promises';
import { ServiceError } from './validation.js';

const digest = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const jobId = message => 'organization-' + digest([message.accountId, message.id]);
const mailIdentity = account => digest([account.id, account.imapHost, account.imapPort, account.imapTLS, account.username]);
const sameInbox = (a, b) => a?.path?.toUpperCase() === b?.path?.toUpperCase() && a?.validity === b?.validity;
const batchLimit = 1000;
const defaultClassification = { mode: 'automatic', labelIds: [] };
const tasks = "kind='job' AND json_extract(data,'$.task') IN ('mailOrganization','labelMatch')";
const pending = `${tasks} AND json_extract(data,'$.status')='pending'`;
const batchKey = "json_extract(data,'$.batchId')";
const activeBatches = `${tasks} AND ${batchKey} IS NOT NULL AND json_extract(data,'$.status') IN ('pending','running')`;
const created = "json_extract(data,'$.createdAt')";
const uid = "json_extract(data,'$.uid')";
const eligibility = `json_extract(m.data,'$.folder')<>'trash' AND NOT coalesce(json_extract(m.data,'$.oversized'),0)
  AND (json_extract(m.data,'$.uid') IS NULL OR json_extract(m.data,'$.bodyVersion')=1)`;
const candidateColumns = `m.id, coalesce(json_extract(m.data,'$.subject'),'') AS subject,
  coalesce(json_extract(m.data,'$.sender'),'') AS sender, coalesce(json_extract(m.data,'$.date'),'') AS date,
  json_extract(m.data,'$.folder') AS folder`;

const matchingVersion = ({ id, revision, enabledAt }) => ({ id, revision, enabledAt });
const sourceVersion = message => digest([message.folder, message.subject, message.body, message.sender, message.senderEmail]);

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
    this.controller = new AbortController();
    this.repo.db.exec(`
      CREATE INDEX IF NOT EXISTS organization_pending ON records(${created},${uid},id) WHERE ${pending};
      CREATE INDEX IF NOT EXISTS organization_batch_jobs ON records(${batchKey},id) WHERE ${tasks};
      CREATE INDEX IF NOT EXISTS organization_active_batches ON records(${batchKey}) WHERE ${activeBatches};
      CREATE INDEX IF NOT EXISTS organization_active_mail ON records(
        json_extract(data,'$.accountId'),json_extract(data,'$.messageId'))
        WHERE kind='job' AND json_extract(data,'$.task')='mailOrganization'
        AND json_extract(data,'$.status') IN ('pending','running');
      CREATE INDEX IF NOT EXISTS organization_batches_recent ON records(${created} DESC,id)
        WHERE kind='mailOrganizationBatch';
      CREATE INDEX IF NOT EXISTS organization_legacy_recent ON records(${created} DESC,id)
        WHERE kind='job' AND json_extract(data,'$.task')='mailOrganization' AND ${batchKey} IS NULL;`);
    this.repo.db.prepare(`UPDATE records SET data=json_set(data,'$.status','failed','$.error',?)
      WHERE ${tasks} AND json_extract(data,'$.status')='running'`).run('应用退出中断了处理，请检查后重试。');
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

  async savePolicy({ accountId, mode, labelId, enabled, classification, confirmed }) {
    const account = this.repo.get('account', accountId);
    if (!account) throw new ServiceError('请选择有效的邮箱账户');
    const previous = this.policy(accountId);
    if (classification !== undefined) {
      if (confirmed !== true) throw new ServiceError('请核对并确认本邮箱的标签方式', 403);
      return this.repo.put('mailOrganizationPolicy', { ...previous,
        classification: organizationLabelMode(this.repo, classification) });
    }
    if (labelId !== undefined) {
      const tag = categoryCatalog(this.repo).find(item => item.id === labelId && item.match);
      if (typeof enabled !== 'boolean' || enabled && !tag) throw new ServiceError('请先保存此标签的匹配条件');
      const labelRules = { ...previous.labelRules };
      if (enabled && !labelRules[labelId]) labelRules[labelId] = randomUUID();
      if (!enabled) delete labelRules[labelId];
      return this.repo.put('mailOrganizationPolicy', { ...previous, labelRules });
    }
    if (mode === 'manual') {
      return this.repo.transaction(() => {
        if (previous.grant) {
          this.repo.db.prepare(`UPDATE records SET data=json_set(data,'$.status','paused','$.error',?)
            WHERE ${pending} AND json_extract(data,'$.grant')=?`)
            .run('已关闭自动整理。可在活动记录中手动重试。', previous.grant);
        }
        return this.repo.put('mailOrganizationPolicy', { id: accountId, mode, labelRules: previous.labelRules, classification: previous.classification });
      });
    }
    if (mode !== 'automatic' || confirmed !== true || account.isDemo)
      throw new ServiceError('请在真实邮箱中明确确认开启自动整理');
    if (previous.mode === 'automatic') return previous;
    this.connection();
    const grant = randomUUID();
    this.repo.put('mailOrganizationPolicy', { id: accountId, mode, grant, confirmedAt: Date.now(), identity: mailIdentity(account),
      labelRules: previous.labelRules, classification: previous.classification });
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
    const messages = this.repo.db.prepare(`SELECT m.id, json_extract(m.data,'$.uid') AS uid, json_extract(m.data,'$.subject') AS subject
      FROM records m WHERE kind='message' AND json_extract(data,'$.accountId')=?
      AND json_extract(data,'$.remotePath')=? AND json_extract(data,'$.uidValidity')=?
      AND json_extract(data,'$.folder')='inbox' AND json_extract(data,'$.uid')>=?
      AND json_extract(data,'$.bodyVersion')=1 AND NOT coalesce(json_extract(data,'$.oversized'),0)
      AND NOT coalesce(json_extract(data,'$.organizationRetained'),0)
      ORDER BY uid`).all(accountId, observed.path, point.validity, point.uidNext);
    this.repo.transaction(() => {
      for (const { id, uid, subject } of messages) {
        const receipt = digest([accountId, point.path, point.validity, uid]);
        if (this.repo.get('mailOrganizationReceipt', receipt)) continue;
        this.repo.put('mailOrganizationReceipt', { id: receipt, accountId, messageId: id });
        this.queue({ id, accountId, uid, subject }, { grant: policy.grant, point });
      }
    });
  }

  candidates(accountId, query, offset, { unread = false, selected = [], count } = {}) {
    if (!this.repo.get('account', accountId) || !Number.isSafeInteger(offset) || offset < 0)
      throw new ServiceError('请选择有效邮箱及页码');
    if (count !== undefined && (!Number.isSafeInteger(count) || count < 1 || count > batchLimit))
      throw new ServiceError(`请选择 1 至 ${batchLimit} 封邮件`);
    const { where, params } = this.repo.messageWhere({ query, filter: unread ? '未读' : undefined });
    const scope = `FROM records m WHERE ${where} AND json_extract(m.data,'$.accountId')=? AND ${eligibility}`;
    const values = [...params, accountId];
    const { total } = this.repo.db.prepare(`SELECT count(*) AS total ${scope}`).get(...values);
    const outside = selected.length ? selected.length - this.repo.db.prepare(`SELECT count(*) AS total ${scope}
      AND m.id IN (SELECT value FROM json_each(?))`).get(...values, JSON.stringify(selected)).total : 0;
    const messages = this.repo.db.prepare(`SELECT ${candidateColumns} ${scope}
      ORDER BY date DESC,m.id LIMIT ? OFFSET ?`).all(...values, count ?? 50, offset);
    return { messages, total, outside, limit: batchLimit,
      nextOffset: offset + messages.length < total ? offset + messages.length : null };
  }

  selectedIDs(ids, allowEmpty = false) {
    if (!Array.isArray(ids) || (!allowEmpty && !ids.length) || ids.length > batchLimit || ids.some(id => typeof id !== 'string'))
      throw new ServiceError(`请选择 1 至 ${batchLimit} 封已缓存的邮件`);
    return [...new Set(ids)];
  }

  eligible(message, accountId) {
    return message != null && message.accountId === accountId && !message.oversized && message.folder !== 'trash'
      && (message.uid == null || message.bodyVersion === 1);
  }

  message(accountId, id) {
    const message = this.repo.get('message', id);
    if (!this.eligible(message, accountId)) throw new ServiceError('所选邮件已移动、删除或正文未缓存', 409);
    return message;
  }

  activeJob(message) {
    const row = this.repo.db.prepare(`SELECT data FROM records INDEXED BY organization_active_mail WHERE kind='job'
      AND json_extract(data,'$.task')='mailOrganization' AND json_extract(data,'$.status') IN ('pending','running')
      AND json_extract(data,'$.accountId')=? AND json_extract(data,'$.messageId')=? LIMIT 1`).get(message.accountId, message.id);
    return row && JSON.parse(row.data);
  }

  queue(message, { grant, point, force = false, manualRules, manualClassification, batchId } = {}) {
    const active = this.activeJob(message);
    const id = batchId ? randomUUID() : jobId(message);
    const old = this.repo.get('job', id);
    if (active && (active.status === 'running' || grant || !active.grant || batchId)) return active;
    if (grant && old && old.grant !== grant && !['paused', 'failed'].includes(old.status)) return old;
    return this.repo.put('job', { id: active?.id || id, task: 'mailOrganization', accountId: message.accountId,
      messageId: message.id, subject: message.subject, uid: message.uid, folder: batchId ? message.folder : undefined, status: 'pending', createdAt: new Date().toISOString(),
      grant, point, force, manualRules, manualClassification, batchId, result: null, error: null });
  }

  scope({ accountId, messageIds, force, labelId, expectedLabelIds, expectedFolders }, { strict = false } = {}) {
    if (!this.repo.get('account', accountId)) throw new ServiceError('请选择有效邮箱');
    const ids = this.selectedIDs(messageIds);
    const rules = labelId ? [] : this.rules(accountId);
    const classification = labelId ? null : this.classification(accountId);
    if (expectedLabelIds !== undefined && (!Array.isArray(expectedLabelIds)
      || JSON.stringify(expectedLabelIds) !== JSON.stringify(rules.map(rule => rule.id).sort())))
      throw new ServiceError('已启用的标签发生变化，请重新核对提交范围', 409);
    const tag = labelId ? categoryCatalog(this.repo).find(item => item.id === labelId && item.match) : null;
    if (labelId && !tag) throw new ServiceError('请先保存匹配条件');
    const items = ids.map(id => {
      const message = this.repo.get('message', id);
      const subject = message?.accountId === accountId ? message.subject : undefined;
      let status = 'new';
      let reason;
      const moved = expectedFolders && Object.hasOwn(expectedFolders, id) && message?.folder !== expectedFolders[id];
      if (!this.eligible(message, accountId) || moved) {
        if (strict) throw new ServiceError('所选邮件已移动、删除或正文未缓存', 409);
        status = 'invalid'; reason = '邮件已移动、删除或正文未缓存';
      } else if (!tag) {
        if (this.activeJob(message)) { status = 'skipped'; reason = '邮件已在队列中'; }
        else if (message.summary != null) {
          status = force === true ? 'update' : 'skipped';
          if (status === 'skipped') reason = '已有整理结果';
        }
      }
      return { id, subject, status, reason, folder: status === 'invalid' ? undefined : message.folder };
    });
    const receipt = digest([accountId, force === true, tag && matchingVersion({ ...tag, revision: tag.matchRevision }), rules, classification, items]);
    return { items, receipt, rules, tag, classification };
  }

  preview(input) {
    const { items, receipt, rules, tag } = this.scope(input);
    return { items, receipt, batchId: randomUUID(), usesLabelConditions: !!tag || rules.length > 0 };
  }

  submit(input) {
    if (input.batchId !== undefined && (typeof input.batchId !== 'string' || !/^[0-9a-f-]{36}$/i.test(input.batchId)))
      throw new ServiceError('批次编号无效');
    const previous = input.batchId && this.repo.get('mailOrganizationBatch', input.batchId);
    if (previous) {
      if (input.receipt !== previous.receipt) throw new ServiceError('批次与已确认的提交范围不同', 409);
      return this.batch(previous.id);
    }
    const { items, receipt, rules, tag, classification } = this.scope(input);
    if (input.receipt !== receipt) throw new ServiceError('所选邮件或标签条件已变化，请重新预览提交范围', 409);
    if (items.some(item => ['new', 'update'].includes(item.status))) this.connection();
    return this.repo.transaction(() => {
      const batch = this.repo.put('mailOrganizationBatch', { id: input.batchId ?? randomUUID(), accountId: input.accountId, receipt,
        createdAt: new Date().toISOString(), ...(tag ? { labelId: tag.id, labelName: tag.name, revision: tag.matchRevision } : {}) });
      for (const item of items) {
        if (item.status === 'invalid' || item.status === 'skipped' || tag) {
          this.repo.put('job', { id: randomUUID(), task: tag ? 'labelMatch' : 'mailOrganization', batchId: batch.id,
            accountId: batch.accountId, createdAt: batch.createdAt, messageId: item.id, subject: item.subject, folder: item.folder,
            status: item.reason ? 'skipped' : 'pending', error: item.reason, ...(tag ? { condition: tag.match } : {}) });
        } else {
          this.queue(this.message(batch.accountId, item.id), { force: input.force === true,
            manualRules: rules.map(matchingVersion), manualClassification: classification, batchId: batch.id });
        }
      }
      return this.batch(batch.id);
    });
  }

  // Keep the existing direct run endpoint usable by older clients.
  organize(input) {
    const { items, rules, classification } = this.scope(input, { strict: true });
    if (items.some(item => ['new', 'update'].includes(item.status))) this.connection();
    return this.repo.transaction(() => items.map(item => {
      const message = this.message(input.accountId, item.id);
      if (item.status === 'skipped') return this.activeJob(message) || {
        id: jobId(message), task: 'mailOrganization', accountId: message.accountId, messageId: message.id,
        status: 'completed', createdAt: new Date().toISOString(), error: item.reason,
      };
      return this.queue(message, { force: input.force === true, manualRules: rules.map(matchingVersion), manualClassification: classification });
    }));
  }

  retry(id) {
    const old = this.repo.get('job', id);
    if (old?.task !== 'mailOrganization' || old.batchId || !['failed', 'paused'].includes(old.status))
      throw new ServiceError('此整理任务无法重试', 409);
    const message = this.message(old.accountId, old.messageId);
    const active = this.activeJob(message);
    if (active) return active;
    this.connection();
    return this.repo.put('job', { ...old, grant: undefined, point: undefined,
      manualRules: old.manualRules ?? this.rules(old.accountId).map(matchingVersion), status: 'pending', error: null });
  }

  batchRecord(id) {
    const batch = this.repo.get('mailOrganizationBatch', id);
    if (!batch) throw new ServiceError('找不到此处理批次', 404);
    return batch;
  }

  batchJobs(id, statuses) {
    const status = statuses ? "AND json_extract(data,'$.status') IN (SELECT value FROM json_each(?))" : '';
    return this.repo.db.prepare(`SELECT data FROM records INDEXED BY organization_batch_jobs WHERE ${tasks} AND ${batchKey}=? ${status} ORDER BY id`)
      .all(id, ...(statuses ? [JSON.stringify(statuses)] : [])).map(row => JSON.parse(row.data));
  }

  batchCounts(id) {
    const rows = this.repo.db.prepare(`SELECT json_extract(data,'$.status') AS status, count(*) AS count
      FROM records INDEXED BY organization_batch_jobs WHERE ${tasks} AND ${batchKey}=? GROUP BY status`).all(id);
    return Object.fromEntries(rows.map(({ status, count }) => [status, count]));
  }

  batchSummary({ receipt, revision, ...batch }) {
    return { ...batch, counts: this.batchCounts(batch.id) };
  }

  batch(id) {
    return { ...this.batchSummary(this.batchRecord(id)), items: this.batchJobs(id).map(job => ({
      id: job.id, messageId: job.messageId, subject: job.subject, status: job.status, error: job.error,
      matched: job.matched, overview: job.overview, todos: job.todos, labelNames: job.labelNames,
    })) };
  }

  progress() {
    const active = this.repo.db.prepare(`SELECT DISTINCT ${batchKey} AS id FROM records INDEXED BY organization_active_batches
      WHERE ${activeBatches}`).all();
    const latest = this.repo.db.prepare(`SELECT id FROM records INDEXED BY organization_batches_recent
      WHERE kind='mailOrganizationBatch' ORDER BY ${created} DESC,id LIMIT 1`).get();
    const ids = new Set([...(latest ? [latest.id] : []), ...active.map(row => row.id)]);
    return [...ids].map(id => this.repo.get('mailOrganizationBatch', id)).filter(Boolean)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.id.localeCompare(b.id))
      .map(batch => this.batchSummary(batch));
  }

  activity() {
    const batches = this.repo.db.prepare(`SELECT data FROM records INDEXED BY organization_batches_recent WHERE kind='mailOrganizationBatch'
      ORDER BY ${created} DESC,id LIMIT 100`).all().map(row => JSON.parse(row.data));
    return {
      batches: batches.map(batch => this.batchSummary(batch)),
      jobs: this.repo.db.prepare(`SELECT data FROM records INDEXED BY organization_legacy_recent WHERE kind='job'
        AND json_extract(data,'$.task')='mailOrganization' AND ${batchKey} IS NULL
        ORDER BY ${created} DESC,id LIMIT 100`).all().map(row => JSON.parse(row.data)),
      usage: this.repo.list('aiUsage').filter(item => ['mailOrganization', 'labelMatch'].includes(item.task))
        .sort((a, b) => b.startedAt.localeCompare(a.startedAt)).slice(0, 100),
    };
  }

  cancelBatch(id, includeRunning = false) {
    this.batchRecord(id);
    const scope = includeRunning ? activeBatches : pending;
    this.repo.db.prepare(`UPDATE records INDEXED BY organization_batch_jobs SET data=json_set(data,'$.status','cancelled')
      WHERE ${scope} AND ${batchKey}=?`).run(id);
    if (includeRunning && this.activeBatch?.id === id) this.activeBatch.controller.abort();
    return this.batch(id);
  }

  retryBatch(id) {
    const batch = this.batchRecord(id);
    if (batch.applied) throw new ServiceError('标签已应用，请重新发起试用', 409);
    this.connection();
    this.repo.transaction(() => {
      for (const job of this.batchJobs(id, ['failed', 'paused'])) {
        const message = this.repo.get('message', job.messageId);
        const active = !batch.labelId && this.eligible(message, job.accountId) && this.activeJob(message);
        this.repo.put('job', { ...job, status: active ? 'skipped' : 'pending', error: active ? '邮件已在队列中' : null });
      }
    });
    return this.batch(id);
  }

  classification(accountId) {
    return this.policy(accountId).classification ?? defaultClassification;
  }

  rules(accountId) {
    const { labelRules, classification } = this.policy(accountId);
    return categoryCatalog(this.repo).filter(item => item.match && labelRules?.[item.id]
      && (classification?.mode !== 'existing' || classification.labelIds.includes(item.id))).map(item => ({
      id: item.id, condition: item.match, revision: item.matchRevision, enabledAt: labelRules[item.id],
    }));
  }

  async tick(blocked = () => false) {
    if (this.processing || this.controller.signal.aborted || blocked()) return;
    this.processing = this.drain(blocked).finally(() => { this.processing = null; });
    await this.processing;
  }

  async drain(blocked) {
    const select = this.repo.db.prepare(`SELECT data FROM records INDEXED BY organization_pending WHERE ${pending} ORDER BY ${created},${uid},id LIMIT 1`);
    while (!this.controller.signal.aborted && !blocked()) {
      const row = select.get();
      if (!row) return;
      const job = JSON.parse(row.data);
      if (job.grant) {
        const policy = this.policy(job.accountId);
        const account = this.repo.get('account', job.accountId);
        if (!account || policy.grant !== job.grant || policy.identity !== mailIdentity(account)
          || !sameInbox(policy.point, job.point)) {
          this.repo.put('job', { ...job, status: 'paused', error: '此邮箱的自动整理授权或收件箱起点已改变。' });
          await yieldToRequests();
          continue;
        }
      }
      const controller = job.batchId ? new AbortController() : null;
      const signal = controller ? AbortSignal.any([this.controller.signal, controller.signal]) : this.controller.signal;
      if (controller) this.activeBatch = { id: job.batchId, controller };
      try {
        if (job.task === 'labelMatch') await this.runTrial(job, signal);
        else await this.run(job, signal);
      } finally { this.activeBatch = null; }
      // Let a cancel or policy update take effect before claiming the next item.
      await yieldToRequests();
    }
  }

  async run(job, signal = this.controller.signal) {
    try {
      const source = this.message(job.accountId, job.messageId);
      if (job.folder && source.folder !== job.folder) throw new ServiceError('邮件已移出选信时所在的文件夹', 409);
      if (source.summary != null && !job.force) {
        this.repo.put('job', { ...job, status: 'skipped', error: '已有整理结果' });
        return;
      }
      if (job.grant && (source.folder !== 'inbox' || !sameInbox({ path: source.remotePath, validity: source.uidValidity }, job.point)))
        throw new ServiceError('邮件已离开授权的收件箱', 409);
      const rules = this.rules(job.accountId).filter(rule => !job.manualRules || job.manualRules.some(expected =>
        expected.id === rule.id && expected.revision === rule.revision && expected.enabledAt === rule.enabledAt));
      const connection = this.connection();
      this.repo.put('job', { ...job, status: 'running' });
      const needsAttachment = !source.body?.trim() && source.attachmentIds?.length > 0;
      const classification = this.classification(job.accountId);
      const classificationMatches = !job.manualClassification || digest(job.manualClassification) === digest(classification);
      const catalog = classificationMatches ? categoryCatalog(this.repo).filter(label =>
        classification.mode === 'automatic' || classification.labelIds.includes(label.id)) : undefined;
      const raw = needsAttachment ? { overview: '需查看原邮件附件', todos: [], labelIds: [] } : await this.request(
        connection, 'mailOrganization', source, rules, { id: job.id, signal, catalog, classificationMode: classification.mode });
      signal.throwIfAborted();
      const matched = this.matches(raw, rules);
      this.repo.transaction(() => {
        const current = this.message(job.accountId, job.messageId);
        if (current.summary != null && !job.force) {
          this.repo.put('job', { ...job, status: 'skipped', error: '已有整理结果' });
          return;
        }
        if (sourceVersion(current) !== sourceVersion(source)) throw new ServiceError('邮件内容已变化，请重新整理', 409);
        const latest = this.rules(job.accountId);
        const ids = matched.filter(id => latest.some(rule => {
          const used = rules.find(rule => rule.id === id);
          return rule.id === id && rule.revision === used.revision && rule.enabledAt === used.enabledAt;
        }));
        const summary = summaryResult(raw, current);
        new FollowUps(this.repo).linkLegacyTodos(current);
        const mayClassify = catalog && digest(classification) === digest(this.classification(job.accountId))
          && (classification.mode === 'automatic' || typeof raw.classification?.id === 'string');
        const classified = mayClassify && organizationCategory(this.repo, raw.classification, catalog);
        if (classified && !ids.includes(classified.id)) ids.push(classified.id);
        const labels = categoryCatalog(this.repo);
        const labeled = ids.length ? addMatchedLabels(labels, current, ids) : current;
        this.repo.put('message', { ...labeled, summary, summaryHidden: current.summaryHidden ?? false,
          ...(current.summary?.context && !current.previousAttachmentSummary ? { previousAttachmentSummary: current.summary } : {}) });
        this.repo.put('job', { ...job, status: 'completed', result: null,
          ...(job.batchId ? { overview: summary.overview, todos: summary.todos, labelNames: labels.filter(label =>
            ids.includes(label.id) && Object.hasOwn(labeled.labels, label.id)).map(label => label.name) } : {}) });
      });
    } catch (error) {
      if (this.repo.get('job', job.id)?.status === 'cancelled') return;
      this.repo.put('job', { ...job, status: 'failed',
        error: error instanceof ServiceError ? error.message : '整理未完成，请检查模型连接后重试。' });
    }
  }

  request({ config, apiKey }, task, message, rules, { id, signal, catalog, classificationMode }) {
    const content = { subject: message.subject, body: message.body || '',
      ...(rules.length ? { sender: { name: message.sender, address: message.senderEmail },
        conditions: rules.map(({ id, condition }) => ({ id, condition })) } : {}) };
    return this.complete(config, apiKey, task, content, [], { repository: this.repo, taskId: id, signal, organizationCategories: catalog, classificationMode });
  }

  matches(raw, rules) {
    if (!Array.isArray(raw?.labelIds) || raw.labelIds.some(id => !rules.some(rule => rule.id === id)))
      throw new ServiceError('模型返回了无效的标签，未保存本次结果', 502);
    return [...new Set(raw.labelIds)];
  }

  submitTrial(input) {
    if (!input.labelId) throw new ServiceError('请选择要试用的标签');
    if (input.receipt) return this.submit(input);
    const { receipt } = this.scope(input, { strict: true });
    return this.submit({ ...input, receipt });
  }

  trialTag(batch) {
    return categoryCatalog(this.repo).find(item => item.id === batch.labelId && item.match && item.matchRevision === batch.revision);
  }

  async runTrial(job, signal = this.controller.signal) {
    try {
      const batch = this.batchRecord(job.batchId);
      if (!this.trialTag(batch)) throw new ServiceError('匹配条件已变化，请重新试用', 409);
      const source = this.message(job.accountId, job.messageId);
      if (job.folder && source.folder !== job.folder) throw new ServiceError('邮件已移出选信时所在的文件夹', 409);
      const connection = this.connection();
      this.repo.put('job', { ...job, status: 'running' });
      const rules = [{ id: batch.labelId, condition: job.condition }];
      const raw = await this.request(connection, 'labelMatch', source, rules, { id: job.id, signal });
      signal.throwIfAborted();
      const matched = this.matches(raw, rules).includes(batch.labelId);
      this.repo.put('job', { ...job, status: 'completed', matched, version: sourceVersion(source) });
    } catch (error) {
      if (this.repo.get('job', job.id)?.status === 'cancelled') return;
      this.repo.put('job', { ...job, status: 'failed',
        error: error instanceof ServiceError ? error.message : '试用未完成，请检查模型连接后重试。' });
    }
  }

  applyTrial({ id, approved }) {
    return this.repo.transaction(() => {
      const batch = this.repo.get('mailOrganizationBatch', id);
      const trial = batch || this.repo.get('mailLabelTrial', id);
      const tag = trial && this.trialTag(trial);
      if (approved !== true || !tag || trial.applied) throw new ServiceError('匹配条件或预览已变化，请重新试用', 409);
      if (batch) {
        const counts = this.batchCounts(id);
        if (counts.pending || counts.running) throw new ServiceError('请等待试用完成或停止剩余邮件', 409);
      }
      const matches = batch ? this.batchJobs(id, ['completed']).filter(job => job.matched) : trial.matches;
      if (!matches.length) throw new ServiceError('没有可应用的匹配结果', 409);
      const sources = matches.map(match => {
        const source = this.message(trial.accountId, match.messageId);
        const version = batch ? sourceVersion(source) : digest([source.subject, source.body, source.sender, source.senderEmail]);
        if (version !== match.version) throw new ServiceError('邮件已更新，请重新试用', 409);
        return source;
      });
      const catalog = categoryCatalog(this.repo);
      for (const source of sources) this.repo.put('message', addMatchedLabels(catalog, source, [tag.id]));
      this.repo.put(batch ? 'mailOrganizationBatch' : 'mailLabelTrial', { ...trial, applied: true });
      return { ok: true };
    });
  }

  async close() {
    this.controller.abort();
    await this.processing;
  }
}
