import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, rm } from 'node:fs/promises';
import { DatabaseSync } from 'node:sqlite';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { Repository } from '../src/database.js';
import { syncAccount } from '../src/mail.js';
import { buildReplyDraft } from '../src/reply.js';
import { startServer } from '../src/server.js';
import { saveAttachment } from '../src/attachments.js';
import { workbookPreview } from '../src/workbook-preview.js';
import ExcelJS from 'exceljs';

const token = 'boxmail-test-session-0123456789';
const account = { id: 'a1', email: 'me@example.com', username: 'me@example.com', isDemo: false };
const base = { id:'m1', accountId:'a1', sender:'Sender', senderEmail:'a@example.com',
  to:'me@example.com', cc:'', subject:'项目', body:'原文', date:'2026-10-19T00:00:00Z',
  messageId:'<m1@example.com>', attachmentIds:[], folder:'inbox', category:'未分类',
  preview:'原文', unread:true, starred:false, summary:null };
async function fixture(t) {
  const directory = await mkdtemp(path.join(tmpdir(), 'boxmail-daily-'));
  const repo = new Repository(directory);
  t.after(async () => { repo.close(); await rm(directory,{recursive:true,force:true}); });
  return repo;
}
function mailbox(size = 1005) {
  const state = { validity:'10', uids:Array.from({length:size},(_,i)=>i+1), fetched:[], failUID:null,
    failListing:false, flags:new Map() };
  const client = { mailbox:{}, async connect(){}, async logout(){}, close(){},
    async list(){return [{path:'INBOX'}];},
    async getMailboxLock(){this.mailbox={uidValidity:state.validity,exists:state.uids.length};return {release(){}};},
    async *fetch(){
      for (const uid of state.uids) {
        if (state.failListing && uid === 3) throw new Error('connection interrupted');
        yield {uid,size:200,flags:state.flags.get(uid)||new Set(),internalDate:new Date(1792368000000+uid*1000)};
      }
    },
    async fetchOne(uid){
      if(uid===state.failUID) throw new Error('offline');
      state.fetched.push(uid);
      return {source:Buffer.from(`From: A <a@example.com>\r\nTo: me@example.com, B <b@example.com>\r\nReply-To: support@example.com\r\nSubject: Mail ${uid}\r\nMessage-ID: <uid-${uid}@example.com>\r\nReferences: <root@example.com>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n正文 ${uid}`)};
    },
  };
  return {state,client};
}

test('reply all includes original To and Cc, respects Reply-To, excludes self and deduplicates quoted names',()=>{
  const m={...base,to:'"Last, First" <b@example.com>, ME@example.com, alias@example.com',
    cc:'B@example.com, c@example.com, support@example.com',replyTo:'Support <support@example.com>',
    references:['<root@example.com>','<root@example.com>']};
  const draft=buildReplyDraft(m,{...account,aliases:['alias@example.com']},{all:true});
  assert.equal(draft.accountId,'a1');
  assert.equal(draft.to,'support@example.com, b@example.com');
  assert.equal(draft.cc,'c@example.com');
  assert.deepEqual(draft.references,['<root@example.com>','<m1@example.com>']);
  assert.equal(draft.status,'draft');
});
test('replying to own sent mail addresses recipients; forwarding has no reply headers and keeps attachments',()=>{
  const m={...base,senderEmail:'ME@example.com',to:'b@example.com',attachmentIds:['file1'],subject:'Re: 项目'};
  assert.equal(buildReplyDraft(m,account).to,'b@example.com');
  assert.equal(buildReplyDraft(m,account).subject,'Re: 项目');
  const draft=buildReplyDraft(m,account,{forward:true});
  assert.equal(draft.inReplyTo,'');assert.deepEqual(draft.references,[]);
  assert.deepEqual(draft.attachmentIds,['file1']);assert.match(draft.body,/原文/);
});
test('history backfill resumes after interruption and restart without redownloading completed mail',async t=>{
  const repo=await fixture(t), {state,client}=mailbox();
  await syncAccount(repo,{...account},'not-persisted',{clientFactory:()=>client});
  assert.equal(repo.list('message').length,200);
  assert.equal(repo.list('sync')[0].remaining,805);
  state.failUID=755;
  await assert.rejects(syncAccount(repo,{...account},'not-persisted',{clientFactory:()=>client}),/offline/);
  assert.equal(repo.list('message').length,250);
  assert.equal(repo.list('sync')[0].status,'failed');
  repo.close();
  repo.db=new DatabaseSync(path.join(repo.directory,'boxmail.sqlite'));
  state.failUID=null;
  for(let i=0;i<4;i++) await syncAccount(repo,{...account},'not-persisted',{clientFactory:()=>client});
  assert.equal(repo.list('message').length,1005);
  assert.equal(new Set(state.fetched).size,1005);
  assert.equal(state.fetched.length,1005);
  assert.equal(repo.list('sync')[0].hasMore,false);
  assert.equal(repo.list('sync')[0].status,'completed');
  assert.ok(repo.list('message').every(m=>m.replyTo==='support@example.com'));
  assert.equal(JSON.stringify(repo.list('sync')).includes('not-persisted'),false);
});
test('metadata reconciliation updates old flags and deletions, and never prunes on a partial listing',async t=>{
  const repo=await fixture(t), {state,client}=mailbox(5);
  await syncAccount(repo,{...account},'pw',{clientFactory:()=>client});
  state.failListing=true;
  await assert.rejects(syncAccount(repo,{...account},'pw',{clientFactory:()=>client}));
  assert.equal(repo.list('message').length,5);
  state.failListing=false;state.uids=[1,3,4,5];state.flags.set(1,new Set(['\\Seen','\\Flagged']));
  await syncAccount(repo,{...account},'pw',{clientFactory:()=>client});
  assert.equal(repo.list('message').length,4);
  assert.equal(repo.list('message').find(m=>m.uid===1).unread,false);
  assert.equal(repo.list('message').find(m=>m.uid===1).starred,true);
  assert.equal(state.fetched.length,5);
});

test('an interrupted listing after a UIDVALIDITY reset retains cached mail until reconciliation succeeds', async t => {
  const repo = await fixture(t), { state, client } = mailbox(5);
  await syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client });
  const original = repo.list('message');
  state.validity = '11'; state.failListing = true;
  await assert.rejects(syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client }));
  assert.deepEqual(repo.list('message'), original);
  assert.deepEqual(repo.list('recovery'), []);
  state.failListing = false;
  await syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client });
  assert.equal(repo.list('message').length, 5);
  assert.ok(repo.list('message').every(item => item.uidValidity === '11'));
});

test('unchanged synchronization keeps the index clean and later flag changes remain visible', async t => {
  const repo = await fixture(t), { state, client } = mailbox(3);
  await syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client });
  repo.searchIndex.flush();
  await syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client });
  assert.equal(repo.searchIndex.status().pending, 0);
  state.flags.set(1, new Set(['\\Seen', '\\Flagged']));
  await syncAccount(repo, { ...account }, 'pw', { clientFactory: () => client });
  assert.equal(repo.searchIndex.status().pending, 1);
  const updated = repo.list('message').find(item => item.uid === 1);
  assert.equal(updated.unread, false);
  assert.equal(updated.starred, true);
  assert.equal(state.fetched.length, 3);
});
test('UIDVALIDITY reset retains AI results, attachments, drafts and preview job associations',async t=>{
  const repo=await fixture(t), {state,client}=mailbox(1);
  await syncAccount(repo,{...account},'pw',{clientFactory:()=>client});
  const original=repo.list('message')[0];
  const file=await saveAttachment(repo,original.id,'note.txt',Buffer.from('格式之外的检索文本'));
  repo.put('message',{...original,category:'工作项目',summary:{points:['AI结果'],todos:[],keyInfo:[]},attachmentIds:[file.id]});
  repo.put('draft',{id:'draft1',accountId:'a1',sourceMessageId:original.id,status:'draft'});
  repo.put('job',{id:'job1',accountId:'a1',messageId:original.id});
  state.validity='11';
  await syncAccount(repo,{...account},'pw',{clientFactory:()=>client});
  const updated=repo.list('message')[0];
  assert.notEqual(updated.id,original.id);assert.equal(updated.category,'工作项目');
  assert.deepEqual(updated.summary.points,['AI结果']);
  assert.equal(repo.get('attachment',file.id).messageId,updated.id);
  assert.equal(repo.get('draft','draft1').sourceMessageId,updated.id);
  assert.equal(repo.get('job','job1').messageId,updated.id);
});
test('v1 migration makes a consistent backup, retains data, and is not repeated',async t=>{
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-migration-'));
  t.after(()=>rm(directory,{recursive:true,force:true}));
  let old=new DatabaseSync(path.join(directory,'boxmail.sqlite'));
  old.exec('CREATE TABLE records(kind TEXT,id TEXT,data TEXT,PRIMARY KEY(kind,id)); PRAGMA user_version=1;');
  old.prepare('INSERT INTO records VALUES(?,?,?)').run('draft','d1',JSON.stringify({id:'d1',body:'不能丢失的草稿'}));old.close();
  let repo=new Repository(directory);
  assert.equal(repo.get('draft','d1').body,'不能丢失的草稿');
  assert.equal(repo.db.prepare('PRAGMA user_version').get().user_version,2);repo.close();
  const files=await readdir(path.join(directory,'backups'));assert.equal(files.length,1);
  const backup=new DatabaseSync(path.join(directory,'backups',files[0]),{readOnly:true});
  assert.equal(backup.prepare('PRAGMA user_version').get().user_version,1);backup.close();
  repo=new Repository(directory);repo.close();
  assert.equal((await readdir(path.join(directory,'backups'))).length,1);
});
test('future database versions are rejected without resetting their schema version',async t=>{
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-future-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  let db=new DatabaseSync(path.join(directory,'boxmail.sqlite'));db.exec('PRAGMA user_version=77');db.close();
  assert.throws(()=>new Repository(directory),/数据库版本较新/);
  db=new DatabaseSync(path.join(directory,'boxmail.sqlite'));assert.equal(db.prepare('PRAGMA user_version').get().user_version,77);db.close();
});
test('paged HTTP lists are lightweight, body and attachment analysis load on demand, original bytes are preserved',async t=>{
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-page-'));
  const app=await startServer({directory,token,demo:false});
  t.after(async()=>{await app.close();await rm(directory,{recursive:true,force:true});});
  app.repo.put('account',account);
  for(let i=0;i<205;i++) app.repo.put('message',{...base,id:`mail-${String(i).padStart(3,'0')}`,body:'完整正文专用词',html:'<table><tr><td>样式</td></tr></table>'});
  const bytes=Buffer.from('原文件\u0000字节：不能由提取文本重建');
  const file=await saveAttachment(app.repo,'mail-000','原始附件.txt',bytes,'text/plain');
  app.repo.put('attachment',{...file,analysis:'完整AI理解'});
  app.repo.put('message',{...app.repo.get('message','mail-000'),attachmentIds:[file.id]});
  const request=async(route,body)=>{
    const res=await fetch(`http://127.0.0.1:${app.port}${route}`,{method:body?'POST':'GET',headers:{'X-Boxmail-Token':token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
    return {status:res.status,body:await res.json()};
  };
  const state=(await request('/state?compact=1')).body;
  assert.ok(state.messages.every(m=>m.body===''&&m.html===undefined));
  assert.equal(state.attachments[0].text,'');assert.equal(state.attachments[0].analysis,undefined);
  assert.equal(state.attachments[0].hasAnalysis,true);
  assert.equal(state.attachments[0].analysisPreview,'完整AI理解');
  const first=(await request('/messages?accountId=a1&folder=inbox&limit=100')).body;
  const second=(await request(`/messages?accountId=a1&folder=inbox&limit=100&offset=${first.nextOffset}`)).body;
  assert.equal(first.total,205);assert.equal(first.messages.length,100);
  assert.equal(new Set([...first.messages,...second.messages].map(m=>m.id)).size,200);
  assert.equal((await request('/messages?limit=-1')).status,400);
  assert.equal((await request('/messages?q=%E4%B8%93%E7%94%A8%E8%AF%8D')).body.total,205);
  assert.equal((await request('/messages?q=body')).body.total,0);
  assert.match((await request('/messages/mail-000')).body.html,/<table>/);
  assert.equal((await request(`/attachments/${file.id}/metadata`)).body.analysis,'完整AI理解');
  assert.deepEqual((await request('/attachments/search?accountId=a1&q=%E5%AE%8C%E6%95%B4AI%E7%90%86%E8%A7%A3')).body.ids,[file.id]);
  assert.deepEqual((await request('/attachments/search?accountId=other&q=%E5%AE%8C%E6%95%B4AI%E7%90%86%E8%A7%A3')).body.ids,[]);
  const downloaded=(await request(`/attachments/${file.id}`)).body;
  assert.deepEqual(Buffer.from(downloaded.content,'base64'),bytes);
  const draft=(await request('/messages/mail-000/reply-draft',{all:true})).body;
  assert.equal(draft.accountId,'a1');assert.equal(draft.to,'a@example.com');
  assert.deepEqual((await request('/drafts',draft)).body.references,['<m1@example.com>']);
});
test('background sync returns immediately, isolates account failures, and exposes no credentials',async t=>{
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-background-'));
  let finish;
  const app=await startServer({directory,token,demo:false,mailSync:async(repo,a,password,{signal})=>{
    if(a.id==='bad')throw new Error('server unavailable');
    await new Promise(resolve=>{finish=resolve;signal.addEventListener('abort',resolve,{once:true});});
    return {ok:true};
  }});
  t.after(async()=>{finish?.();await app.close();await rm(directory,{recursive:true,force:true});});
  app.repo.put('account',account);app.repo.put('account',{...account,id:'bad'});
  const request=async(route,body)=>{const res=await fetch(`http://127.0.0.1:${app.port}${route}`,{method:body?'POST':'GET',headers:{'X-Boxmail-Token':token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});return {status:res.status,body:await res.json()};};
  assert.equal((await request('/sync',{accountId:'a1',password:'never-log-this',background:true})).body.status,'running');
  assert.equal((await request('/sync',{accountId:'a1',password:'pw',background:true})).status,409);
  await request('/sync',{accountId:'bad',password:'pw',background:true});
  let status=(await request('/sync-status')).body;
  assert.deepEqual(status.runningAccounts,['a1']);assert.equal(status.results.find(r=>r.accountId==='bad').status,'failed');
  assert.equal(JSON.stringify(status).includes('never-log-this'),false);
  finish();
  status=(await request('/sync-status')).body;assert.deepEqual(status.runningAccounts,[]);
});

test('workbook original preview retains merges, colors, dimensions and embedded images without executable content',async()=>{
  const book=new ExcelJS.Workbook(), sheet=book.addWorksheet('排期<script>');
  sheet.columns=[{width:24},{width:32}];sheet.mergeCells('A1:B1');sheet.getRow(1).height=32;
  const cell=sheet.getCell('A1');cell.value='<script>alert(1)</script>';cell.font={bold:true,color:{argb:'FFFFFFFF'},size:18};
  cell.fill={type:'pattern',pattern:'solid',fgColor:{argb:'FF3265AB'}};
  sheet.getCell('A2').value=1.25;sheet.getCell('A2').numFmt='General';
  const image=book.addImage({buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jmQAAAABJRU5ErkJggg==','base64'),extension:'png'});
  sheet.addImage(image,'A4:B8');
  const html=await workbookPreview(Buffer.from(await book.xlsx.writeBuffer()));
  assert.match(html,/colspan="2"/);assert.match(html,/#3265AB/);assert.match(html,/data:image\/png;base64,/);
  assert.match(html,/工作簿内嵌图片/);assert.match(html,/1\.25/);
  assert.match(html,/&lt;script&gt;alert\(1\)&lt;\/script&gt;/);assert.doesNotMatch(html,/<script>/);
  assert.match(html,/default-src 'none'/);
});

test('stale UID mutations are discarded before reaching the server and oversized mail remains visible',async t=>{
  const repo=await fixture(t), {state,client}=mailbox(1);
  let flagWrites=0;client.messageFlagsAdd=async()=>{flagWrites++;};
  repo.put('mutation',{id:'stale',accountId:'a1',path:'INBOX',uid:1,uidValidity:'old',flag:'\\Seen',value:true});
  client.fetch=async function*(){yield {uid:1,size:26*1024*1024,flags:new Set(),internalDate:new Date(),envelope:{subject:'超限原件',messageId:'<large@example.com>',from:[{address:'a@example.com'}]}};};
  await syncAccount(repo,{...account},'pw',{clientFactory:()=>client});
  assert.equal(flagWrites,0);assert.equal(repo.list('mutation').length,0);
  assert.equal(state.fetched.length,0);assert.equal(repo.list('message')[0].subject,'超限原件');
  assert.match(repo.list('message')[0].body,/25 MB/);assert.equal(repo.list('message')[0].oversized,true);
});
test('server restart exposes interrupted synchronization as paused with its checkpoint intact',async t=>{
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-sync-restart-'));
  let repo=new Repository(directory);repo.put('sync',{id:'checkpoint',accountId:'a1',folder:'inbox',status:'running',downloaded:250,total:1005,remaining:755,hasMore:true});repo.close();
  const app=await startServer({directory,token,demo:false});
  t.after(async()=>{await app.close();await rm(directory,{recursive:true,force:true});});
  const res=await fetch(`http://127.0.0.1:${app.port}/sync-status`,{headers:{'X-Boxmail-Token':token}});
  const state=await res.json();assert.equal(state.folders[0].status,'paused');assert.equal(state.folders[0].downloaded,250);
  assert.deepEqual(state.runningAccounts,[]);
});
