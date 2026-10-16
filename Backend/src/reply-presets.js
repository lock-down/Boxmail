import { existsSync, readFileSync } from 'node:fs';
const packaged = new URL('../Resources/ReplyPresets.json', import.meta.url);
const source = new URL('../../Sources/BoxmailCore/Resources/ReplyPresets.json', import.meta.url);
export const REPLY_PRESETS = Object.freeze(JSON.parse(readFileSync(existsSync(packaged) ? packaged : source, 'utf8')));
