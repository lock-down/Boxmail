import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';

const text = value => typeof value === 'string' ? value.trim() : '';
// Preserve the legacy points/todos/keyInfo contract while adding a compact overview and explicit suggestions.
export function summaryResult(result, message) {
  const points = Array.isArray(result.points) ? result.points.map(text).filter(Boolean).slice(0, 12) : [];
  const overview = text(result.overview);
  if (!overview && !points.length) throw new ServiceError('摘要格式不正确', 502);
  const suggestions = new Map();
  for (const step of Array.isArray(result.nextSteps) ? result.nextSteps : []) {
    if (!step || !text(step.title)) continue;
    const action = step.action === 'reply' && text(step.prompt) ? 'reply'
      : step.action === 'attachments' && message.attachmentIds?.length ? 'attachments' : 'note';
    const item = { title: text(step.title).slice(0, 60), action, prompt: action === 'reply' ? text(step.prompt).slice(0, 2000) : '' };
    suggestions.set(`${item.action}:${item.title}`, item);
  }
  return {
    overview: overview || points.join(' '),
    points: points.length ? points : [overview],
    todos: (Array.isArray(result.todos) ? result.todos : []).filter(item => item && text(item.title)).slice(0, 12)
      .map(item => ({ id: randomUUID(), title: text(item.title), due: text(item.due), done: false })),
    keyInfo: (Array.isArray(result.keyInfo) ? result.keyInfo : []).filter(item => item && text(item.label) && text(item.value)).slice(0, 10)
      .map(item => ({ label: text(item.label), value: text(item.value) })),
    nextSteps: [...suggestions.values()].slice(0, 4),
  };
}
