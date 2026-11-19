import { usageRequest } from './ai-usage.js';
import { aiConfig, ServiceError } from './validation.js';
import { partialResult } from './ai-progress.js';
import { errorDiagnostic } from './diagnostics.js';

import { OUTPUT_FORMATS, completionInstructions } from './ai-instructions.js';

export async function completion(configInput, apiKey, task, content, images = [], options = {}) {
  const started = performance.now();
  const config = aiConfig(configInput, { requireModel: false });
  if (!config.model)
    throw new ServiceError('请先在设置 > AI 助手中填写模型名称并保存');
  if (!config.enabled) throw new ServiceError('请先启用 AI 助手');
  const local = ['localhost', '127.0.0.1', '[::1]'].includes(new URL(config.baseURL).hostname);
  if (!apiKey && !local) throw new ServiceError('请在设置中填写 API Key');
  if (!OUTPUT_FORMATS[task]) throw new ServiceError('未知 AI 任务');

  const { protocolCompletion, providerClient, validateModelInput } = await import('./ai-protocols.js');
  const client = config.apiProtocol === 'openai-responses' && config.providerId === 'default'
    ? providerClient(config, apiKey) : null;
  const deadline = AbortSignal.timeout(config.timeout * 1000);
  const signal = options.signal ? AbortSignal.any([deadline, options.signal]) : deadline;
  const uploaded = [];
  const usage = usageRequest(options.repository, config, task, options.taskId);
  let usageStatus = "failed";
  try {
    const instructions = completionInstructions(config, task, content, options);
    const prepared = validateModelInput(config, instructions, content, images, {
      inlineImages: !client, maxOutputTokens: options.maxOutputTokens,
    });
    const parts = client ? [{ type: 'input_text', text: prepared.context.messages[1].content[0].text }] : undefined;
    if (client) {
      const { toFile } = images.length ? await import('openai') : {};
      for (const image of images) {
        let file;
        try {
          file = await client.files.create({ purpose: 'user_data',
            expires_after: { anchor: 'created_at', seconds: 3600 },
            file: await toFile(image.buffer, image.name, { type: image.contentType }),
          }, { signal });
        } catch (error) {
          if (signal.aborted) throw signal.reason;
          throw new ServiceError(`附件上传失败${error.status ? `：HTTP ${error.status}` : ''}，请检查模型服务的 Files API`, 502);
        }
        if (typeof file.id !== 'string' || !file.id || file.id.length > 500)
          throw new ServiceError('模型服务未返回有效文件 ID', 502);
        uploaded.push(file.id);
        parts.push({ type: 'input_image', file_id: file.id });
      }
    }
    const raw = await protocolCompletion(config, apiKey, instructions, prepared, { signal, responseParts: parts,
      onUsage: value => usage?.update(value),
      onText: options.onProgress ? raw => options.onProgress(partialResult(raw)) : undefined });
    if (!raw.trim()) throw new ServiceError('模型返回内容为空', 502);
    try {
      const result = JSON.parse(raw.replace(/^\s*```(?:json)?\s*/, '').replace(/\s*```\s*$/, ''));
      if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error('Expected object');
      usageStatus = "completed";
      options.onProgress?.(result);
      return result;
    } catch {
      throw new ServiceError('模型未返回有效 JSON，请调整模型或提示词后重试', 502);
    }
  } catch (error) {
    options.diagnostics?.record('ai.request.failed', { protocol: config.apiProtocol,
      task: Object.hasOwn(OUTPUT_FORMATS, task) ? task : 'unknown', durationMs: performance.now() - started,
      ...errorDiagnostic(signal.aborted ? signal.reason : error) });
    if (signal.aborted) throw signal.reason;
    if (error instanceof ServiceError) throw error;
    if (error instanceof SyntaxError)
      throw new ServiceError('AI 服务返回的响应格式不正确，请重试', 502);
    if (error instanceof TypeError || error.message === 'terminated')
      throw new ServiceError('与 AI 服务的连接已中断，未保存不完整结果。请重试，或检查服务商连接与模型上下文配置。', 502);
    throw error;
  } finally {
    usage?.finish(signal.aborted ? "cancelled" : usageStatus);
    // Expiration also bounds retention if cleanup cannot reach the service.
    await Promise.allSettled(uploaded.map(id => client.files.delete(id, { signal: AbortSignal.timeout(3000) })));
  }
}
