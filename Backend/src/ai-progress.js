import { EventEmitter } from 'node:events';
import { parseStreamingJson } from '@earendil-works/pi-ai/utils/json-parse';

const text = value => typeof value === 'string' ? value : '';
export function partialResult(raw) {
  const value = parseStreamingJson(raw.replace(/^\s*```(?:json)?\s*/, ''));
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

// Only answer fields enter the UI; JSON syntax, reasoning and tool output stay private.
export function progressText(task, result) {
  if (task === 'summary') return [text(result.overview),
    ...(Array.isArray(result.points) ? result.points.map(p => text(p) && `- ${text(p)}`) : []),
    ...(Array.isArray(result.todos) ? result.todos.map(p => p && text(p.title) && `- 待办：${text(p.title)}${text(p.due) ? `（${p.due}）` : ''}`) : []),
    ...(Array.isArray(result.keyInfo) ? result.keyInfo.map(p => p && text(p.label) && `${p.label}：${text(p.value)}`) : []),
    ...(Array.isArray(result.nextSteps) ? result.nextSteps.map(p => p && text(p.title) && `- ${p.title}`) : []),
  ].filter(Boolean).join('\n\n');
  if (task === 'classify') return (Array.isArray(result.items) ? result.items : [])
    .filter(p => p && text(p.category)).map(p => `${p.category}${text(p.reason) ? `：${p.reason}` : ''}`).join('\n\n');
  if (['reply', 'compose'].includes(task)) return [text(result.subject), text(result.body)].filter(Boolean).join('\n\n');
  return text(result.text);
}

// Progress is ephemeral. Durable results are committed only after validation.
export class AIProgress {
  constructor() { this.active = new Map(); this.clients = new Set(); this.events = new EventEmitter(); this.events.setMaxListeners(0); }
  publish(output) {
    if (output.status === 'running') this.active.set(output.id, output);
    else this.active.delete(output.id);
    this.events.emit('output', output);
  }
  subscribe(res) {
    this.clients.add(res);
    res.writeHead(200, { 'Content-Type': 'text/event-stream; charset=utf-8', 'X-Accel-Buffering': 'no' });
    const send = event => {
      if (!res.destroyed && !res.writableEnded) {
        // A slow reader must reconnect for a snapshot instead of accumulating model output.
        if (res.writableLength > 4_000_000) { res.destroy(); return; }
        res.write(`data: ${JSON.stringify(event)}\n\n`);
      }
    };
    send({ type: 'snapshot', outputs: [...this.active.values()] });
    const listener = output => send({ type: 'update', output });
    this.events.on('output', listener);
    const heartbeat = setInterval(() => { if (!res.destroyed) res.write(': heartbeat\n\n'); }, 15000);
    res.on('close', () => { clearInterval(heartbeat); this.clients.delete(res); this.events.off('output', listener); });
  }
  close() { for (const res of this.clients) res.destroy(); }
}
