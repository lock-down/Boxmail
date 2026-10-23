// Standard wire events exercise the real pi-ai adapters and their official SDKs.
export function responseOutputEvents(payload) {
  return payload.output.flatMap((item, index) => item.type === 'message' ? [
    { type: 'response.output_item.added', output_index: index, item: { ...item, id: 'msg-' + index, content: [] } },
    { type: 'response.output_item.done', output_index: index, item: { ...item, id: 'msg-' + index } },
  ] : []);
}
export function responsesEvents(payload) {
  return [...responseOutputEvents(payload), { type: payload.status === 'completed' ? 'response.completed'
    : payload.status === 'incomplete' ? 'response.incomplete' : 'response.failed', response: payload }];
}
export function compatibleEvents(apiProtocol, { text, finish, stop = true }) {
  return apiProtocol === 'anthropic-messages'
    ? [{ type: 'message_start', message: { id: 'msg-test', role: 'assistant', model: 'custom-model',
      usage: { input_tokens: 20, output_tokens: 0 } } },
      { type: 'content_block_start', index: 0, content_block: { type: 'thinking', thinking: 'private reasoning' } },
      { type: 'content_block_stop', index: 0 },
      { type: 'content_block_start', index: 1, content_block: { type: 'text', text: '' } },
      { type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: text.slice(0, 12) } },
      { type: 'content_block_delta', index: 1, delta: { type: 'text_delta', text: text.slice(12) } },
      { type: 'content_block_stop', index: 1 },
      ...(stop ? [{ type: 'message_delta', delta: { stop_reason: finish || 'end_turn' }, usage: { output_tokens: 30 } },
        { type: 'message_stop' }] : [])]
    : [{ choices: [{ index: 0, delta: { role: 'assistant', reasoning_content: 'private reasoning' } }] },
      { choices: [{ index: 0, delta: { content: text.slice(0, 12) } }] },
      { choices: [{ index: 0, delta: { content: text.slice(12) } }] },
      ...(stop ? [{ choices: [{ index: 0, delta: {}, finish_reason: finish || 'stop' }] }] : [])];
}
export const sse = events => events.map(event => `data: ${JSON.stringify(event)}\r\n\r\n`).join('');
export const responsesWire = payload => sse(responsesEvents(payload));
