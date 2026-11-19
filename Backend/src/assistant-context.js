import { estimateContextTokens } from '@earendil-works/pi-ai/utils/estimate';
import { completionInstructions } from './ai-instructions.js';
import { selectedModel, reasoningLevel } from './ai-models.js';
import { prepareMailContext } from './mail-ai-context.js';
import { categoryCatalog } from './categories.js';
import { assistantCandidates, assistantTerms, cachedAssistantDocument, readAssistantSource, sourceAttachments } from './assistant-sources.js';
import { ServiceError } from './validation.js';

const assistantInstructions = '根据本轮 documents 提供的证据回答。history 只帮助理解追问，不能作为新证据。' +
  'contextCoverage 标明本轮查阅范围。资料只覆盖一部分时说明覆盖限制，未提供的附件不得作为依据。' +
  '找不到依据时说明缺少什么，不猜测。引用当前 documents 中的邮件 ID 和附件 ID。';

export async function prepareAssistantContext(repo, config, session, prompt, { signal, publish, compact = false }) {
  const { scope } = session;
  const task = scope.kind === 'attachments' ? 'compare' : 'question';
  const model = selectedModel(config);
  // Use a conservative fallback for custom connections with no declared window.
  // Even very large models only need a bounded amount of evidence per interactive turn.
  const modelWindow = Math.min(model.configuredContextWindow ?? 8192, 32768);
  const window = compact ? Math.floor(modelWindow / 2) : modelWindow;
  const budgetedThinking = config.apiProtocol === 'anthropic-messages'
    && reasoningLevel(model, config.effort) && !model.compat.forceAdaptiveThinking;
  const maxOutputTokens = Math.min(model.maxTokens, Math.max(budgetedThinking ? 2048 : 0, Math.floor(window / 4)));
  const available = window - maxOutputTokens - 256;
  const budget = budgetedThinking ? Math.min(available, modelWindow - 4096 - 2048) : available;
  const options = { additionalInstructions: assistantInstructions, maxOutputTokens };
  const instructions = completionInstructions(config, task, {}, options);
  const contextCoverage = { total: 0, included: 0, partial: false };
  const content = { prompt, scope, cachedOnly: true, documents: [], history: [],
    categories: scope.query?.folder === 'drafts' ? [] : categoryCatalog(repo).map(item => item.name), contextCoverage };
  const images = [], sources = [], original = new Map();
  const fits = (limit = budget) => tokenCost(instructions, content, images) <= limit;
  if (!fits()) throw new ServiceError('问题或模型设置占用了可用上下文，请缩短问题或检查模型上下文窗口');
  const terms = assistantTerms(prompt);
  const envelopeCost = Buffer.byteLength('{"id":"","body":"","attachments":[]}');
  const { ids, total } = assistantCandidates(repo, scope, terms,
    (session.turns.at(-1)?.citations ?? []).map(item => item.messageId),
    // Each source needs at least an id, a body and an attachment array.
    Math.max(1, Math.floor(budget / envelopeCost)));
  if (!total) throw new ServiceError(scope.query?.folder === 'drafts' ? '草稿箱没有可查阅的草稿' : '当前范围没有已缓存邮件');
  contextCoverage.total = total;
  const baseCost = tokenCost(instructions, content, images);
  const historyBudget = baseCost + Math.floor((budget - baseCost) / 4);
  for (const turn of session.turns.slice().reverse()) {
    content.history.unshift({ prompt: turn.prompt, text: turn.text, citations: turn.citations });
    if (fits(historyBudget)) continue;
    content.history.shift();
    break;
  }

  const evidenceBudget = budget - tokenCost(instructions, content, images);
  const share = Math.floor(evidenceBudget / Math.min(ids.length, 4));
  const excerptOnly = ['folder', 'search'].includes(scope.kind) || compact;
  for (const id of ids) {
    signal.throwIfAborted();
    const remaining = budget - tokenCost(instructions, content, images);
    if (remaining < envelopeCost) break;
    const message = readAssistantSource(repo, id);
    if (!message) throw new ServiceError('所选来源已移除，请重新选择范围', 409);
    const attachmentIds = sourceAttachments(scope, message);
    const snapshot = {
      body: message.body, html: message.html, folder: message.folder, category: message.category,
      attachments: attachmentIds.map(id => {
        const file = repo.get('attachment', id);
        return [id, file?.path, file?.size];
      }),
    };
    const allowance = Math.min(remaining, share);
    const include = candidate => {
      if (candidate.images.length) shiftImageIndices(candidate.content.attachments, images.length);
      const before = images.length;
      images.push(...candidate.images);
      content.documents.push({ id, ...candidate.content });
      contextCoverage.included++;
      if (fits(budget - remaining + allowance)) return true;
      images.length = before;
      content.documents.pop();
      contextCoverage.included--;
      return false;
    };

    let prepared = excerptOnly ? null : await prepareMailContext(repo, message, config, {
      signal, attachmentIds, onProgress: stage => publish({ stage }),
    });
    if (!prepared || !include(prepared)) {
      prepared = null;
      for (let length = Math.floor(allowance / 3); length > 0; length = Math.floor(length / 2)) {
        const candidate = cachedAssistantDocument(repo, message, attachmentIds, terms, length);
        if (include(candidate)) { prepared = candidate; break; }
      }
    }
    if (!prepared) {
      if (excerptOnly) break;
      continue;
    }
    contextCoverage.partial ||= prepared.partial || prepared.coverage.partial;
    original.set(id, snapshot);
    sources.push({ id, accountId: message.accountId, subject: message.subject, sender: message.sender,
      date: message.date, coverage: prepared.coverage, draft: !!message.draftId });
  }
  if (!sources.length) throw new ServiceError('模型没有足够的上下文容纳来源，请缩短问题或检查模型上下文窗口');
  contextCoverage.partial ||= sources.length < total;
  return { content, images, sources, original, options };
}

function tokenCost(instructions, content, images) {
  const json = JSON.stringify(content);
  const system = { role: 'system', content: instructions };
  const user = { role: 'user', content: [{ type: 'text', text: json }, ...images.map(() => ({ type: 'image' }))] };
  const sdk = estimateContextTokens({ messages: [system, user] }).tokens;
  const text = estimateContextTokens({ messages: [system, { ...user, content: user.content.slice(0, 1) }] }).tokens;
  // Pi's length estimator can undercount CJK and escaped text. Reserve by byte
  // length for non-ASCII while keeping its image and Latin text estimates.
  const nonASCII = (instructions + json).replace(/[\x00-\x7f]/g, '');
  return sdk - text + Math.max(text, Math.ceil((instructions.length + json.length - nonASCII.length) / 3.5)
    + Buffer.byteLength(nonASCII));
}

function shiftImageIndices(files, offset) {
  for (const file of files) {
    if (file.imageIndices) file.imageIndices = file.imageIndices.map(index => index + offset);
    if (file.entries) shiftImageIndices(file.entries, offset);
  }
}
