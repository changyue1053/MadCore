// Exact production ETS with import-only remapping. No Huawei runtime/drain proof.
import { mkdtemp, readFile, writeFile, copyFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
const dir = await mkdtemp(join(tmpdir(), 'madcore-copied-driver-'));
const drivers = [];
try {
  let source = await readFile(new URL('../harmony/experimental/copied-http/CopiedHttpDriver.ets', import.meta.url), 'utf8');
  for (const name of ['libmadcore_copied_bridge.so', '@kit.RemoteCommunicationKit', '@kit.BasicServicesKit', '@kit.ArkTS']) {
    assert.ok(source.includes(`'${name}'`)); source = source.replace(`'${name}'`, "'./fake.ts'");
  }
  source = source.replace("'./HttpPolicy'", "'./HttpPolicy.ts'");
  await writeFile(join(dir, 'Driver.ts'), source);
  await copyFile(new URL('../harmony/madcore/HttpPolicy.ets', import.meta.url), join(dir, 'HttpPolicy.ts'));
  await writeFile(join(dir, 'fake.ts'), `
export class CopiedRequest {}
export class BusinessError extends Error { code:number=0 }
export const log:any = { sessions:new Map(), fetches:[], mode:'pending', events:[] };
let sequence=1;
export default {
 open(){const s=sequence++;log.sessions.set(s,new Map());return s},
 close(s:number){log.events.push('close:'+s);log.sessions.delete(s);return 0},
 state(s:number,o:number){return log.sessions.get(s)?.get(o)?.state ?? -2},
 nextRequest(s:number){for(const op of log.sessions.get(s)?.values()??[])if(op.state===1&&!op.sent){op.sent=true;return op.wire}return null},
 fail(s:number,o:number,e:number){const op=log.sessions.get(s)?.get(o);if(!op)return -2;if(op.state!==1)return 0;op.state=3;op.error=e;return 1},
 complete(s:number,o:number,status:number,headers:string,body:ArrayBuffer){const op=log.sessions.get(s)?.get(o);if(!op)return -2;if(op.state!==1)return 0;op.state=2;op.result={status,headers,body:body.slice(0)};return 1},
};
export const util={TextEncoder:class {encodeInto(s:string){return new TextEncoder().encode(s)}}};
class Request { destination:any;constructor(public url:string,public method:string,public headers:any,public content:any){} }
class Session {
 constructor(public config:any){}
 fetch(request:any){if(log.mode==='syncThrow')throw Error('private');let resolve:any,reject:any;const promise=new Promise((a,b)=>{resolve=a;reject=b});log.fetches.push({request,resolve,reject,session:this});return promise}
 cancel(){log.events.push('cancel')}
 close(){log.events.push('platformClose')}
}
export const rcp={Request,createSession(config:any){return new Session(config)}};
`);
  const { CopiedHttpDriver } = await import(pathToFileURL(join(dir, 'Driver.ts')));
  const { log } = await import(pathToFileURL(join(dir, 'fake.ts')));
  const make = () => { const d = new CopiedHttpDriver(); drivers.push(d); return d; };
  let next = 1;
  const queue = (d, overrides = {}) => {
    const operation = next++;
    const op = { state: 1, sent: false, wire: { operation, method: 1, url: 'https://example.test/a', headers: '{}', body: new ArrayBuffer(0), maxResponse: 8, connectTimeout: 100, readTimeout: 100, callTimeout: 10000, allowInsecure: 0, ...overrides } };
    log.sessions.get(d.session).set(operation, op); return op;
  };
  const flush = async () => { for (let i=0;i<8;i++) await Promise.resolve(); };
  const d = make();
  const success = queue(d); d.pump(); const f = log.fetches.at(-1);
  assert.equal(f.session.config.requestConfiguration.transfer.autoRedirect, false);
  assert.equal(f.session.config.requestConfiguration.security, undefined);
  f.request.destination(new Uint8Array([1,0,3]).buffer);
  f.resolve({statusCode:201, headers:{'set-cookie':['a=1','b=2'],'X-Test':'a,b'}}); await flush();
  assert.equal(success.state,2); assert.deepEqual(JSON.parse(success.result.headers), {'set-cookie':['a=1','b=2'],'X-Test':['a,b']});
  assert.deepEqual([...new Uint8Array(success.result.body)],[1,0,3]); assert.equal(d.active.size,0);
  const cancelled=queue(d);d.pump();const late=log.fetches.at(-1);cancelled.state=4;d.pump();
  late.request.destination(new Uint8Array(30).buffer);late.resolve({statusCode:200,headers:{}});await flush();
  assert.equal(cancelled.state,4);assert.equal(cancelled.result,undefined);assert.equal(d.active.size,0);
  const malformedResponse=queue(d);d.pump();log.fetches.at(-1).resolve({statusCode:200,headers:{'bad name':'x'}});await flush();assert.equal(malformedResponse.state,3);
  for(const headers of ['{', 'null', '[]', '{"X-Test":123}']) {
    const prior=log.fetches.length,op=queue(d,{headers});d.pump();assert.equal(op.state,3, 'malformed request header must fail: '+headers);assert.equal(log.fetches.length,prior);
  }
  log.mode='syncThrow';
  for(let i=0;i<20;i++){const op=queue(d);d.pump();assert.equal(op.state,3);assert.equal(d.active.size,0,'sync throw must release active entry');}
  log.mode='pending';
  const closing=queue(d);d.pump();const old=log.fetches.at(-1);const start=log.events.length;d.close();d.close();
  assert.equal(log.events[start],'close:'+d.session);old.request.destination(new Uint8Array([1]).buffer);old.resolve({statusCode:200,headers:{}});await flush();assert.equal(closing.result,undefined);assert.equal(d.active.size,0);
  // Eight unsettled fetches retain global quota even after logical timeout/close.
  const stuck=make();const unsettled=[];
  for(let i=0;i<8;i++){const op=queue(stuck,{callTimeout:5});stuck.pump();unsettled.push({op,fetch:log.fetches.at(-1)});}
  await new Promise(resolve=>setTimeout(resolve,20));
  for(const {op} of unsettled){assert.equal(op.state,3);assert.equal(op.error,2);}
  stuck.close();const fresh=make();const before=log.fetches.length,blocked=queue(fresh);fresh.pump();
  assert.equal(blocked.state,3);assert.equal(log.fetches.length,before,'close/timeout must not release unsettled slots');
  unsettled[0].fetch.resolve({statusCode:200,headers:{}});await flush();
  const admitted=queue(fresh);fresh.pump();assert.equal(log.fetches.length,before+1);log.fetches.at(-1).resolve({statusCode:200,headers:{}});await flush();assert.equal(admitted.state,2);
  // The seven remaining slots stay reserved until each actual fake promise settles.
  for (const item of unsettled.slice(1)) item.fetch.resolve({statusCode:200,headers:{}});
  await flush();
  const recovered = [];
  for (let i=0;i<8;i++) recovered.push(queue(fresh));
  const recoveryStart = log.fetches.length;
  fresh.pump(); // all eight dispatch before yielding to any promise handler
  assert.equal(log.fetches.length,recoveryStart+8,'all eight application slots must recover');
  assert.equal(fresh.active.size,8);
  for (const {op} of unsettled) assert.equal(log.sessions.get(fresh.session).has(op.wire.operation),false);
  for (const fetch of log.fetches.slice(recoveryStart)) {
    fetch.request.destination(new Uint8Array([7]).buffer);
    fetch.resolve({statusCode:200,headers:{}});
  }
  await flush();
  for (const op of recovered) {
    assert.equal(op.state,2);
    assert.deepEqual([...new Uint8Array(op.result.body)],[7]);
  }
  assert.equal(fresh.active.size,0);
  // Another complete batch proves all eight finally paths released their quota.
  const again=[];
  for(let i=0;i<8;i++)again.push(queue(fresh));
  const againStart=log.fetches.length;fresh.pump();
  assert.equal(log.fetches.length,againStart+8);
  for(const fetch of log.fetches.slice(againStart))fetch.resolve({statusCode:200,headers:{}});
  await flush();assert.ok(again.every(op=>op.state===2));assert.equal(fresh.active.size,0);
  fresh.close();
  console.log('Copied HTTP exact-source host mocks passed; not Harmony execution or drain evidence');
} finally {
  for(const driver of drivers)driver.close();
  await rm(dir,{recursive:true,force:true});
}
