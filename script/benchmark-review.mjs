// Run with: node --expose-gc script/benchmark-review.mjs [absolute Backend directory]
// Each scenario runs in a fresh process; setup, indexing and GC precede timing.
import { mkdtemp, rm, writeFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
const root = path.resolve(process.argv[2] || new URL('../Backend/', import.meta.url).pathname);
const scenario = process.argv[3];
if (!scenario) {
  const results = [];
  for (const name of ['draft40','draft120','messagePage','messageHeaders','attachmentHeaders','attachmentSearch','archiveCache','categoryEdit','trashScope']) {
    const samples = [];
    for (let i = 0; i < 3; i++) {
      const child = spawnSync(process.execPath, ['--expose-gc', import.meta.filename, root, name], { encoding: 'utf8' });
      if (child.status) throw new Error(child.stderr || child.stdout);
      samples.push(JSON.parse(child.stdout));
    }
    results.push({ scenario: name, samples });
  }
  console.log(JSON.stringify({ node: process.version, platform: process.platform, arch: process.arch, results }, null, 2));
} else {
  const { Repository } = await import(pathToFileURL(path.join(root, 'src/database.js')));
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-benchmark-'));
  const repo = new Repository(directory);
  let operation, reads = 0, scans = 0;
  try {
    repo.searchIndex.close();
    repo.searchIndex.schedule = () => {};
    const account = { id: 'a', name: 'benchmark', email: 'me@example.test', username: 'me@example.test', folders: { drafts: 'Drafts' } };
    repo.put('account', account);
    if (scenario.startsWith('draft')) {
      const { syncRemoteDrafts } = await import(pathToFileURL(path.join(root, 'src/draft-sync.js')));
      const { draftRevision } = await import(pathToFileURL(path.join(root, 'src/draft-state.js')));
      const scope = createHash('sha256').update(JSON.stringify([undefined, undefined, undefined, account.username, account.email])).digest('hex');
      const n = Number(scenario.slice(5)), uids = Array.from({length: n}, (_, i) => i + 1);
      repo.transaction(() => { for (const uid of uids) {
        const draft = { id: `d${uid}`, accountId: 'a', status: 'draft', body: '正文'.repeat(10000), to: '', subject: '', syncState: 'synced' };
        draft.remoteDraft = { path: 'Drafts', uid, uidValidity: '10', serverIdentity: scope, baseHash: draftRevision(draft) };
        repo.put('draft', draft);
      }});
      const active = repo.activeDrafts.bind(repo);
      repo.activeDrafts = (...args) => { scans++; return active(...args); };
      const client = { mailbox: { uidValidity: '10' }, capabilities: new Set(['UIDPLUS']),
        async getMailboxLock() { return { release() {} }; }, async status() { return { messages: n, uidValidity: '10', uidNext: n+1 }; },
        async search() { return uids; }, async *fetch(ids) { for (const uid of ids) yield { uid, size: 1, flags: new Set() }; } };
      operation = () => syncRemoteDrafts(repo, account, client);
    } else if (scenario.startsWith('message')) {
      repo.transaction(() => { for (let i=0; i<600; i++) repo.put('message', { id: `m${i}`, accountId:'a', folder:'inbox', date:'2026-11-10', body:'正文'.repeat(14000), html:'', attachmentIds:[] }); });
      operation = () => scenario === 'messagePage' ? repo.messagePage({accountId:'a',limit:100}) : repo.messageHeaders('a');
    } else if (['categoryEdit','trashScope'].includes(scenario)) {
      repo.transaction(()=>{for(let i=0;i<12000;i++)repo.put('message',{id:`m${i}`,accountId:'a',folder:i<20?'trash':'inbox',category:i<20?'目标分类':'其他',body:'正文'.repeat(2000),html:'<p>HTML</p>'.repeat(300),attachmentIds:[],date:'2026-11-10'});});
      if(scenario==='categoryEdit') {
        const {editCategory}=await import(pathToFileURL(path.join(root,'src/categories.js')));
        repo.put('categoryCatalog',{id:'categories',items:[{id:'target',name:'目标分类',description:''},{id:'unclassified',name:'未分类',description:''}]});
        operation=()=>editCategory(repo,'target',{},true);
      } else {
        const {clearTrash}=await import(pathToFileURL(path.join(root,'src/mail-trash.js')));
        repo.put('account',{...account,isDemo:true});
        operation=()=>clearTrash(repo,'a','',true,{});
      }
    } else {
      const archive = { hash: 'a'.repeat(64), status:'completed', totalFiles:10, omitted:0, entries:Array.from({length:10},(_,i)=>({id:String(i),name:`合同${i}.txt`,path:`合同${i}.txt`,size:10,contentType:'text/plain',status:'completed',analysis:'分析'.repeat(10000)})), summary:null };
      repo.transaction(() => { for (let i=0;i<30;i++) {
        repo.put('message',{id:`m${i}`,accountId:'a',date:'2026-11-10'});
        repo.put('attachment',{id:`a${i}`,messageId:`m${i}`,name:'资料.zip',contentType:'application/zip',text:'',analysis:'汇总',archive,path:''});
      }});
      if (scenario === 'archiveCache') {
        const { openArchive } = await import(pathToFileURL(path.join(root,'src/archive-service.js')));
        const { default: JSZip } = await import(pathToFileURL(path.join(root, 'node_modules/jszip/lib/index.js')));
        const zip = new JSZip();
        for (let i = 0; i < 10; i++) zip.file(`file${i}.txt`, i === 0 ? Buffer.alloc(24 * 1024 * 1024 - 1024, 65) : 'A');
        const bytes = await zip.generateAsync({ type: 'nodebuffer', compression: 'STORE' });
        const file = path.join(directory, 'sample.zip');
        archive.entries = archive.entries.map((entry, i) => ({ ...entry, name: `file${i}.txt`, path: `file${i}.txt`, size: i === 0 ? 24 * 1024 * 1024 - 1024 : 1 }));
        await writeFile(file,bytes);
        repo.put('attachment',{...repo.get('attachment','a0'),path:file,archive:{...archive,hash:createHash('sha256').update(bytes).digest('hex')}});
        await openArchive(repo,'a0');
        operation = () => openArchive(repo,'a0');
      } else operation = () => scenario === 'attachmentHeaders' ? repo.attachmentHeaders() : repo.attachmentPage({accountId:'a',query:'合同'});
    }
    const get = repo.get.bind(repo);
    repo.get = (...args) => { reads++; return get(...args); };
    global.gc();
    const before = process.memoryUsage(), cpu = process.cpuUsage(), start = performance.now();
    const result = await operation();
    const elapsedMs = performance.now()-start, usage = process.cpuUsage(cpu), after = process.memoryUsage();
    const metrics = { elapsedMs, cpuMs: (usage.user + usage.system) / 1000,
      heapDelta: after.heapUsed - before.heapUsed, rssDelta: after.rss - before.rss,
      maxRSS: process.resourceUsage().maxRSS, reads, scans,
      ...(scenario === 'archiveCache' ? { archiveReadBytes: result.buffer?.length || 0 } : {}) };
    // Measure allocated SQLite pages separately, after the operation has been timed.
    repo.db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    metrics.databaseBytes = (await stat(path.join(directory, 'boxmail.sqlite'))).size;
    console.log(JSON.stringify(metrics));
  } finally { repo.close(); await rm(directory,{recursive:true,force:true}); }
}
