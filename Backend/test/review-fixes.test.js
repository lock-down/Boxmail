import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp,rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { startServer } from '../src/server.js';
import { Organizer } from '../src/organizer.js';
import { editCategory,categoryCatalog } from '../src/categories.js';
import { clearTrash } from '../src/mail-trash.js';
import { DEFAULT_AI } from '../src/ai-settings.js';
import { conversationContext,requireFreshConversation,conversationResult } from '../src/conversation-ai.js';
import { draftRevision } from '../src/draft-state.js';

async function fixture(t) {
  const directory=await mkdtemp(path.join(tmpdir(),'boxmail-review-'));
  const token='review-regressions-local-session-token';
  const app=await startServer({directory,token,demo:false});
  t.after(async()=>{await app.close();await rm(directory,{recursive:true,force:true});});
  for(const id of ['a','b'])app.repo.put('account',{id,isDemo:true});
  async function request(route,body) {
    const response=await fetch(`http://127.0.0.1:${app.port}${route}`,{method:body?'POST':'GET',
      headers:{'X-Boxmail-Token':token,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    return {status:response.status,body:await response.json()};
  }
  return {...app,request};
}
const message=(id,changes={})=>({id,accountId:'a',folder:'inbox',body:'正文',html:'<p>正文</p>',sender:'A',senderEmail:'a@example.test',to:'',cc:'',
  date:'2026-11-10',subject:id,category:'工作项目',attachmentIds:[],...changes});

test('draft saves reject cross-account overwrites and omit internal IMAP bindings from responses',async t=>{
  const {repo,request}=await fixture(t);
  repo.put('draft',{id:'draft',accountId:'a',status:'draft',body:'保留原文',to:'',subject:'',cc:'',bcc:'',attachmentIds:[],remotePending:{token:'internal-secret'}});
  assert.equal((await request('/drafts',{id:'draft',accountId:'b',body:'覆盖'})).status,409);
  assert.equal(repo.get('draft','draft').body,'保留原文');
  const response=await request('/drafts/draft');
  assert.equal(response.status,200);assert.equal(response.body.remotePending,undefined);assert.equal(response.body.remoteDraft,undefined);
  assert.equal((await request('/drafts',{id:'bad/id',accountId:'a',body:''})).status,400);
});

test('legacy state and search return bounded headers while detail endpoints retain full bodies',async t=>{
  const {repo,request}=await fixture(t);
  repo.transaction(()=>{for(let i=0;i<230;i++)repo.put('message',message(String(i),{body:'x'.repeat(8192)}));});
  const state=(await request('/state')).body, search=(await request('/search')).body;
  assert.equal(state.messages.length,200);assert.equal(search.messages.length,200);assert.equal(search.nextOffset,200);
  assert.ok(search.messages.every(item=>item.body===''&&item.bodyLoaded===false));
  assert.equal((await request('/messages/0')).body.body.length,8192);
});

test('organizing, clearing trash and category edits avoid full mailbox materialization',async t=>{
  const {repo}=await fixture(t);
  repo.put('message',message('keep'));repo.put('message',message('trash',{folder:'trash'}));
  const list=repo.list.bind(repo);repo.list=(kind,...args)=>{assert.notEqual(kind,'message');return list(kind,...args);};
  const catalog=categoryCatalog(repo), category=catalog.find(item=>item.name==='工作项目');
  editCategory(repo,category.id,{},true);assert.equal(repo.get('message','keep').category,'未分类');
  const manager=new Organizer(repo,{complete:async()=>({items:[{id:'keep',category:'未分类',reason:'test'}]})});
  t.after(()=>manager.close());
  const job=manager.start({accountId:'a',scope:'inbox',config:{...DEFAULT_AI,baseURL:'http://localhost/v1'}});
  await manager.workers.get(job.id).promise;assert.equal(repo.get('job',job.id).status,'needsApproval');
  await clearTrash(repo,'a','',true,{});assert.equal(repo.get('message','trash'),null);assert.ok(repo.get('message','keep'));
});

test('thread graph snapshots are reused and invalidated by new mail and transaction rollback',async t=>{
  const {repo}=await fixture(t);
  repo.put('message',message('root',{messageId:'<root@example.test>'}));
  let scans=0;const headers=repo.messageGraphHeaders.bind(repo);
  repo.messageGraphHeaders=options=>{if(options.accountId)scans++;return headers(options);};
  const first=conversationContext(repo,'root');conversationContext(repo,'root');assert.equal(scans,1);
  const result=conversationResult({subject:'Reply',body:'内容',sourceIds:['root']},first,'conversationReply');
  const job={accountId:'a',messageId:'root',result};
  assert.throws(()=>repo.transaction(()=>{repo.put('message',message('temporary',{references:['<root@example.test>']}));conversationContext(repo,'root');throw new Error('rollback');}));
  assert.doesNotThrow(()=>requireFreshConversation(repo,job));
  repo.put('message',message('new',{references:['<root@example.test>']}));
  assert.throws(()=>requireFreshConversation(repo,job),/会话已有新邮件/);
});

test('saving an unchanged remotely bound draft through HTTP restores synced state', async t => {
  const { repo, request } = await fixture(t);
  repo.put('account', { id: 'a', isDemo: false });
  const first = await request('/drafts', { id: 'saved', accountId: 'a', to: 'you@example.test',
    bcc: 'hidden@example.test', subject: '草稿', body: '正文', attachmentIds: [] });
  assert.equal(first.status, 200);
  const original = repo.get('draft', 'saved');
  const binding = { path: 'Drafts', uid: 1, uidValidity: '10', baseHash: draftRevision(original) };
  repo.put('draft', { ...original, remoteDraft: binding, syncState: 'pending', syncError: 'old warning' });
  const second = await request('/drafts', first.body);
  assert.equal(second.status, 200);
  assert.equal(second.body.syncState, 'synced');
  assert.equal(second.body.syncError, undefined);
  assert.deepEqual(repo.get('draft', 'saved').remoteDraft, binding);
  assert.equal(draftRevision(repo.get('draft', 'saved')), binding.baseHash);
});

test('draft-only sync failures do not label mail threads or search as partial caches', async t => {
  const { repo } = await fixture(t);
  repo.put('message', message('root'));
  repo.put('sync', { id: 'drafts', accountId: 'a', folder: 'drafts', status: 'failed', remaining: 2 });
  assert.equal(conversationContext(repo, 'root').partial, false);
  assert.equal(repo.searchIndex.status().partial, false);
  repo.put('sync', { id: 'inbox', accountId: 'a', folder: 'inbox', hasMore: true, remaining: 2 });
  assert.equal(conversationContext(repo, 'root').partial, true);
  assert.equal(repo.searchIndex.status().partial, true);
});
