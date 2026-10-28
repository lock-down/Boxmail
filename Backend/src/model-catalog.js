import { aiConfig, aiModel, ServiceError } from './validation.js';
import { errorDiagnostic } from './diagnostics.js';

function catalogKey(config) {
  return config.providerId === 'default' && config.apiProtocol === 'openai-responses'
    ? config.baseURL : JSON.stringify([config.providerId, config.apiProtocol, config.baseURL]);
}
function publicCatalog(catalog) {
  return { models: catalog?.models || [], ...(catalog?.details ? { details: catalog.details } : {}) };
}
export function cachedModelCatalog(repo, input) {
  const config = aiConfig(typeof input === 'string' ? { baseURL: input } : input, { requireModel: false });
  return publicCatalog(repo.get('modelCatalog', catalogKey(config)));
}
function discoveredModel(item) {
  const details = { id: item.id };
  const name = item.name ?? item.display_name ?? item.displayName;
  if (typeof name === 'string' && name.trim()) details.name = name.trim();
  const context = item.contextWindow ?? item.context_window ?? item.context_length ?? item.max_input_tokens ?? item.limit?.context;
  const output = item.maxOutputTokens ?? item.max_output_tokens ?? item.maxTokens ?? item.max_tokens
    ?? item.limit?.output ?? item.top_provider?.max_completion_tokens;
  if (Number.isSafeInteger(context) && context > 0) details.contextWindow = context;
  if (Number.isSafeInteger(output) && output > 0) details.maxTokens = output;
  const input = item.input ?? item.input_modalities ?? item.architecture?.input_modalities;
  if (Array.isArray(input) && input.some(v => v === 'text' || v === 'image'))
    details.input = input.filter(v => ['text', 'image'].includes(v));
  return aiModel(details);
}

export async function refreshModelCatalog(repo, input, apiKey) {
  const config = aiConfig(input, { requireModel: false });
  const { providerClient } = await import('./ai-protocols.js');
  const client = providerClient(config, apiKey);
  const models = new Map(), cursors = new Set(), signal = AbortSignal.timeout(15000);
  let cursor;
  try {
    do {
      const response = await (config.apiProtocol === 'anthropic-messages'
        ? client.models.list({ limit: 1000, ...(cursor ? { after_id: cursor } : {}) }, { signal })
        : client.models.list({ signal })).asResponse();
      let payload;
      try { payload = await response.json(); }
      catch { throw new ServiceError('模型服务返回的列表格式不正确，请重试', 502); }
      let entries = payload?.data;
      if (!Array.isArray(entries) && payload?.models && typeof payload.models === 'object' && !Array.isArray(payload.models)) {
        entries = Object.entries(payload.models).map(([id, item]) => item && typeof item === 'object' && !Array.isArray(item)
          ? { ...item, id: item.id ?? id } : null);
      }
      if (!Array.isArray(entries)) throw new ServiceError('模型服务返回的列表格式不正确，请重试', 502);
      for (const item of entries) {
        try { const model = discoveredModel(item); models.set(model.id, { ...models.get(model.id), ...model }); }
        catch { throw new ServiceError('模型服务返回的列表格式不正确，请重试', 502); }
      }
      cursor = config.apiProtocol === 'anthropic-messages' && payload.has_more === true ? payload.last_id : null;
      if (payload.has_more === true && config.apiProtocol === 'anthropic-messages'
        && (typeof cursor !== 'string' || !cursor || cursor.length > 500 || cursors.has(cursor) || cursors.size >= 20))
        throw new ServiceError('模型列表分页格式不正确，请手动添加模型', 502);
      if (models.size > 500) throw new ServiceError('模型列表超过 500 个，请手动添加所需模型', 502);
      if (cursor) cursors.add(cursor);
    } while (cursor);
  } catch (error) {
    repo.diagnostics?.record('ai.models.failed', { protocol: config.apiProtocol, ...errorDiagnostic(error) });
    if (error instanceof ServiceError) throw error;
    throw new ServiceError(error.status ? `模型列表请求失败：HTTP ${error.status}` : '模型列表连接失败或超时，请重试', 502);
  }
  const details = [...models.values()];
  const catalog = { models: [...models.keys()], ...(details.some(m => Object.keys(m).length > 1) ? { details } : {}) };
  repo.put('modelCatalog', { id: catalogKey(config), ...catalog, updatedAt: new Date().toISOString() });
  return catalog;
}
