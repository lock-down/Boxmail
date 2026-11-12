import test from 'node:test';
import assert from 'node:assert/strict';
import JSZip from 'jszip';
import http from 'node:http';
import { mkdtemp, rm } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { readArchive, ARCHIVE_LIMITS } from '../src/archive-reader.js';
import { openArchive, archiveEntry } from '../src/archive-service.js';
import { archiveSummary } from '../src/archive-summary.js';
import { Repository } from '../src/database.js';
import { saveAttachment } from '../src/attachments.js';
import { AttachmentBatch } from '../src/attachment-batch.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { responsesWire } from './helpers/ai-streams.js';
import { startServer } from '../src/server.js';

async function zipOf(files, compression = 'DEFLATE') {
  const zip = new JSZip();
  for (const [name, content, options] of files) zip.file(name, content, options);
  return zip.generateAsync({type: 'nodebuffer', compression, platform: 'UNIX'});
}
async function fixture(t, files) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'boxmail-archive-'));
  const repo = new Repository(directory);
  repo.put('account',{id:'a'});
  const file = await saveAttachment(repo,'m','项目资料.zip',await zipOf(files),'application/zip');
  repo.put('message',{id:'m',accountId:'a',attachmentIds:[file.id],subject:'采购材料',sender:'测试发件人',body:'请核对报价',date:'2026-11-10T00:00:00Z'});
  t.after(async()=>{repo.close();await rm(directory,{recursive:true,force:true});});
  return {repo,file,directory};
}
test('ZIP preserves Chinese paths, ignores metadata, streams exact bytes and rejects unsafe paths',async()=>{
  const buffer=await zipOf([['合同/采购.txt','金额100元'],['__MACOSX/._采购.txt','ignored'],['.DS_Store','ignored'],['说明.md','材料说明']]);
  const result=await readArchive(buffer);
  assert.deepEqual(result.entries.map(x=>x.path),['合同/采购.txt','说明.md']);
  assert.equal(result.totalFiles,2);
  assert.equal((await readArchive(buffer,{entryId:result.entries[0].id})).buffer.toString(),'金额100元');
  await assert.rejects(readArchive(await zipOf([['../逃逸.txt','bad']])),/路径不安全/);
  await assert.rejects(readArchive(Buffer.from('not zip')),/ZIP/);
  await assert.rejects(readArchive(buffer,{entryId:'999'}),/不存在/);
});
test('ZIP limits, symlinks, nested archives, executable and encrypted entries are explicit',async()=>{
  const files=Array.from({length:102},(_,i)=>[`${i}.txt`,'text']);
  const result=await readArchive(await zipOf(files));
  assert.equal(result.entries.length,100);assert.equal(result.omitted,2);
  const blocked=await readArchive(await zipOf([['nested.zip','nested'],['run.sh','echo bad'],['link.txt','target',{unixPermissions:0o120777}],['big.txt',Buffer.alloc(ARCHIVE_LIMITS.fileBytes+1)]]));
  assert.ok(blocked.entries.every(x=>x.status==='unsupported'));
  const encrypted=await zipOf([['secret.txt','secret'.repeat(12)]],'STORE');
  const central=encrypted.indexOf(Buffer.from([0x50,0x4b,0x01,0x02]));
  encrypted.writeUInt16LE(encrypted.readUInt16LE(central+8)|1,central+8);
  encrypted.writeUInt32LE(encrypted.readUInt32LE(central+24)-12,central+24);
  assert.match((await readArchive(encrypted)).entries[0].error,/加密/);
  const corrupt=await zipOf([['text.txt','unchanged']],'STORE');
  corrupt[corrupt.indexOf(Buffer.from('unchanged'))]=0;
  await assert.rejects(readArchive(corrupt,{entryId:'0'}),/校验失败/);
});
test('archive manifests and children stay under their parent and are omitted from compact state',async t=>{
  const {repo,file}=await fixture(t,[['合同/采购.txt','金额100元']]);
  const opened=await openArchive(repo,file.id);
  assert.equal(repo.list('attachment').length,1);
  assert.equal(opened.archive.totalFiles,1);
  assert.equal(repo.attachmentHeaders()[0].archive,undefined);
  const entry=await archiveEntry(repo,file.id,opened.archive.entries[0].id);
  assert.equal(entry.buffer.toString(),'金额100元');
  assert.equal((await openArchive(repo,file.id)).archive.hash,opened.archive.hash);
});
test('summary rejects invented and unsupported source references',()=>{
  const archive={entries:[{id:'0',status:'completed'},{id:'1',status:'unsupported'}]};
  const valid={overview:'整体说明',groups:[{title:'合同',entryIds:['0']}],findings:[{text:'金额一致',entryIds:['0']}],actions:[]};
  assert.deepEqual(archiveSummary(valid,archive),valid);
  for(const ids of [['invented'],['1'],[]]) assert.throws(()=>archiveSummary({...valid,findings:[{text:'结论',entryIds:ids}]},archive),/引用无效/);
});
test('real archive batch saves individual results, summarizes with checked sources and retries only failures',async t=>{
  const {repo,file}=await fixture(t,[['报价.txt','报价100元'],['合同.txt','合同120元']]);
  let fail=true;const calls=[];
  const server=http.createServer(async(req,res)=>{
    let raw='';for await(const chunk of req)raw+=chunk;
    const request=JSON.parse(raw), context=JSON.parse(request.input[0].content[0].text);
    calls.push(context);
    const text=context.files ? {overview:'采购资料，报价与合同金额需要核对',groups:[{title:'采购',entryIds:context.files.map(x=>x.id)}],
      findings:[{text:'需要核对金额差异',entryIds:context.files.filter(x=>x.status==='completed').map(x=>x.id)}],actions:[]}
      : {text:fail&&context.name.endsWith('合同.txt')?' ':`## 理解\n${context.text}`};
    res.setHeader('Content-Type','text/event-stream');
    res.end(responsesWire({status:'completed',output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify(text)}]}]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const manager=new AttachmentBatch(repo);
  t.after(async()=>{await manager.close();await new Promise(resolve=>server.close(resolve));});
  const config={...DEFAULT_AI,baseURL:`http://127.0.0.1:${server.address().port}/v1`};
  const job=manager.start({messageId:'m',config,attachmentIds:[file.id]});
  await manager.workers.get(job.id).promise;
  let result=repo.get('attachment',file.id);
  assert.equal(repo.get('job',job.id).status,'failed');
  assert.deepEqual(result.archive.entries.map(x=>x.status),['completed','failed']);
  assert.match(result.analysis,/已理解 1\/2/);
  assert.equal(repo.attachmentHeaders()[0].hasPartialAnalysis,true);
  fail=false;calls.length=0;
  manager.start({config},job.id);await manager.workers.get(job.id).promise;
  result=repo.get('attachment',file.id);
  assert.equal(repo.get('job',job.id).status,'completed');
  assert.equal(result.archive.status,'completed');
  assert.equal(repo.attachmentHeaders()[0].hasPartialAnalysis,false);
  assert.equal(calls.filter(x=>!x.files).length,1);
  assert.ok(calls.filter(x=>!x.files)[0].name.endsWith('合同.txt'));
  assert.equal(repo.list('attachment').length,1);
});
test('archive API enforces parent membership, updates search and recovers interrupted progress',async t=>{
  const directory=await mkdtemp(path.join(os.tmpdir(),'boxmail-archive-api-'));
  const token='archive-integration-test-token-0123456789';
  let app=await startServer({directory,token,demo:false});
  t.after(async()=>{await app.close();await rm(directory,{recursive:true,force:true});});
  app.repo.put('account',{id:'a'});
  const file=await saveAttachment(app.repo,'m','资料.zip',await zipOf([['目录/独特文件.txt','test']]),'application/zip');
  app.repo.put('message',{id:'m',accountId:'a',attachmentIds:[file.id],body:'',subject:'资料',sender:'测试',date:'2026-11-10T00:00:00Z'});
  async function get(route,authenticated=true){
    const res=await fetch(`http://127.0.0.1:${app.port}${route}`,{headers:authenticated?{'X-Boxmail-Token':token}:{}});
    return {status:res.status,body:await res.json()};
  }
  assert.equal((await get(`/attachments/${file.id}/archive`,false)).status,403);
  const manifest=await get(`/attachments/${file.id}/archive`);
  assert.equal(manifest.status,200);
  assert.equal((await get(`/attachments/${file.id}/archive/999`)).status,404);
  assert.equal((await get(`/attachments/${file.id}/archive/${manifest.body.entries[0].id}`)).body.name,'独特文件.txt');
  assert.deepEqual(app.repo.searchAttachmentIDs('独特文件','a'),[file.id]);
  app.repo.put('attachment',{...app.repo.get('attachment',file.id),archive:{...manifest.body,status:'running',entries:manifest.body.entries.map(x=>({...x,status:'running'}))}});
  await app.close();
  app=await startServer({directory,token,demo:false});
  const recovered=(await get(`/attachments/${file.id}/archive`)).body;
  assert.equal(recovered.status,'paused');assert.equal(recovered.entries[0].status,'pending');
});

test('pausing a ZIP batch keeps completed children and resumes without repeating their model requests',async t=>{
  const {repo,file}=await fixture(t,[['a.txt','A'],['b.txt','B']]);
  const started=Promise.withResolvers();let block=true;const seen=[];
  const server=http.createServer(async(req,res)=>{
    let raw='';for await(const chunk of req)raw+=chunk;
    const context=JSON.parse(JSON.parse(raw).input[0].content[0].text);seen.push(context);
    if(block&&context.name.endsWith('/b.txt')){started.resolve();return;}
    const result=context.files?{overview:'两个文件',groups:[],findings:[{text:'两份材料',entryIds:context.files.map(x=>x.id)}],actions:[]}:{text:'文件内容已理解'};
    res.setHeader('Content-Type','text/event-stream');
    res.end(responsesWire({status:'completed',output:[{type:'message',role:'assistant',content:[{type:'output_text',text:JSON.stringify(result)}]}]}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const manager=new AttachmentBatch(repo);const config={...DEFAULT_AI,baseURL:`http://127.0.0.1:${server.address().port}/v1`};
  t.after(async()=>{await manager.close();server.closeAllConnections();await new Promise(resolve=>server.close(resolve));});
  const job=manager.start({messageId:'m',config});await started.promise;
  await manager.pause(job.id);
  assert.equal(repo.get('attachment',file.id).archive.status,'paused');
  assert.deepEqual(repo.get('attachment',file.id).archive.entries.map(x=>x.status),['completed','pending']);
  block=false;seen.length=0;
  manager.start({config},job.id);await manager.workers.get(job.id).promise;
  assert.equal(repo.get('job',job.id).status,'completed');
  assert.deepEqual(seen.filter(x=>!x.files).map(x=>x.name.split('/').at(-1)),['b.txt']);
});
test('backup archive validation bounds manifests and rejects altered references',async t=>{
  const {validateArchiveDocument}=await import('../src/archive-summary.js');
  const {repo,file}=await fixture(t,[['目录/文件.txt','test']]);
  const {archive}=await openArchive(repo,file.id);
  assert.doesNotThrow(()=>validateArchiveDocument(archive));
  for(const invalid of [{...archive,hash:'bad'},{...archive,totalFiles:100000},{...archive,entries:[...archive.entries,...archive.entries]}])
    assert.throws(()=>validateArchiveDocument(invalid),/记录无效/);
});

test('invalid manifest paths are omitted and legacy corrupt archive caches cannot block backups', async t => {
  const {createBackup,restoreBackup}=await import('../src/backups.js');
  const {repo,file,directory}=await fixture(t,[['合同\n名.txt','bad'],['x'.repeat(1001)+'.txt','bad'],['good.txt','valid']]);
  // Use a real seeded schema for the end-to-end backup validator.
  repo.put('settings',{id:'settings',ai:{...DEFAULT_AI,model:'test'},preferences:{syncMinutes:5,fontSize:14,signature:'',language:'简体中文',markRead:true,launchAtLogin:false,notifications:false,blockRemoteImages:true,spamFilter:true}});
  repo.put('account',{id:'a',name:'A',email:'a@example.test',username:'',imapHost:'',imapPort:993,imapTLS:true,smtpHost:'',smtpPort:465,smtpTLS:true,isDemo:true});
  repo.put('message',{...repo.get('message','m'),folder:'inbox',senderEmail:'a@example.test',to:'',cc:'',preview:'',category:'未分类',unread:false,starred:false});
  const {archive}=await openArchive(repo,file.id);
  assert.equal(archive.entries.length,1);assert.equal(archive.omitted,2);
  const target=path.join(directory,'valid.zip');await createBackup(repo,target);
  const saved=repo.get('attachment',file.id);
  repo.put('attachment',{...saved,archive:{...archive,entries:[{...archive.entries[0],path:'bad\nname.txt'}]}});
  const legacy=path.join(directory,'legacy.zip');await createBackup(repo,legacy);
  await restoreBackup(repo,legacy,true);
  assert.equal(repo.get('attachment',file.id).archive,undefined);
  await restoreBackup(repo,target,true);
  assert.equal(repo.get('attachment',file.id).archive.entries[0].path,'good.txt');
});

test('legacy GBK names decode to Chinese and known Office extensions take precedence over ZIP MIME',async()=>{
  const {isArchive}=await import('../src/archive-reader.js');
  assert.equal(isArchive({name:'合同.docx',contentType:'application/zip'}),false);
  assert.equal(isArchive({name:'幻灯片.pptx',contentType:'application/zip'}),false);
  const zip=new JSZip();zip.file('合同.txt','content');
  const bytes=await zip.generateAsync({type:'nodebuffer',encodeFileName:name=>name==='合同.txt'?Buffer.from('bacfcdac2e747874','hex'):Buffer.from(name)});
  // Remove Unicode extra-field IDs so this fixture actually exercises the legacy decoder.
  for(let i=0;i<bytes.length-1;i++)if(bytes.readUInt16LE(i)===0x7075)bytes.writeUInt16LE(0xffff,i);
  assert.equal((await readArchive(bytes)).entries[0].path,'合同.txt');
});

test('unchanged ZIP metadata avoids repeated file reads and a changed or missing file invalidates it',async t=>{
  const {writeFile,unlink}=await import('node:fs/promises');
  const {repo,file}=await fixture(t,[['one.txt','one']]);
  await openArchive(repo,file.id);
  assert.equal((await openArchive(repo,file.id)).buffer,undefined);
  assert.ok(Buffer.isBuffer((await openArchive(repo,file.id,{readBytes:true})).buffer));
  await writeFile(file.path,await zipOf([['two.txt','two']]));
  assert.equal((await openArchive(repo,file.id)).archive.entries[0].path,'two.txt');
  await unlink(file.path);
  await assert.rejects(openArchive(repo,file.id),error=>error.status===404&&/丢失/.test(error.message));
});

test('GBK trail byte 0x5c decodes before validation while real backslash paths remain rejected', async () => {
  const encoded = Buffer.from([0x81, 0x5c, 0x2e, 0x74, 0x78, 0x74]);
  const name = new TextDecoder('gbk', { fatal: true }).decode(encoded);
  assert.match(name, /\p{Script=Han}/u);
  const zip = new JSZip(); zip.file(name, '原始字节');
  const bytes = await zip.generateAsync({ type: 'nodebuffer', encodeFileName: value => value === name ? encoded : Buffer.from(value) });
  for (let i = 0; i < bytes.length - 1; i++) if (bytes.readUInt16LE(i) === 0x7075) bytes.writeUInt16LE(0xffff, i);
  const manifest = await readArchive(bytes);
  assert.equal(manifest.entries[0].path, name);
  assert.equal((await readArchive(bytes, { entryId: '0' })).buffer.toString(), '原始字节');
  await assert.rejects(readArchive(await zipOf([['bad\\path.txt', 'unsafe']])), /路径不安全/);
});

test('legacy malformed embedded caches are dropped on migration without losing the original ZIP', async t => {
  const { migrateAttachmentArchives } = await import('../src/attachment-archive-store.js');
  const { repo, file } = await fixture(t, [['good.txt', 'original']]);
  const { archive } = await openArchive(repo, file.id);
  const legacy = { ...repo.get('attachment', file.id), archive: { ...archive,
    entries: [{ ...archive.entries[0], path: 'bad\nname.txt' }] } };
  delete legacy.archiveInfo;
  repo.db.prepare("DELETE FROM records WHERE kind='archive' AND id=?").run(file.id);
  repo.db.prepare("UPDATE records SET data=? WHERE kind='attachment' AND id=?").run(JSON.stringify(legacy), file.id);
  migrateAttachmentArchives(repo);
  const migrated = repo.get('attachment', file.id);
  assert.equal(migrated.archive, undefined); assert.equal(migrated.archiveInfo, undefined);
  assert.equal(migrated.path, file.path);
  const raw = JSON.parse(repo.db.prepare("SELECT data FROM records WHERE kind='attachment' AND id=?").get(file.id).data);
  assert.equal(raw.archive, undefined);
  assert.equal(repo.get('archive', file.id), null);
  const reopened = await openArchive(repo, file.id);
  assert.equal(reopened.archive.entries[0].path, 'good.txt');
});
