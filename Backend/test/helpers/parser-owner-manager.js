import { ParserProcess } from '../../src/parser-process.js';
import { setTimeout as delay } from 'node:timers/promises';
const parser = new ParserProcess({ executable: new URL('./parser-fault.js', import.meta.url) });
parser.run('docx', Buffer.from('SYNTHETIC_BUSY'), { readyFile: process.argv[2] }).catch(() => {});
while (!parser.child) await delay(5);
process.stdout.write(JSON.stringify({ pid: parser.child.pid, directory: parser.directory }) + '\n');
