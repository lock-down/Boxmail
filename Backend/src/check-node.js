import { readFileSync } from 'node:fs';

const { engines } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const minimum = engines.node.replace(/^>=/, '').split('.').map(Number);
const current = process.versions.node.split('.').map(Number);
const difference = current.map((value, index) => value - minimum[index]).find(value => value !== 0) ?? 0;

if (difference < 0 || !process.release.lts) {
  console.error(`Boxmail 需要 Node.js ${engines.node} LTS，当前为 ${process.version}${process.release.lts ? ' LTS' : '（非 LTS）'}。`);
  process.exit(2);
}
