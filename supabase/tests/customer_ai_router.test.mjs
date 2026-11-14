import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createModelRouter, freeModelList, openRouterBody, DEFAULT_FREE_MODELS} from '../functions/_shared/customer_ai_router.ts';
import {withinAppScope} from '../functions/_shared/customer_ai_scope.ts';
import {handleAssistant} from '../functions/_shared/customer_ai.ts';
import {handleVisualAgent} from '../functions/_shared/customer_visual_agent.ts';
const [first, second] = DEFAULT_FREE_MODELS;
const body = {systemInstruction:{parts:[{text:'App only.'}]},contents:[{role:'user',parts:[{text:'Find a cleaner'}]}]};
const schema = {type:'OBJECT',properties:{decision:{type:'STRING',enum:['allow','refuse']}},required:['decision']};
const reply = (content='Hello', extra={}) => Response.json({choices:[{finish_reason:'stop',message:{content,...extra}}]});
const meta = (id, extra={}) => ({id,pricing:{prompt:'0',completion:'0'},supported_parameters:['tools','tool_choice','structured_outputs'],architecture:{input_modalities:['text','image']},...extra});
function fixture(options={}) {
 const calls=[], events=[]; let n=0, clock=100;
 const env={GEMINI_API_KEY:'gemini-private',OPENROUTER_API_KEY:'router-private',...options.env};
 const deps={env:n=>env[n],now:()=>clock,log:e=>events.push(e),fetch:async(url,init={})=>{
  const sent=init.body?JSON.parse(init.body):null; calls.push({url,init,body:sent});
  if(url.includes('googleapis'))return options.gemini?options.gemini(sent):new Response('',{status:429});
  if(url.endsWith('/models'))return Response.json({data:options.models??DEFAULT_FREE_MODELS.map(id=>meta(id))});
  return options.router?options.router(sent,n++):reply();
 }};
 return {deps,calls,events,advance:ms=>clock+=ms,generate:createModelRouter(deps,'gemini-test',100000)};
}
test('configuration rejects paid IDs, automatic routers, empty lists and mixed lists',()=>{
 for(const value of ['openrouter/auto','openrouter/free','vendor/paid','vendor/free:free,vendor/paid','', 'vendor/a:free,'])
  assert.throws(()=>freeModelList(value));
 assert.deepEqual(freeModelList('vendor/a:free, vendor/b:free'),['vendor/a:free','vendor/b:free']);
});
test('Gemini quota falls back with zero price caps and no secrets in results/logs',async()=>{
 const f=fixture(); const data=await f.generate(body,0); assert.equal(data.candidates[0].content.parts[0].text,'Hello');
 const call=f.calls.find(x=>x.url.endsWith('/chat/completions'));
 assert.equal(call.body.model,first); assert.equal(call.body.models,undefined);
 assert.deepEqual(call.body.provider.max_price,{prompt:0,completion:0,request:0,image:0});
 assert.equal(call.body.provider.require_parameters,true); assert.equal(call.body.provider.data_collection,'deny');
 assert.equal(call.init.headers.Authorization,'Bearer router-private');
 assert.ok(!JSON.stringify([data,f.events]).includes('private'));
 await f.generate(body,0); assert.equal(f.calls.filter(x=>x.url.includes('googleapis')).length,1);
});
test('fallback works without a Gemini key and rejects paid catalogue prices',async()=>{
 const f=fixture({env:{GEMINI_API_KEY:''},models:[meta(first,{pricing:{prompt:'0',completion:'0',request:'0.1'}}),meta(second)]});
 await f.generate(body,0); assert.equal(f.calls.at(-1).body.model,second);
 assert.ok(!f.calls.some(x=>x.url.includes('googleapis')));
});
test('catalogue outage fails closed without contacting a completion endpoint',async()=>{
 const f=fixture(); const original=f.deps.fetch;
 // Make a fresh router because its injected fetch is the cache boundary.
 const deps={...f.deps,fetch:async(url,init)=>url.endsWith('/models')?new Response('',{status:503}):original(url,init)};
 await assert.rejects(createModelRouter(deps,'gemini-test',100000)(body,0));
 assert.ok(!f.calls.some(x=>x.url.endsWith('/chat/completions')));
});
test('skips missing capabilities for tools, JSON schema and images',async()=>{
 for(const [extra,request] of [
  [{supported_parameters:[]},{...body,tools:[{functionDeclarations:[]}]}],
  [{supported_parameters:['tools']},{...body,generationConfig:{responseSchema:schema}}],
  [{architecture:{input_modalities:['text']}},{...body,contents:[{role:'user',parts:[{inlineData:{mimeType:'image/jpeg',data:'abc'}}]}]}],
 ]) {
  const f=fixture({models:[meta(first,extra),meta(second)]}); await f.generate(request,0);
  assert.equal(f.calls.at(-1).body.model,second);
 }
});
test('shared quota stops the free-model chain, provider quota allows the next model',async()=>{
 for(const provider of [false,true]){
  const f=fixture({router:(_,n)=>n===0?Response.json({error:{metadata:provider?{provider_code:'rate_limit'}:{}}},{status:429,headers:{'retry-after':'60'}}):reply()});
  if(provider) {await f.generate(body,0);assert.equal(f.calls.at(-1).body.model,second);}
  else {await assert.rejects(f.generate(body,0));assert.equal(f.calls.filter(x=>x.url.endsWith('/chat/completions')).length,1);}
 }
});
test('isolate cooldown respects Retry-After across turns and does not sleep',async()=>{
 const f=fixture({router:()=>Response.json({error:{}},{status:429,headers:{'retry-after':'120'}})});
 await assert.rejects(f.generate(body,0)); const count=f.calls.length;
 const another=createModelRouter(f.deps,'gemini-test',100000);
 await assert.rejects(another(body,0)); assert.equal(f.calls.length,count);
});
test('refusals, malformed replies and invalid arguments never trigger model shopping',async()=>{
 for(const output of [reply(null,{refusal:'Cannot help'}),Response.json({choices:[{finish_reason:'length',message:{content:'partial'}}]}),
  Response.json({choices:[{finish_reason:'tool_calls',message:{tool_calls:[{id:'call1',type:'function',function:{name:'search_services',arguments:'bad'}}]}}]})]){
  const f=fixture({router:()=>output});await assert.rejects(f.generate(body,0));
  assert.equal(f.calls.filter(x=>x.url.endsWith('/chat/completions')).length,1);
 }
});
test('converts tool history and images while removing foreign thought signatures',()=>{
 const converted=openRouterBody({...body,contents:[
  {role:'user',parts:[{text:'Help'},{inlineData:{mimeType:'image/png',data:'abc'}}]},
  {role:'model',parts:[{thought:true,text:'private thought'},{functionCall:{name:'search_services',args:{keyword:'cleaner'}},thoughtSignature:'private signature'}]},
  {role:'user',parts:[{functionResponse:{name:'search_services',response:{result:[{name:'Cleaner'}]}}}]},
 ],tools:[{functionDeclarations:[{name:'search_services',parameters:schema}]}],toolConfig:{functionCallingConfig:{mode:'NONE'}},generationConfig:{responseSchema:schema}},first);
 assert.equal(converted.messages[1].content[1].image_url.url,'data:image/png;base64,abc');
 assert.equal(converted.messages[2].tool_calls[0].id,converted.messages[3].tool_call_id);
 assert.equal(converted.messages[3].role,'tool'); assert.equal(converted.tool_choice,'none');
 assert.equal(converted.response_format.json_schema.schema.type,'object');
 assert.ok(!JSON.stringify(converted).includes('private'));
});
test('scope checks use fallback and refuse unrelated input',async()=>{
 const f=fixture({router:()=>reply('{"decision":"refuse"}')});
 assert.equal(await withinAppScope(f.generate,[{role:'user',parts:[{text:'Buy fruit'}]}]),false);
 assert.match(f.calls.at(-1).body.messages[0].content,/scope classifier/);
});
test('a timeout while reading completion bytes switches models before any tool execution',async()=>{
 const f=fixture({router:(_,n)=>n===0?new Response(new ReadableStream({
  start(controller){controller.error(new DOMException('private upstream','TimeoutError'));}
 })):reply('Recovered')});
 const data=await f.generate(body,0);
 assert.equal(data.candidates[0].content.parts[0].text,'Recovered');
 assert.equal(f.calls.at(-1).body.model,second);
 assert.ok(!JSON.stringify(f.events).includes('private upstream'));
});
test('invalid paid configuration is rejected before any request',()=>{
 let called=false;
 assert.throws(()=>createModelRouter({env:n=>n==='OPENROUTER_FREE_MODELS'?'vendor/paid':'key',fetch:async()=>{called=true;}},'gemini-test',Date.now()+10000));
 assert.equal(called,false);
});
test('generation budget and elapsed deadline are bounded',async()=>{
 const f=fixture(); for(let i=0;i<11;i++)await f.generate(body,0);
 await assert.rejects(f.generate(body,0));
 const g=fixture();g.advance(100000); await assert.rejects(g.generate(body,0));assert.equal(g.calls.length,0);
});
const uid='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', cid='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',rid='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
test('assistant switches after a real tool result without replaying the tool or turn',async()=>{
 const calls=[];let google=0;
 const env={SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',GEMINI_API_KEY:'google',OPENROUTER_API_KEY:'router'};
 const fetch=async(url,init={})=>{
  const b=init.body?JSON.parse(init.body):{};calls.push({url,b});
  if(url.endsWith('/auth/v1/user'))return Response.json({id:uid});
  if(url.endsWith('customer_ai_begin_turn'))return Response.json({turn_id:rid,lease:rid,history:[{role:'user',content:'Find a cleaner'}]});
  if(url.endsWith('customer_search_services'))return Response.json([{service_id:rid,provider_id:rid,service_name:'Cleaner',quoted_amount:90}]);
  if(url.endsWith('ai_finish_turn'))return Response.json({content:b.p_content,actions:b.p_actions});
  if(url.includes('googleapis')){
   if(b.generationConfig.responseSchema)return Response.json({candidates:[{content:{parts:[{text:'{"decision":"allow"}'}]}}]});
   if(google++===0)return Response.json({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{keyword:'cleaner'}},thoughtSignature:'secret-thought'}]}}]});
   return new Response('',{status:429});
  }
  if(url.endsWith('/models'))return Response.json({data:DEFAULT_FREE_MODELS.map(id=>meta(id))});
  if(url.endsWith('/chat/completions')){
   if(b.response_format)return reply('{"decision":"allow"}');
   assert.ok(b.messages.some(x=>x.role==='tool'&&x.content.includes('90')));
   assert.ok(!JSON.stringify(b).includes('secret-thought'));return reply('Cleaner costs RM90.');
  }
  throw new Error('Unexpected request');
 };
 const r=await handleAssistant(new Request('https://app.invalid',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify({conversation_id:cid,request_id:rid,message:'Find a cleaner'})}),{env:n=>env[n],fetch});
 assert.equal(r.status,200);assert.equal((await r.json()).message.content,'Cleaner costs RM90.');
 assert.equal(calls.filter(x=>x.url.endsWith('customer_search_services')).length,1);
 assert.equal(calls.filter(x=>x.url.endsWith('customer_ai_begin_turn')).length,1);
});
test('visual agent uses fallback scope guard before generating an off-topic action',async()=>{
 const f=fixture({router:()=>reply('{"decision":"refuse"}')});const original=f.deps.fetch;
 const env={SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'anon'};
 const deps={...f.deps,env:n=>env[n]??f.deps.env(n),fetch:async(url,init)=>{
  if(url.endsWith('/auth/v1/user'))return Response.json({id:uid});
  if(url.includes('/rpc/'))return Response.json({});
  return original(url,init);
 }};
 const r=await handleVisualAgent(new Request('https://app.invalid',{method:'POST',headers:{Authorization:'Bearer user'},body:JSON.stringify({run_id:rid,step:1,goal:'Buy fruit',locale:'en',screen:'explore',local_choices:false,image:'/9j/AAAA',targets:[],history:[]})}),deps);
 assert.equal(r.status,200);assert.equal((await r.json()).action,'handoff');
 assert.equal(f.calls.filter(x=>x.url.endsWith('/chat/completions')).length,1);
});
