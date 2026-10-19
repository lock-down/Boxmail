import { existsSync, readFileSync } from 'node:fs';
import { LEGACY_PROMPTS } from './legacy-prompts.js';

const packaged = new URL('../Resources/DefaultPrompts.json', import.meta.url);
const source = new URL('../../Sources/BoxmailCore/Resources/DefaultPrompts.json', import.meta.url);
export const DEFAULT_PROMPTS = Object.freeze(JSON.parse(readFileSync(existsSync(packaged) ? packaged : source, 'utf8')));
export function upgradeDefaultPrompts(prompts) {
  const next = { ...prompts };
  for (const [task, previous] of Object.entries(LEGACY_PROMPTS))
    if (next[task]?.trim() === previous) next[task] = DEFAULT_PROMPTS[task];
  return next;
}
export const DEFAULT_AI = Object.freeze({
  baseURL: 'https://api.deepseek.com',
  model: 'deepseek-flash',
  effort: 'high',
  timeout: 120,
  enabled: true,
  prompts: DEFAULT_PROMPTS,
});
