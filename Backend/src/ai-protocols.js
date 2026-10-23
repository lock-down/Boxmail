import OpenAI from 'openai';
import Anthropic from '@anthropic-ai/sdk';
import { openAICompletionsApi } from '@earendil-works/pi-ai/api/openai-completions.lazy';
import { openAIResponsesApi } from '@earendil-works/pi-ai/api/openai-responses.lazy';
import { anthropicMessagesApi } from '@earendil-works/pi-ai/api/anthropic-messages.lazy';
import { estimateContextTokens } from '@earendil-works/pi-ai/utils/estimate';
import { reasoningLevel, selectedModel } from './ai-models.js';
import { REASONING_LEVELS, ServiceError } from './validation.js';

const apis = {
  'openai-completions': openAICompletionsApi(),
  'openai-responses': openAIResponsesApi(),
  'anthropic-messages': anthropicMessagesApi(),
};
export const anthropicBaseURL = url => url.replace(/\/v1\/?$/, '');
const incomplete = () => new ServiceError('模型响应未完成或连接中断，未保存不完整结果，请重试或调整思考等级', 502);

// A local route must never fall back to ambient SDK credentials.
class BYOKAnthropic extends Anthropic {
  _shouldResolveDefaultCredentials() { return false; }
}
export function providerClient(config, apiKey) {
  const options = { apiKey: apiKey || 'boxmail-local', maxRetries: 0, timeout: config.timeout * 1000, logLevel: 'off' };
  return config.apiProtocol === 'anthropic-messages'
    ? new BYOKAnthropic({ ...options, baseURL: anthropicBaseURL(config.baseURL), authToken: null,
      defaultHeaders: { Authorization: null, 'x-api-key': apiKey || null } })
    : new OpenAI({ ...options, baseURL: config.baseURL, organization: null, project: null,
      defaultHeaders: apiKey ? {} : { Authorization: null } });
}

export function validateModelInput(config, instructions, content, images) {
  const capability = selectedModel(config);
  if (config.apiProtocol === 'openai-responses' && capability.configuredMaxTokens < 16)
    throw new ServiceError('Responses 的最大输出 token 数至少为 16');
  if (images.length && !capability.input.includes('image'))
    throw new ServiceError(`模型 ${capability.name} 不支持图片输入，请切换模型或在模型目录中确认图片能力`);
  if (!capability.input.includes('text')) throw new ServiceError('邮件助手需要支持文本输入的模型');
  const reasoning = reasoningLevel(capability, config.effort);
  const context = { messages: [{ role: 'system', content: instructions, timestamp: 0 }, { role: 'user', timestamp: Date.now(), content: [
    { type: 'text', text: JSON.stringify(content) }, ...images.map(image => ({
      type: 'image', data: image.buffer.toString('base64'), mimeType: image.contentType,
    })),
  ] }] };
  if (capability.configuredContextWindow && estimateContextTokens(context).tokens >= capability.contextWindow)
    throw new ServiceError('输入内容估算已超过模型上下文窗口，请缩小处理范围或调整模型配置');
  if (reasoning && config.apiProtocol === 'anthropic-messages' && !capability.compat.forceAdaptiveThinking
    && Math.min(capability.maxTokens, capability.contextWindow - estimateContextTokens(context).tokens - 4096) < 2048)
    throw new ServiceError('上下文或输出上限不足以启用思考预算，请至少为思考和回答各保留 1024 token');
  return { capability, reasoning, context };
}

export async function protocolCompletion(config, apiKey, instructions, prepared, { signal, responseParts }) {
  const { capability, reasoning, context } = prepared;
  const model = { id: capability.id, name: capability.name, provider: `boxmail-${config.providerId}`,
    api: config.apiProtocol, baseUrl: config.apiProtocol === 'anthropic-messages' ? anthropicBaseURL(config.baseURL) : config.baseURL,
    reasoning: capability.reasoning, input: capability.input,
    contextWindow: capability.contextWindow, maxTokens: capability.maxTokens,
    thinkingLevelMap: Object.fromEntries(REASONING_LEVELS.map(level => [level, capability.reasoningEfforts?.[level] ?? null])), compat: capability.compat,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
  let httpStatus, terminalText;
  const controller = new AbortController();
  const requestSignal = AbortSignal.any([signal, controller.signal]);
  const events = apis[config.apiProtocol].streamSimple(model, context, {
    apiKey: apiKey || 'boxmail-local', reasoning, maxTokens: capability.configuredMaxTokens,
    signal: requestSignal, timeoutMs: config.timeout * 1000, maxRetries: 0, cacheRetention: 'none', env: {},
    headers: { 'OpenAI-Organization': null, 'OpenAI-Project': null,
      ...(!apiKey ? { Authorization: null, 'x-api-key': null } : {}) },
    fetch: async (url, init) => {
      const response = await fetch(url, init);
      httpStatus = response.status;
      return response;
    },
    onProviderStreamEvent: event => {
      if (config.apiProtocol === 'openai-responses') {
        if (event.item?.type === 'message' && event.item.role !== 'assistant') throw new Error('Invalid assistant role');
        if (event.type === 'response.completed' && event.response?.status === 'completed') {
          // Some compatible gateways only include answer blocks in the terminal event.
          const parts = (event.response.output || []).filter(item => item.type === 'message' && item.role === 'assistant')
            .flatMap(item => item.content || []).filter(part => part.type === 'output_text' && typeof part.text === 'string');
          if (parts.length) terminalText = parts.map(part => part.text).join('');
        }
      } else if (config.apiProtocol === 'anthropic-messages') {
        if (event.type === 'message_start' && event.message?.role !== 'assistant') throw new Error('Invalid assistant role');
      } else if (event.choices?.some(choice => choice.delta?.role && choice.delta.role !== 'assistant')) {
        throw new Error('Invalid assistant role');
      }
    },
    onPayload: payload => {
      if (config.apiProtocol === 'openai-responses') {
        payload.instructions = instructions;
        payload.input = responseParts ? [{ role: 'user', content: responseParts }]
          : payload.input.filter(message => message.role === 'user');
        payload.text = { format: { type: 'json_object' } };
        // Mail tasks do not replay reasoning history or display a thinking summary.
        if (payload.reasoning) delete payload.reasoning.summary;
        delete payload.include;
        // The fallback capability is not an explicitly configured request cap.
        if (!capability.configuredMaxTokens) delete payload.max_output_tokens;
      } else if (config.apiProtocol === 'openai-completions') {
        payload.response_format = { type: 'json_object' };
        if (!capability.configuredMaxTokens) { delete payload.max_tokens; delete payload.max_completion_tokens; }
      }
      return payload;
    },
  });
  try {
    for await (const event of events) {
      if (event.partial?.content.reduce((n, p) => n + (p.text?.length || p.thinking?.length || 0), 0) > 2_000_000)
        throw new ServiceError('模型响应过长，请缩小处理范围', 502);
    }
    if (signal.aborted) throw signal.reason;
    const result = await events.result();
    if (httpStatus >= 400) throw new ServiceError(`AI 服务返回 HTTP ${httpStatus}，请检查地址、密钥、协议和模型`, 502);
    if (result.stopReason === 'error' && /(?:parse|JSON|Unexpected token)/i.test(result.errorMessage || ''))
      throw new ServiceError('模型流式响应格式不正确，请重试', 502);
    if (result.stopReason !== 'stop') throw incomplete();
    const text = terminalText ?? result.content.filter(part => part.type === 'text').map(part => part.text).join('');
    if (text.length > 2_000_000) throw new ServiceError('模型响应过长，请缩小处理范围', 502);
    return text;
  } finally { controller.abort(); }
}
