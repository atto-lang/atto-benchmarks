// Shared-runner diagnostic only: no official SharkBench score.
import http from 'node:http';
import fs from 'node:fs';
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
const [upstream,variant,roundText] = process.argv.slice(2);
assert(upstream && ['boxed','native','rust'].includes(variant));
const round=Number(roundText); assert(Number.isInteger(round)&&round>0);
const elements=JSON.parse(fs.readFileSync(upstream+'/element.json','utf8'));
const shells=JSON.parse(fs.readFileSync(upstream+'/shells.json','utf8'));
const symbols=Object.keys(elements).filter(s=>Object.hasOwn(shells,s)).sort();
assert(symbols.length>100);
const agent=new http.Agent({keepAlive:true,maxSockets:32});
function get(port,path,expectedType) {
  return new Promise((resolve,reject)=>{
    const req=http.get({hostname:'127.0.0.1',port,path,agent},res=>{
      if(res.statusCode!==200 || (expectedType && !/^application\/json(?:;|$)/i.test(res.headers['content-type']??''))) {res.resume();reject(Error('status/content-type '+res.statusCode+' '+path));return;}
      let n=0;const chunks=[];
      res.on('data',b=>{n+=b.length;if(n>16384){req.destroy(Error('body too large'));return;}chunks.push(b);});
      res.on('error',reject);
      res.on('end',()=>{try{resolve(new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks)));}catch(e){reject(e);}});
    });
    req.setTimeout(10000,()=>req.destroy(Error('timeout '+path)));
    req.on('error',reject);
  });
}
const plan=Array.from({length:symbols.length*2},(_,i)=>({symbol:symbols[Math.floor(i/2)],route:i%2?'shells':'element'}));
async function request(i){
  const {symbol,route}=plan[i%plan.length];
  const expected=route==='element'?elements[symbol]:{shells:shells[symbol]};
  const start=performance.now();
  const raw=await get(5001,'/api/v1/periodic-table/'+route+'?symbol='+encodeURIComponent(symbol),true);
  const duration=performance.now()-start;
  assert.deepEqual(JSON.parse(raw),expected);
  return duration;
}
async function phase(count){
  await get(5002,'/reset',false);
  let next=0;const samples=[];
  const start=performance.now();
  await Promise.all(Array.from({length:32},async()=>{while(true){const i=next++;if(i>=count)return;samples.push(await request(i));}}));
  const elapsed=performance.now()-start;
  const fetched=Number(await get(5002,'/reset',false));
  assert.equal(samples.length,count);assert.equal(fetched,count,'upstream fetch count');
  samples.sort((a,b)=>a-b);
  const pct=p=>samples[Math.ceil(p*count)-1];
  return {requests:count,upstream_fetches:fetched,elapsed_ms:elapsed,requests_per_second:count*1000/elapsed,p50_ms:pct(.5),p99_ms:pct(.99)};
}
try{
  const warmup=await phase(plan.length*2);
  const measured=await phase(plan.length*8);
  console.log(JSON.stringify({scope:'shared-runner diagnostic, not official score',variant,round,symbols:symbols.length,concurrency:32,warmup,measured}));
}finally{agent.destroy();}
