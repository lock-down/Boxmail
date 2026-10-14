import { existsSync, readFileSync } from 'node:fs';

const packaged = new URL('../Resources/DefaultPrompts.json', import.meta.url);
const source = new URL('../../Sources/BoxmailCore/Resources/DefaultPrompts.json', import.meta.url);
export const DEFAULT_PROMPTS = Object.freeze(JSON.parse(readFileSync(existsSync(packaged) ? packaged : source, 'utf8')));
export const DEFAULT_AI = Object.freeze({
  baseURL: 'https://api.deepseek.com',
  model: 'deepseek-flash',
  effort: 'high',
  timeout: 120,
  enabled: true,
  prompts: DEFAULT_PROMPTS,
});
