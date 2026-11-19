import { randomUUID } from 'node:crypto';

export function providerUsage(protocol, event) {
  const usage = protocol === 'openai-responses' ? event.response?.usage
    : protocol === 'anthropic-messages' ? event.message?.usage || event.usage : event.usage;
  if (!usage) return null;
  const number = value => Number.isFinite(value) && value >= 0 ? value : null;
  return { input: number(usage.input_tokens ?? usage.prompt_tokens),
    output: number(usage.output_tokens ?? usage.completion_tokens),
    cacheRead: number(usage.cache_read_input_tokens ?? usage.input_tokens_details?.cached_tokens ?? usage.prompt_tokens_details?.cached_tokens),
    cacheWrite: number(usage.cache_creation_input_tokens) };
}

export function usageRequest(repo, config, task, taskId) {
  if (!repo) return null;
  const value = { id: randomUUID(), task, taskId: taskId || null, provider: config.providerId,
    model: config.model, startedAt: new Date().toISOString(), status: 'running', durationMs: 0,
    input: null, output: null, cacheRead: null, cacheWrite: null, cost: null };
  repo.put('aiUsage', value);
  const started = performance.now();
  return {
    update(usage) {
      if (usage) for (const [key, count] of Object.entries(usage)) if (count !== null) value[key] = count;
      repo.put('aiUsage', value);
    },
    finish(status) { repo.put('aiUsage', { ...value, status, durationMs: Math.round(performance.now() - started) }); },
  };
}
