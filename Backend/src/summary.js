import { textSlice } from './unicode.js';
import { randomUUID } from 'node:crypto';
import { ServiceError } from './validation.js';

const text = value => typeof value === 'string' ? value.trim() : '';
export const todoSourceKey = todo => `todo:${todo.title}\u001f${todo.due}`;
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
    const item = { title: textSlice(text(step.title), 0, 60), action, prompt: action === 'reply' ? textSlice(text(step.prompt), 0, 2000) : '' };
    suggestions.set(`${item.action}:${item.title}`, item);
  }
  const previous = message.summary?.todos || [];
  const suggestionsByKey = new Map();
  for (const item of Array.isArray(result.todos) ? result.todos : []) {
    if (!item || !text(item.title)) continue;
    const todo = { title: text(item.title), due: text(item.due) };
    suggestionsByKey.set(todoSourceKey(todo), todo);
  }
  const suggestionsForMail = [...suggestionsByKey.values()].slice(0, 12);
  const matches = suggestionsForMail.map(todo => previous.find(item => todoSourceKey(item) === todoSourceKey(todo)));
  const matched = new Set(matches.filter(Boolean));
  const todos = suggestionsForMail.map((todo, index) => {
    let prior = matches[index];
    if (!prior && suggestionsForMail.filter(item => item.title === todo.title).length === 1) {
      const sameTitle = previous.filter(item => !matched.has(item) && item.title === todo.title);
      if (sameTitle.length === 1) { prior = sameTitle[0]; matched.add(prior); }
    }
    return { ...todo, id: prior?.id || randomUUID(), done: prior?.done ?? false };
  });
  for (const item of previous) if (item.done && !matched.has(item)) todos.push(item);
  return {
    overview: overview || points.join(' '),
    points: points.length ? points : [overview],
    todos,
    keyInfo: (Array.isArray(result.keyInfo) ? result.keyInfo : []).filter(item => item && text(item.label) && text(item.value)).slice(0, 10)
      .map(item => ({ label: text(item.label), value: text(item.value) })),
    nextSteps: [...suggestions.values()].slice(0, 4),
  };
}
