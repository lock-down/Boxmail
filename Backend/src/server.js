import http from 'node:http';
import { randomUUID, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { rm } from 'node:fs/promises';
import { Repository } from './database.js';
import {
  ServiceError,
  accountInput,
  aiConfig,
  recipients,
} from './validation.js';
import { testAccount, syncAccount, updateMessage, restoreMessage, unarchiveMessage, emptyTrash, sendDraft } from './mail.js';
import { archiveRestoreFolder, trashRestoreFolder } from './mail-folders.js';
import { runAgent, approveClassification, useReplyPreview, completion } from './agent.js';
import { saveAttachment, attachmentBytes } from './attachments.js';
import { seedDemo } from './demo.js';
import { DEFAULT_AI, upgradeDefaultPrompts } from './ai-settings.js';
import { Organizer } from './organizer.js';
import { createReplyDraft } from './reply.js';
import { workbookPreview } from './workbook-preview.js';
import { AttachmentBatch } from './attachment-batch.js';
import { cachedModelCatalog, refreshModelCatalog } from './model-catalog.js';
import { categoryCatalog, editCategory } from './categories.js';
import { draftSearchMessage } from './draft-search.js';
import { contactSuggestions } from './contacts.js';
import { conversation } from './threads.js';
import { parseSearch } from './search-query.js';
import { createBackup, inspectBackup, restoreBackup } from './backups.js';
import { exportConfiguration, inspectConfiguration, importConfiguration } from './configuration.js';
import { AIProgress } from './ai-progress.js';
import { setSummaryVisibility } from './summary-overview.js';

export async function startServer({
  directory,
  token,
  port = 0,
  demo = true,
  mailSync = syncAccount,
  mailTest = testAccount,
  mailEmptyTrash = emptyTrash,
  agentRun = runAgent,
  organizerComplete,
  backupCreate = createBackup,
}) {
  if (!token || token.length < 24)
    throw new Error('A session token is required');
  const repo = new Repository(directory);
  if (demo) await seedDemo(repo);
  for (const d of repo.list('draft').filter((d) => d.status === 'sending'))
    repo.put('draft', { ...d, status: 'uncertain' });
  for (const j of repo.list('job').filter((j) => j.status === 'running'))
    repo.put('job', {
      ...j,
      status: (j.task === 'classify' && j.messageIds) || j.task === 'attachmentBatch' ? 'paused' : 'failed',
      ...(j.task === 'attachmentBatch' ? { attachmentItems: j.attachmentItems.map(item =>
        item.status === 'running' ? { ...item, status: 'pending', error: null } : item) } : {}),
      error: '应用关闭中断了任务，已完成的结果已保留，请重试',
    });
  const locks = new Set();
  const clearingTrash = new Set();
  let maintenance = false, activeWrites = 0;
  const syncTasks = new Map();
  const agentTasks = new Map();
  for (const progress of repo.list('sync').filter(p => p.status === 'running'))
    repo.put('sync', { ...progress, status: 'paused', lastError: '应用关闭中断了同步，可继续加载未完成的邮件' });
  function syncStatus() {
    return { runningAccounts: [...syncTasks].filter(([, task]) => task.status === 'running').map(([id]) => id),
      folders: repo.list('sync'),
      results: [...syncTasks].map(([accountId, task]) => ({ accountId, status: task.status, error: task.error || null })) };
  }
  const aiProgress = new AIProgress();
  const onProgress = output => aiProgress.publish(output);
  const organizer = new Organizer(repo, { ...(organizerComplete ? { complete: organizerComplete } : {}), onProgress });
  const attachmentBatch = new AttachmentBatch(repo, { run: agentRun, onProgress });
  function requireIdle() {
    if (activeWrites > 1 || locks.size || repo.list('account').some(account => organizer.busy(account.id) || attachmentBatch.busy(account.id)))
      throw new ServiceError('请等待同步、发送或 AI 任务完成后再维护本机数据', 409);
  }
  const defaults = {
    id: 'settings',
    ai: { ...DEFAULT_AI, prompts: { ...DEFAULT_AI.prompts } },
    preferences: {
      syncMinutes: 5,
      markRead: true,
      signature: '',
      fontSize: 14,
      launchAtLogin: false,
      notifications: false,
      blockRemoteImages: true,
      spamFilter: true,
      language: '简体中文',
    },
  };
  if (!repo.get('settings', 'settings')) repo.put('settings', defaults);
  // Normalize existing 0.0.1 settings without losing custom prompts or providers.
  const saved = repo.get('settings', 'settings');
  let savedAI = { ...DEFAULT_AI, ...saved.ai, prompts: upgradeDefaultPrompts(saved.ai?.prompts) };
  if (!saved.ai.effort && !saved.ai.model && saved.ai.baseURL === 'https://api.openai.com/v1')
    savedAI = { ...savedAI, baseURL: DEFAULT_AI.baseURL, model: DEFAULT_AI.model };
  repo.put('settings', { ...saved, preferences: { ...defaults.preferences, ...saved.preferences }, ai: aiConfig(savedAI, { requireModel: false }) });
  function requestedAI(body) {
    const config = repo.get('settings', 'settings').ai;
    if (body.providerId !== undefined && body.providerId !== config.providerId)
      throw new ServiceError('AI 服务商已切换，请刷新后重试', 409);
    return config;
  }
  categoryCatalog(repo);
  function presentMessage(message) {
    if (message.folder === 'trash') return { ...message,
      restoreFolder: trashRestoreFolder(message, repo.get('account', message.accountId)) };
    if (message.folder === 'archive') return { ...message,
      unarchiveFolder: archiveRestoreFolder(message, repo.get('account', message.accountId)) };
    return message;
  }
  function state(compact = false) {
    return {
      accounts: repo.list('account'),
      messages: (compact ? repo.messageHeaders() : repo.search('')).map(presentMessage),
      drafts: repo.list('draft').filter((d) => d.status !== 'sent'),
      attachments: compact ? repo.attachmentHeaders() : repo.list('attachment'),
      jobs: repo
        .list('job')
        .sort((a, b) => b.createdAt.localeCompare(a.createdAt)),
      settings: repo.get('settings', 'settings'),
      events: repo.events(),
      pendingMutations: repo.list('mutation').length,
      sync: syncStatus(),
      categories: categoryCatalog(repo),
      searchIndex: repo.searchIndex.status(),
    };
  }
  const server = http.createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const provided = Buffer.from(String(req.headers['x-boxmail-token'] || ''));
    const expected = Buffer.from(token);
    if (
      provided.length !== expected.length ||
      !timingSafeEqual(provided, expected) ||
      req.headers.origin
    ) {
      res.writeHead(403);
      res.end(JSON.stringify({ error: '未授权访问' }));
      return;
    }
    let countedWrite = false;
    try {
      const url = new URL(req.url, 'http://127.0.0.1');
      const route = url.pathname;
      if (req.method === 'GET' && route === '/ai/events') {
        aiProgress.subscribe(res);
        return;
      }
      if (maintenance && req.method !== 'GET') throw new ServiceError('正在备份、恢复或重建索引，请稍候', 409);
      let body = {};
      if (['POST', 'PATCH', 'PUT'].includes(req.method)) {
        let size = 0;
        const chunks = [];
        for await (const c of req) {
          size += c.length;
          if (size > 40 * 1024 * 1024)
            throw new ServiceError('请求超过 40 MB', 413);
          chunks.push(c);
        }
        try {
          body = JSON.parse(Buffer.concat(chunks).toString() || '{}');
        } catch {
          throw new ServiceError('请求 JSON 无效');
        }
        if (!body || typeof body !== 'object' || Array.isArray(body))
          throw new ServiceError('请求格式错误');
      }
      if (maintenance && req.method !== 'GET') throw new ServiceError('正在维护本机数据，请稍候', 409);
      if (req.method !== 'GET') { activeWrites++; countedWrite = true; }
      let result;
      if (req.method === 'GET' && route === '/state') result = state(url.searchParams.get('compact') === '1');
      else if (req.method === 'GET' && route === '/sync-status') result = syncStatus();
      else if (req.method === 'POST' && route === '/summaries/visibility') result = setSummaryVisibility(repo, body);
      else if (req.method === 'POST' && route === '/configuration/export') result = exportConfiguration(repo, body.settings);
      else if (req.method === 'POST' && route === '/configuration/inspect') result = inspectConfiguration(repo, body.configuration);
      else if (req.method === 'POST' && route === '/configuration/import') {
        requireIdle();
        result = importConfiguration(repo, body);
      }
      else if (req.method === 'GET' && route === '/categories') result = { categories: categoryCatalog(repo) };
      else if (['POST', 'PATCH', 'DELETE'].includes(req.method) && /^\/categories(?:\/[^/]+)?$/.test(route)) {
        requireIdle();
        result = editCategory(repo, route.split('/')[2] || null, body, req.method === 'DELETE');
      } else if (req.method === 'GET' && route === '/contacts') {
        result = contactSuggestions(repo, url.searchParams.get('accountId'), url.searchParams.get('q') || '', url.searchParams.get('limit'));
      } else if (req.method === 'GET' && /^\/messages\/[^/]+\/thread$/.test(route)) {
        result = conversation(repo, route.split('/')[2], { offset: Number(url.searchParams.get('offset') || 0), limit: Number(url.searchParams.get('limit') || 100) });
        result.messages = result.messages.map(presentMessage);
      } else if (req.method === 'GET' && route === '/search/parse') result = parseSearch(url.searchParams.get('q') || '');
      else if (req.method === 'GET' && route === '/search/index') result = repo.searchIndex.status();
      else if (req.method === 'POST' && route === '/search/rebuild') {
        requireIdle(); maintenance = true;
        try { result = repo.transaction(() => repo.rebuildSearch()); }
        finally { maintenance = false; }
      } else if (req.method === 'POST' && route === '/backups/inspect') result = await inspectBackup(body.path);
      else if (req.method === 'POST' && ['/backups/create', '/backups/restore'].includes(route)) {
        requireIdle(); maintenance = true;
        try {
          result = route.endsWith('/create') ? await backupCreate(repo, body.path)
            : await restoreBackup(repo, body.path, body.approved, { expectedSHA256: body.sha256 });
          if (route.endsWith('/restore')) { syncTasks.clear(); categoryCatalog(repo); }
        } finally { maintenance = false; }
      }
      else if (req.method === 'GET' && route === '/messages') {
        const offset = Number(url.searchParams.get('offset') || 0), limit = Number(url.searchParams.get('limit') || 100);
        if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 200)
          throw new ServiceError('分页参数无效');
        result = repo.messagePage({ accountId: url.searchParams.get('accountId'),
          folder: url.searchParams.get('folder'), filter: url.searchParams.get('filter'),
          query: url.searchParams.get('q') || '', offset, limit });
        result.messages = result.messages.map(presentMessage);
      } else if (req.method === 'GET' && /^\/messages\/[^/]+$/.test(route)) {
        const id = route.split('/')[2];
        result = repo.get('message', id) || draftSearchMessage(repo, id);
        if (!result) throw new ServiceError('邮件不存在或已移动，请刷新列表', 404);
        result = { ...presentMessage(result), bodyLoaded: true };
      } else if (req.method === 'POST' && /^\/messages\/[^/]+\/restore$/.test(route)) {
        const id = route.split('/')[2], message = repo.get('message', id);
        if (message && locks.has(message.accountId))
          throw new ServiceError('该账户正在同步或清空邮件，请完成后再恢复', 409);
        result = restoreMessage(repo, id);
      } else if (req.method === 'POST' && /^\/messages\/[^/]+\/unarchive$/.test(route)) {
        const id = route.split('/')[2], message = repo.get('message', id);
        if (message && locks.has(message.accountId))
          throw new ServiceError('该账户正在同步或清空邮件，请完成后再取消归档', 409);
        result = unarchiveMessage(repo, id);
      } else if (req.method === 'POST' && route === '/trash/empty') {
        if (body.approved !== true) throw new ServiceError('清空已删除邮件需要明确确认', 403);
        if (!repo.get('account', body.accountId)) throw new ServiceError('账户不存在', 404);
        if (locks.has(body.accountId) || locks.has('agent') || organizer.busy(body.accountId)
          || attachmentBatch.busy(body.accountId))
          throw new ServiceError('该账户正在执行任务，请完成后再清空已删除邮件', 409);
        locks.add(body.accountId);
        clearingTrash.add(body.accountId);
        try { result = await mailEmptyTrash(repo, body.accountId, body.password, body.approved); }
        finally { locks.delete(body.accountId); clearingTrash.delete(body.accountId); }
      } else if (req.method === 'POST' && /^\/messages\/[^/]+\/reply-draft$/.test(route)) {
        result = createReplyDraft(repo, route.split('/')[2], { all: body.all === true, forward: body.forward === true });
      }
      else if (req.method === 'GET' && route === '/search')
        result = {
          messages: repo.search(
            url.searchParams.get('q') || '',
            url.searchParams.get('accountId'),
          ),
        };
      else if (req.method === 'POST' && route === '/accounts/test')
        result = await mailTest(accountInput(body.account), body.password);
      else if (req.method === 'POST' && route === '/accounts') {
        const a = accountInput(body.account);
        a.id = a.id || randomUUID();
        if (a.id === 'demo') throw new ServiceError('演示账号不能改为真实账号');
        const old = repo.get('account', a.id);
        repo.put('account', { ...old, ...a, lastSync: old?.lastSync || null });
        result = { id: a.id, ok: true };
      } else if (req.method === 'DELETE' && route.startsWith('/accounts/')) {
        const id = route.split('/')[2];
        if (locks.has(id) || locks.has('agent') || organizer.busy(id) || attachmentBatch.busy(id)
          || repo.list('draft', { accountId: id }).some(draft => draft.status === 'sending'))
          throw new ServiceError('账户正在执行任务，请完成后再移除', 409);
        const candidates = new Set(
          [...repo.list('message'), ...repo.list('draft'),
            ...repo.list('relocation').map(record => record.original),
            ...repo.list('recovery').map(record => record.original)]
            .filter((m) => m.accountId === id)
            .flatMap((m) => m.attachmentIds || []),
        );
        repo.transaction(() => {
          repo.remove('account', id);
          for (const kind of [
            'message',
            'draft',
            'mutation',
            'job',
            'relocation',
            'sync',
            'recovery',
          ])
            for (const v of repo.list(kind).filter((x) => x.accountId === id))
              repo.remove(kind, v.id);
        });
        const referenced = new Set(
          [...repo.list('message'), ...repo.list('draft'),
            ...repo.list('relocation').map(record => record.original),
            ...repo.list('recovery').map(record => record.original)].flatMap(
            (m) => m.attachmentIds || [],
          ),
        );
        for (const aid of candidates) {
          if (referenced.has(aid)) continue;
          const attachment = repo.get('attachment', aid);
          repo.remove('attachment', aid);
          if (attachment)
            await rm(attachment.path, { force: true }).catch(() => {});
        }
        result = { ok: true };
      } else if (req.method === 'POST' && route === '/sync') {
        if (body.folder && !['inbox','sent','trash','drafts','archive','spam'].includes(body.folder))
          throw new ServiceError('请选择有效的邮件文件夹');
        const a = repo.get('account', body.accountId);
        if (!a || a.isDemo) throw new ServiceError('请先添加真实邮箱');
        if (locks.has(a.id)) throw new ServiceError('该账户正在同步', 409);
        locks.add(a.id);
        const controller = new AbortController();
        const task = { status: 'running', controller };
        syncTasks.set(a.id, task);
        const run = async () => {
          try {
            const result = await mailSync(repo, a, body.password, {
              folder: body.folder || undefined, signal: controller.signal });
            task.status = 'completed'; return result;
          } catch (error) {
            task.status = controller.signal.aborted ? 'paused' : 'failed';
            task.error = error instanceof ServiceError ? error.message : '同步未完成，请检查网络与邮箱配置后重试';
            throw error;
          } finally { locks.delete(a.id); }
        };
        task.promise = run();
        if (body.background === true) {
          task.promise.catch(() => {});
          result = { ok: true, status: 'running' };
        } else {
          result = await task.promise;
        }
      } else if (req.method === 'PATCH' && route.startsWith('/messages/')) {
        const id = route.split('/')[2],
          message = repo.get('message', id);
        if (
          message &&
          locks.has(message.accountId) &&
          ['starred', 'unread', 'folder'].some((k) => body[k] !== undefined)
        )
          throw new ServiceError('该账户正在同步或清空邮件，请完成后再修改邮件状态', 409);
        result = presentMessage(updateMessage(repo, id, body));
      } else if (req.method === 'POST' && route === '/todos') {
        const m = repo.get('message', body.messageId);
        if (!m?.summary) throw new ServiceError('邮件没有待办');
        m.summary.todos = m.summary.todos.map((t) =>
          t.id === body.todoId ? { ...t, done: body.done === true } : t,
        );
        result = repo.put('message', m);
      } else if (req.method === 'POST' && route === '/settings') {
        const old = repo.get('settings', 'settings');
        // Older clients edit the active connection through flat fields.
        const providerChanges = body.ai && !body.ai.providers && old.ai.providers
          ? { providers: old.ai.providers.map(provider => provider.id === (body.ai.providerId || old.ai.providerId)
            ? { ...provider, ...Object.fromEntries(['baseURL', 'model', 'apiProtocol']
              .filter(key => body.ai[key] !== undefined).map(key => [key, body.ai[key]])) } : provider) } : {};
        const ai = body.ai
          ? aiConfig({ ...old.ai, ...body.ai, ...providerChanges, prompts: { ...old.ai.prompts, ...body.ai.prompts } }, { requireModel: false })
          : old.ai;
        const p = { ...old.preferences, ...body.preferences };
        const preferences = {
          ...old.preferences,
          ...p,
          syncMinutes: Math.min(60, Math.max(1, Number(p.syncMinutes) || 5)),
          fontSize: Math.min(24, Math.max(12, Number(p.fontSize) || 14)),
          signature: String(p.signature || '').slice(0, 4000),
        };
        result = repo.put('settings', { ...old, id: 'settings', ai, preferences });
      } else if (req.method === 'POST' && route === '/ai/test') {
        await completion(body.config, body.apiKey, 'compose', {
          request: '返回 subject 和 body，内容为连接成功',
        });
        result = { ok: true };
      } else if (req.method === 'GET' && route === '/ai/models') {
        const ai = repo.get('settings', 'settings').ai;
        result = cachedModelCatalog(repo, {
          baseURL: url.searchParams.get('baseURL') || ai.baseURL,
          providerId: url.searchParams.get('providerId') || (url.searchParams.has('baseURL') ? 'default' : ai.providerId),
          apiProtocol: url.searchParams.get('apiProtocol') || (url.searchParams.has('baseURL') ? 'openai-responses' : ai.apiProtocol),
        });
      } else if (req.method === 'POST' && route === '/ai/models') {
        result = await refreshModelCatalog(repo, body.config, body.apiKey);
      } else if (req.method === 'POST' && /^\/messages\/[^/]+\/attachments\/analyze$/.test(route)) {
        const message = repo.get('message', route.split('/')[2]);
        if (clearingTrash.has(message?.accountId)) throw new ServiceError('正在清空已删除邮件，请稍候', 409);
        if (locks.has('agent')) throw new ServiceError('AI 正在执行任务，请等待完成', 409);
        result = attachmentBatch.start({ ...body, messageId: route.split('/')[2], config: requestedAI(body) });
      } else if (req.method === 'POST' && (route === '/organize' || (route === '/agent' && body.task === 'classify'))) {
        if (clearingTrash.has(body.accountId)) throw new ServiceError('正在清空已删除邮件，请稍候', 409);
        result = organizer.start({ ...body, config: requestedAI(body) });
      } else if (req.method === 'GET' && /^\/jobs\/[^/]+$/.test(route)) {
        result = repo.get('job', route.split('/')[2]);
        if (!result) throw new ServiceError('任务不存在', 404);
      } else if (req.method === 'POST' && /^\/jobs\/[^/]+\/draft$/.test(route)) {
        result = useReplyPreview(repo, route.split('/')[2]);
      } else if (req.method === 'POST' && /^\/jobs\/[^/]+\/pause$/.test(route)) {
        const id = route.split('/')[2];
        result = await (repo.get('job', id)?.task === 'attachmentBatch' ? attachmentBatch : organizer).pause(id);
      } else if (req.method === 'POST' && /^\/jobs\/[^/]+\/retry$/.test(route)) {
        const id = route.split('/')[2], job = repo.get('job', id);
        if (!job) throw new ServiceError('任务不存在', 404);
        if (clearingTrash.has(job.accountId)) throw new ServiceError('正在清空已删除邮件，请稍候', 409);
        if (job.task === 'attachmentBatch' && locks.has('agent'))
          throw new ServiceError('AI 正在执行任务，请等待完成', 409);
        result = (job.task === 'attachmentBatch' ? attachmentBatch : organizer).start({ accountId: job.accountId, apiKey: body.apiKey,
          config: requestedAI(body) }, id);
      } else if (req.method === 'POST' && route === '/agent') {
        const messageId = body.messageId || (body.attachmentId ? repo.get('attachment', body.attachmentId)?.messageId : null);
        const message = messageId ? repo.get('message', messageId) : null;
        if (clearingTrash.has(message?.accountId || body.accountId))
          throw new ServiceError('正在清空已删除邮件，请稍候', 409);
        if (body.task === 'attachment') {
          const messageId = repo.get('attachment', body.attachmentId)?.messageId;
          if (messageId && attachmentBatch.active(messageId))
            throw new ServiceError('本封邮件正在批量理解附件，请等待完成后再单独理解。', 409);
        }
        if (locks.has('agent'))
          throw new ServiceError('AI 正在执行任务，请等待完成', 409);
        locks.add('agent');
        if (body.background === true) {
          // The model call has its own deadline; an HTTP start response only
          // transfers the job id. Polling can reconnect without resubmitting it.
          const job = { id: randomUUID(), task: body.task, status: 'running',
            accountId: message?.accountId || body.accountId || null, messageId,
            attachmentId: body.attachmentId || null, createdAt: new Date().toISOString(), result: null, error: null };
          const controller = new AbortController();
          const worker = { controller, promise: null };
          try {
            const config = requestedAI(body);
            repo.put('job', job);
            agentTasks.set(job.id, worker);
            worker.promise = Promise.resolve().then(() => agentRun(repo, {
              ...body, config, onProgress, signal: controller.signal,
            }, { jobId: job.id })).catch(error => {
              const current = repo.get('job', job.id) || job;
              repo.put('job', { ...current, status: controller.signal.aborted ? 'paused' : 'failed',
                error: error instanceof ServiceError ? error.message
                  : error.name === 'TimeoutError' ? 'AI 请求超时，可单独重试这封邮件。' : 'AI 任务未完成，请检查模型连接后重试。' });
            }).finally(() => { locks.delete('agent'); agentTasks.delete(job.id); });
            result = job;
          } catch (error) { locks.delete('agent'); throw error; }
        } else {
          try {
            result = await agentRun(repo, { ...body, config: requestedAI(body), onProgress });
          } finally { locks.delete('agent'); }
        }
      } else if (
        req.method === 'POST' &&
        /^\/jobs\/[^/]+\/(approve|undo)$/.test(route)
      )
        result = approveClassification(
          repo,
          route.split('/')[2],
          route.endsWith('/undo'),
        );
      else if (req.method === 'POST' && route === '/drafts') {
        if (!repo.get('account', body.accountId))
          throw new ServiceError('请选择发送账户');
        const id = body.id || randomUUID();
        const old = repo.get('draft', id);
        if (old && ['sent', 'sending', 'uncertain'].includes(old.status))
          throw new ServiceError('该草稿不能修改，请另存为新草稿', 409);
        const draft = {
          id,
          accountId: body.accountId,
          to: String(body.to || ''),
          cc: String(body.cc || ''),
          bcc: String(body.bcc || ''),
          subject: String(body.subject || '').slice(0, 2000),
          body: String(body.body || '').slice(0, 500000),
          attachmentIds: (body.attachmentIds || []).filter((a) =>
            repo.get('attachment', a),
          ),
          inReplyTo: String(body.inReplyTo || ''),
          references: Array.isArray(body.references) ? body.references.filter(v => typeof v === 'string' && /^<[^<>\s]+>$/.test(v)).slice(-100) : [],
          status: 'draft',
          updatedAt: new Date().toISOString(),
          sourceMessageId: body.sourceMessageId || null,
        };
        result = repo.put('draft', draft);
      } else if (req.method === 'DELETE' && route.startsWith('/drafts/')) {
        const id = route.split('/')[2];
        if (['sending', 'uncertain'].includes(repo.get('draft', id)?.status))
          throw new ServiceError('该草稿的发送结果待确认', 409);
        repo.remove('draft', id);
        result = { ok: true };
      } else if (req.method === 'POST' && route === '/send')
        result = await sendDraft(
          repo,
          body.draftId,
          body.password,
          body.approved,
        );
      else if (req.method === 'POST' && route === '/attachments') {
        if (typeof body.content !== 'string' || !body.name)
          throw new ServiceError('附件无效');
        result = await saveAttachment(
          repo,
          body.messageId || body.draftId || '',
          body.name,
          Buffer.from(body.content, 'base64'),
          body.contentType,
        );
      } else if (req.method === 'GET' && route === '/attachments/search') {
        const query = (url.searchParams.get('q') || '').slice(0,4000);
        result = { ids: repo.searchAttachmentIDs(query, url.searchParams.get('accountId') || '') };
      } else if (req.method === 'GET' && /^\/attachments\/[^/]+\/preview$/.test(route)) {
        const a = await attachmentBytes(repo, route.split('/')[2]);
        if (!a.metadata.name.toLowerCase().endsWith('.xlsx')) throw new ServiceError('此格式请使用系统原文件预览');
        result = { html: await workbookPreview(a.buffer) };
      } else if (req.method === 'GET' && /^\/attachments\/[^/]+\/metadata$/.test(route)) {
        result = repo.get('attachment', route.split('/')[2]);
        if (!result) throw new ServiceError('附件不存在', 404);
      } else if (req.method === 'GET' && route.startsWith('/attachments/')) {
        const a = await attachmentBytes(repo, route.split('/')[2]);
        result = {
          name: a.metadata.name,
          content: a.buffer.toString('base64'),
        };
      } else throw new ServiceError('接口不存在', 404);
      res.writeHead(200);
      res.end(JSON.stringify(result));
    } catch (e) {
      res.writeHead(e.status || 500);
      res.end(
        JSON.stringify({
          error:
            e instanceof ServiceError
              ? e.message
              : e.name === 'TimeoutError'
                ? '请求超时，请重试'
                : '操作失败，请检查网络、邮箱配置或文件内容',
        }),
      );
    } finally { if (countedWrite) activeWrites--; }
  });
  await new Promise((resolve) => server.listen(port, '127.0.0.1', resolve));
  return {
    server,
    repo,
    port: server.address().port,
    close: async () => {
      for (const task of syncTasks.values()) if (task.status === 'running') task.controller.abort();
      for (const task of agentTasks.values()) task.controller.abort();
      await Promise.allSettled([...syncTasks.values(), ...agentTasks.values()].map(task => task.promise));
      await organizer.close();
      await attachmentBatch.close();
      aiProgress.close();
      await new Promise((resolve) => server.close(resolve));
      repo.close();
    },
  };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const app = await startServer({
    directory: process.env.BOXMAIL_DATA,
    token: process.env.BOXMAIL_TOKEN,
    port: Number(process.env.BOXMAIL_PORT || 0),
    demo: process.env.BOXMAIL_DEMO !== '0',
  });
  process.stdout.write(JSON.stringify({ port: app.port }) + '\n');
  const stop = async () => {
    await app.close();
    process.exit(0);
  };
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  const parent = process.ppid;
  setInterval(() => {
    try {
      process.kill(parent, 0);
    } catch {
      stop();
    }
  }, 5000).unref();
}
