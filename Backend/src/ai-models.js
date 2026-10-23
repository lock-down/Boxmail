import { REASONING_LEVELS, ServiceError } from './validation.js';

export function selectedModel(config) {
  const provider = config.providers?.find(p => p.id === config.providerId);
  const declared = (provider?.models || config.models || []).find(m => m.id === config.model);
  // Preserve the original Responses connection when migrating an ID-only configuration.
  const legacy = config.providerId === 'default' && config.apiProtocol === 'openai-responses';
  const reasoningEfforts = declared?.reasoningEfforts ?? (legacy
    ? { low: 'low', high: 'high', max: 'max' } : false);
  const levels = reasoningEfforts === false ? [] : REASONING_LEVELS.filter(level => level in reasoningEfforts);
  const contextWindow = declared?.contextWindow ?? 262144;
  return {
    id: config.model, name: declared?.name || config.model,
    contextWindow, maxTokens: declared?.maxTokens ?? Math.min(32768, contextWindow),
    input: declared?.input ?? (legacy && config.model !== 'deepseek-v4-pro'
      ? ['text', 'image'] : ['text']),
    reasoning: levels.some(l => l !== 'off'), reasoningEfforts, levels,
    configuredMaxTokens: declared?.maxTokens, configuredContextWindow: declared?.contextWindow,
    compat: declared?.compat ?? {},
  };
}

export function reasoningLevel(model, effort) {
  if (!model.reasoning) return undefined;
  if (!model.levels.includes(effort)) throw new ServiceError(`模型 ${model.name} 未提供 ${effort} 推理等级，请在设置中重新选择`);
  return effort === 'off' ? undefined : effort;
}
