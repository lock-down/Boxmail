import { aiConfig, ServiceError } from './validation.js';

export function cachedModelCatalog(repo, baseURL) {
  const endpoint = aiConfig({ baseURL }, { requireModel: false }).baseURL;
  return { models: repo.get('modelCatalog', endpoint)?.models || [] };
}

export async function refreshModelCatalog(repo, input, apiKey) {
  const config = aiConfig(input, { requireModel: false });
  const response = await fetch(`${config.baseURL}/models`, {
    headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok)
    throw new ServiceError(`模型列表请求失败：HTTP ${response.status}`, 502);
  let payload;
  try { payload = await response.json(); }
  catch { throw new ServiceError('模型服务返回的列表格式不正确，请重试', 502); }
  if (!Array.isArray(payload?.data) || payload.data.some(item =>
    typeof item?.id !== 'string' || !item.id.trim() || item.id.trim().length > 500 ||
    /[\u0000-\u001f\u007f]/.test(item.id)))
    throw new ServiceError('模型服务返回的列表格式不正确，请重试', 502);
  const models = [...new Set(payload.data.map(item => item.id.trim()))];
  repo.put('modelCatalog', { id: config.baseURL, models, updatedAt: new Date().toISOString() });
  return { models };
}
