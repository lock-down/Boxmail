// Run from the repository with: node --expose-gc script/benchmark-workspace-lists.mjs
import {mkdtemp,rm} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';
import {Repository} from '../Backend/src/database.js';
import {organizationPage} from '../Backend/src/organization-page.js';
const directory=await mkdtemp(path.join(os.tmpdir(),'boxmail-workspace-benchmark-'));
const repo=new Repository(directory);
const samples=[];
try {
 repo.searchIndex.close();repo.searchIndex.schedule=()=>{};
 repo.put('account',{id:'a'});
 repo.transaction(()=>{
  for(let i=0;i<12000;i++){
   repo.put('message',{id:`m${String(i).padStart(5,'0')}`,accountId:'a',folder:'inbox',sender:'Synthetic',senderEmail:'sender@example.test',to:'',cc:'',subject:`Message ${i}`,date:'2026-11-11',category:i%2?'工作项目':'未分类',body:'正文'.repeat(4000),html:'<p>body</p>',unread:false,starred:false,attachmentIds:[]});
   if(i<1105)repo.put('attachment',{id:`f${String(i).padStart(5,'0')}`,messageId:`m${String(i).padStart(5,'0')}`,name:`Attachment ${i}.txt`,size:100,contentType:'text/plain',path:'/synthetic/file',text:'提取'.repeat(4000),analysis:'分析'.repeat(4000),parseError:'',date:'2026-11-11'});
  }
 });
 const get=repo.get.bind(repo),list=repo.list.bind(repo);let reads=0,scans=0;
 repo.get=(kind,...args)=>{if(['message','attachment'].includes(kind))reads++;return get(kind,...args);};
 repo.list=(kind,...args)=>{if(['message','attachment'].includes(kind))scans++;return list(kind,...args);};
 for(const [name,operation] of [
  ['organization-first',()=>organizationPage(repo,{accountId:'a'})],
  ['organization-filtered-last',()=>organizationPage(repo,{accountId:'a',category:'工作项目',offset:5950})],
  ['attachments-first',()=>repo.attachmentPage({accountId:'a',sort:'name'})],
  ['attachments-last',()=>repo.attachmentPage({accountId:'a',sort:'name',offset:1100})],
 ]) {
  const runs=[];
  for(let i=0;i<7;i++){
   global.gc();reads=0;scans=0;
   const before=process.memoryUsage(), cpu=process.cpuUsage(),start=performance.now();
   const result=operation();
   const elapsedMs=performance.now()-start, cpuDelta=process.cpuUsage(cpu),after=process.memoryUsage();
   runs.push({elapsedMs,cpuMs:(cpuDelta.user+cpuDelta.system)/1000,heapDelta:after.heapUsed-before.heapUsed,rows:result.items.length,total:result.total,responseBytes:Buffer.byteLength(JSON.stringify(result)),reads,scans});
  }
  samples.push({scenario:name,samples:runs});
 }
 console.log(JSON.stringify({node:process.version,messages:12000,attachments:1105,pageSize:50,iterations:7,units:{elapsedMs:'ms, setup and GC excluded',cpuMs:'user + system ms',heapDelta:'bytes, post-operation minus post-GC heap, not peak'},note:'Local SQL calls and serialization size. Does not measure SwiftUI drawing, startup or total App memory. Existing lightweight startup header caches remain in use.',results:samples},null,2));
} finally {repo.close();await rm(directory,{recursive:true,force:true});}
