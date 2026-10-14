import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleAssistant} from '../functions/_shared/customer_ai.ts';
const uid='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',cid='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',rid='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const req=(body={},auth=true)=>new Request('https://app.invalid',{method:'POST',headers:auth?{Authorization:'Bearer customer'}:{},body:JSON.stringify({conversation_id:cid,request_id:rid,message:'Find a cleaner',...body})});
const response=(data,status=200)=>new Response(JSON.stringify(data),{status});
function fixture(options={}){
 const calls=[];let model=0;
 const env={SUPABASE_URL:'https://db.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',GEMINI_API_KEY:'private-test-key',...options.env};
 return {calls,deps:{env:n=>env[n],sleep:async()=>{},fetch:async(url,init={})=>{
  const body=init.body?JSON.parse(init.body):null;calls.push({url,init,body});
  if(url.endsWith('/auth/v1/user'))return response({id:uid},options.authStatus??200);
  if(url.includes('generativelanguage'))return options.gemini?options.gemini(model++,body,url):response({candidates:[{content:{role:'model',parts:[{text:'How can I help you choose?'}]}}]});
  if(url.endsWith('customer_ai_begin_turn'))return options.begin?options.begin():response({turn_id:rid,lease:rid,history:[{role:'user',content:'Find a cleaner'}]});
  if(url.endsWith('ai_finish_turn'))return response({id:2,role:'assistant',content:body.p_content,actions:body.p_actions});
  if(url.endsWith('ai_fail_turn'))return response(null);
  if(url.endsWith('customer_search_services'))return response(options.catalogue??[{service_id:rid,provider_id:rid,business_name:'Local Provider',service_name:'Cleaner',quoted_amount:90}]);
  if(url.includes('/saved_addresses?'))return response(options.addresses??[{address_id:rid,label:'Home',city:'Kuala Lumpur',is_default:true,coordinates:'3,101'}]);
  if(url.endsWith('customer_booking_slots'))return response(options.slots??[{scheduled_time:'14:00:00'}]);
  if(url.endsWith('customer_provider_coverage'))return response([{provider_id:rid,covers_selected:false,distance_km:20,service_radius_km:10}]);
  if(url.endsWith('customer_ai_stage_action'))return response({id:rid,kind:'booking',title:'Request booking',summary:'Cleaner RM90',payload:{quote:90},status:'pending'});
  if(url.endsWith('customer_ai_delete_conversation'))return response([`${uid}/${cid}/${rid}.jpg`]);
  if(url.includes('/storage/v1/object/'))return response({deleted:true});
  throw new Error(`Unexpected URL: ${url}`);
 }} };
}
test('authenticated Gemini reply is persisted server-side without leaking key',async()=>{
 const f=fixture();const r=await handleAssistant(req(),f.deps);assert.equal(r.status,200);const data=await r.json();assert.equal(data.message.content,'How can I help you choose?');assert.ok(!JSON.stringify(data).includes('private-test-key'));
 assert.equal(f.calls.find(c=>c.url.endsWith('customer_ai_begin_turn')).init.headers.Authorization,'Bearer customer');assert.equal(f.calls.find(c=>c.url.endsWith('ai_finish_turn')).init.headers.Authorization,'Bearer service');
});
test('missing and invalid sessions never call Gemini',async()=>{for(const auth of [false,true]){const f=fixture({authStatus:401});assert.equal((await handleAssistant(req({},auth),f.deps)).status,401);assert.ok(!f.calls.some(c=>c.url.includes('generativelanguage')));}});
test('missing Gemini key has actionable setup error and no persisted turn',async()=>{const f=fixture({env:{GEMINI_API_KEY:''}});const r=await handleAssistant(req(),f.deps);assert.equal(r.status,503);assert.match((await r.json()).error,/GEMINI_API_KEY/);assert.ok(!f.calls.some(c=>c.url.endsWith('customer_ai_begin_turn')));});
test('reject client credentials/tool requests/oversized text',async()=>{for(const extra of [{tools:['pay']},{service_role:'x'},{message:'a'.repeat(4001)},{mode:'admin'}]){const f=fixture();assert.equal((await handleAssistant(req(extra),f.deps)).status,400);assert.ok(!f.calls.some(c=>c.url.includes('generativelanguage')));}});
test('reject foreign image path before Gemini',async()=>{const f=fixture();assert.equal((await handleAssistant(req({image_path:`${rid}/${cid}/${rid}.jpg`}),f.deps)).status,403);});
test('completed retry returns stored result and does not spend another model call',async()=>{const f=fixture({begin:()=>response({replay:true,message:{id:2,content:'Already saved'}})});const r=await handleAssistant(req(),f.deps);assert.equal((await r.json()).message.content,'Already saved');assert.ok(!f.calls.some(c=>c.url.includes('generativelanguage')));});
test('function calling uses real app RPC and retains thought signature',async()=>{
 const f=fixture({gemini:(n,b)=>{
  if(n===0)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{keyword:'cleaning'}},thoughtSignature:'signature'}]}}]});
  assert.equal(b.contents[1].parts[0].thoughtSignature,'signature');assert.equal(b.contents[2].parts[0].functionResponse.response.result.services[0].quoted_amount,90);
  return response({candidates:[{content:{role:'model',parts:[{text:'Cleaner costs RM90.'}]}}]});
 }});assert.equal((await handleAssistant(req(),f.deps)).status,200);assert.equal(f.calls.find(c=>c.url.endsWith('customer_search_services')).init.headers.Authorization,'Bearer customer');
});
test('unsupported model tool cannot execute arbitrary RPC or payment',async()=>{
 const f=fixture({gemini:(n)=>response({candidates:[{content:{role:'model',parts:n===0?[{functionCall:{name:'gateway_record_payment',args:{}}}]:[{text:'That action is not available.'}]}}]})});assert.equal((await handleAssistant(req(),f.deps)).status,200);assert.ok(!f.calls.some(c=>c.url.endsWith('gateway_record_payment')));
});
test('booking tool stages a card and never calls confirmation or booking writer',async()=>{
 const f=fixture({gemini:(n)=>response({candidates:[{content:{role:'model',parts:n===0?[{functionCall:{name:'prepare_booking',args:{service_id:rid,address_id:rid,date:'2026-11-01',time:'09:00'}}}]:[{text:'Review the booking card.'}]}}]})});const r=await handleAssistant(req(),f.deps);assert.equal((await r.json()).message.actions[0].kind,'booking');assert.ok(!f.calls.some(c=>/confirm_action|create_booking/.test(c.url)));
});
test('Gemini quota error fails lease without false assistant success',async()=>{const f=fixture({gemini:()=>response({},429)});assert.equal((await handleAssistant(req(),f.deps)).status,429);assert.ok(f.calls.some(c=>c.url.endsWith('ai_fail_turn')));assert.ok(!f.calls.some(c=>c.url.endsWith('ai_finish_turn')));});
test('delete uses owned RPC output for storage cleanup without requiring Gemini key',async()=>{const f=fixture({env:{GEMINI_API_KEY:''}});const request=new Request('https://app.invalid',{method:'POST',headers:{Authorization:'Bearer customer'},body:JSON.stringify({operation:'delete',conversation_id:cid})});assert.equal((await handleAssistant(request,f.deps)).status,200);const cleanup=f.calls.find(c=>c.url.includes('/storage/v1/object/'));assert.deepEqual(cleanup.body.prefixes,[`${uid}/${cid}/${rid}.jpg`]);assert.ok(!f.calls.some(c=>c.url.includes('generativelanguage')));});
test('oversized chunked body is rejected',async()=>{const f=fixture();const r=new Request('https://app.invalid',{method:'POST',headers:{Authorization:'Bearer customer'},body:'x'.repeat(15000)});assert.equal((await handleAssistant(r,f.deps)).status,413);});


test('working default uses a bounded minimal-thinking Gemini request',async()=>{
 const f=fixture();await handleAssistant(req(),f.deps);
 const call=f.calls.find(c=>c.url.includes('generativelanguage'));
 assert.match(call.url,/gemini-3\.1-flash-lite:generateContent/);
 assert.equal(call.body.generationConfig.thinkingConfig.thinkingLevel,'MINIMAL');
 assert.equal(call.body.generationConfig.temperature,undefined);
});
test('timeout releases lease and gives retry guidance without leaking diagnostics',async()=>{
 const events=[];
 const f=fixture({gemini:()=>{throw new DOMException('sensitive upstream details','TimeoutError');}});
 f.deps.log=e=>events.push(e);
 const r=await handleAssistant(req(),f.deps);assert.equal(r.status,503);
 const data=await r.json();assert.match(data.error,/temporarily busy.*retry/);
 assert.ok(!JSON.stringify(data).includes('sensitive'));
 assert.equal(events.filter(e=>e.event==='customer_assistant_transport').length,3);
 assert.deepEqual(events.at(-1),{event:'customer_assistant_failure',stage:'gemini',error:'Error',status:503});
 assert.ok(!JSON.stringify(events).includes('sensitive'));
 assert.ok(f.calls.some(c=>c.url.endsWith('ai_fail_turn')));
});
test('final model round requests an answer instead of another tool loop',async()=>{
 const f=fixture({gemini:(n,b)=>{
  if(n===4){assert.equal(b.toolConfig.functionCallingConfig.mode,'NONE');return response({candidates:[{content:{role:'model',parts:[{text:'No matching provider was found.'}]}}]});}
  return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{keyword:'plumbing'}}}]}}]});
 }});
 assert.equal((await (await handleAssistant(req(),f.deps)).json()).message.content,'No matching provider was found.');
});

test('owned conversation photo path passes input validation',async()=>{
 const f=fixture();const r=await handleAssistant(req({image_path:`${uid}/${cid}/${rid}.jpg`}),f.deps);assert.equal(r.status,200);
});

test('503 retries generation within one turn and saves exactly one reply',async()=>{
 const delays=[],events=[];
 const f=fixture({gemini:n=>n<1?response({error:{status:'UNAVAILABLE',message:'private-test-key customer text'}},503):response({candidates:[{content:{role:'model',parts:[{text:'Recovered'}]}}]})});
 f.deps.sleep=async ms=>delays.push(ms);f.deps.log=e=>events.push(e);
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
 assert.equal(f.calls.filter(c=>c.url.endsWith('customer_ai_begin_turn')).length,1);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_finish_turn')).length,1);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,2);
 assert.ok(delays[0]>=500&&delays[0]<750);
 assert.equal(events[0].http_status,503);assert.equal(events[0].upstream_status,'UNAVAILABLE');
 assert.ok(!JSON.stringify(events).includes('private-test-key'));assert.ok(!JSON.stringify(events).includes('customer text'));
});

test('fallback recovers initial congestion and stays selected for tool results',async()=>{
 const f=fixture({gemini:(n,b,url)=>{
  if(n<2){assert.match(url,/gemini-3\.1-flash-lite:/);return response({},503);}
  assert.match(url,/gemini-3\.6-flash:/);
  return response({candidates:[{content:{role:'model',parts:n===2?[{functionCall:{name:'search_services',args:{keyword:'plumbing'}},thoughtSignature:'fallback-signature'}]:[{text:'Found the service.'}]}}]});
 }});
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
 assert.equal(f.calls.filter(c=>c.url.endsWith('customer_search_services')).length,1);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_finish_turn')).length,1);
});

test('tool continuation retries keep model and signatures without replaying tools',async()=>{
 const f=fixture({gemini:(n,b,url)=>{
  assert.match(url,/gemini-3\.1-flash-lite:/);
  if(n===0)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{}},thoughtSignature:'keep-me'}]}}]});
  assert.equal(b.contents[1].parts[0].thoughtSignature,'keep-me');
  return n<3?response({},503):response({candidates:[{content:{role:'model',parts:[{text:'Recovered after search'}]}}]});
 }});
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
 assert.equal(f.calls.filter(c=>c.url.endsWith('customer_search_services')).length,1);
});

test('credential, quota and invalid configuration failures are not retried',async()=>{
 for(const status of [400,401,403,404,429]){
  const f=fixture({gemini:()=>response({error:{status:'PERMISSION_DENIED',message:'secret details'}},status)});
  const r=await handleAssistant(req(),f.deps);assert.equal(r.status,status===429?429:503);
  assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,1);
  assert.ok(!JSON.stringify(await r.json()).includes('secret details'));
  assert.equal(f.calls.filter(c=>c.url.endsWith('ai_fail_turn')).length,1);
 }
});

test('exhausted retries fail the lease without a fake answer',async()=>{
 const f=fixture({gemini:()=>new Response('temporarily down',{status:502})});
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,3);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_finish_turn')).length,0);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_fail_turn')).length,1);
});

test('generation budget stops retries in time to release lease',async()=>{
 let clock=0;const f=fixture({gemini:()=>{clock+=79000;return response({},503);}});f.deps.now=()=>clock;
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,1);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_fail_turn')).length,1);
});

test('Retry-After is respected but never exceeds the turn budget',async()=>{
 const delays=[];const f=fixture({gemini:()=>new Response('{}',{status:503,headers:{'retry-after':'120'}})});
 f.deps.sleep=async ms=>delays.push(ms);
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,1);assert.deepEqual(delays,[]);
});

test('fallback can be disabled and custom models do not get unsupported thinking parameters',async()=>{
 const f=fixture({env:{GEMINI_MODEL:'gemini-3.7-flash',GEMINI_FALLBACK_MODEL:''},gemini:(n,b,url)=>{
  assert.match(url,/gemini-3\.7-flash:/);assert.equal(b.generationConfig.thinkingConfig,undefined);
  return response({},503);
 }});
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,3);
});

test('network interruption can recover without exposing transport details',async()=>{
 const f=fixture({gemini:n=>{if(!n)throw new TypeError('private networking detail');return response({candidates:[{content:{role:'model',parts:[{text:'Recovered'}]}}]});}});
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
});

test('the total generation request cap applies across multiple tool rounds',async()=>{
 const f=fixture({gemini:n=>n%2===0?response({},503):response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{}}}]}}]})});
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.equal(f.calls.filter(c=>c.url.includes('generativelanguage')).length,7);
 assert.equal(f.calls.filter(c=>c.url.endsWith('customer_search_services')).length,3);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_finish_turn')).length,0);
 assert.equal(f.calls.filter(c=>c.url.endsWith('ai_fail_turn')).length,1);
});

test('invalid fallback configuration is rejected before persisting or generating',async()=>{
 const f=fixture({env:{GEMINI_FALLBACK_MODEL:'https://untrusted.invalid'}});
 assert.equal((await handleAssistant(req(),f.deps)).status,503);
 assert.ok(!f.calls.some(c=>c.url.endsWith('customer_ai_begin_turn')||c.url.includes('generativelanguage')));
});

test('assist refreshes all service facts before reading stale assistant claims',async()=>{
 const services=[{service_id:rid,business_name:'pingu',service_name:'Pipe repair'},{service_id:uid,business_name:'pingu',service_name:'Install Ceiling Light'}];
 const f=fixture({catalogue:services,begin:()=>response({turn_id:rid,lease:rid,history:[{role:'assistant',content:'pingu only offers electrical services.'},{role:'user',content:'Book pipe repair tomorrow 2pm'}]}),gemini:(n,b)=>{
  const system=b.systemInstruction.parts[0].text;
  assert.match(system,/Fresh customer-scoped app data/);assert.match(system,/"service_name":"Pipe repair"/);
  assert.match(system,/today is|Today is/);assert.match(system,/tomorrow is 2026-10-16/);
  return response({candidates:[{content:{role:'model',parts:[{text:'I can prepare that request.'}]}}]});
 }});f.deps.now=()=>Date.parse('2026-10-14T17:00:00Z');
 assert.equal((await handleAssistant(req({mode:'assist'}),f.deps)).status,200);
 assert.equal(f.calls.find(c=>c.url.endsWith('customer_search_services')).body.p_keyword,null);
 assert.equal(f.calls.find(c=>c.url.includes('/saved_addresses?')).init.headers.Authorization,'Bearer customer');
});

test('booking options finds all named-provider services and stages the selected available slot',async()=>{
 const services=[{service_id:rid,provider_id:rid,business_name:'pingu',service_name:'Pipe repair',quoted_amount:100},{service_id:uid,provider_id:rid,business_name:'pingu',service_name:'Install Ceiling Light',quoted_amount:60}];
 const f=fixture({catalogue:services,gemini:(n,b)=>{
  if(n===0)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'booking_options',args:{provider_name:'pingu',service_keyword:'pipe',date:'2026-10-15',time:'14:00',address_id:rid}}}]}}]});
  if(n===1){
   const result=b.contents.at(-1).parts[0].functionResponse.response.result;
   assert.equal(result.services.length,2);assert.equal(result.services[0].requested_time_available,true);
   assert.equal(result.saved_addresses[0].address_id,rid);
   assert.equal(result.coverage.providers[0].covers_selected,false);
   assert.match(result.coverage.coverage_policy,/not an automatic booking rejection/);
   return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'prepare_booking',args:{service_id:rid,address_id:rid,date:'2026-10-15',time:'14:00'}}}]}}]});
  }
  assert.match(b.contents.at(-1).parts[0].functionResponse.response.result.instruction,/review card is visible/);
  return response({candidates:[{content:{role:'model',parts:[{text:'Review your booking below.'}]}}]});
 }});
 const r=await handleAssistant(req({mode:'assist'}),f.deps);assert.equal(r.status,200);
 assert.equal((await r.json()).message.actions[0].kind,'booking');
 assert.equal(f.calls.filter(c=>c.url.endsWith('customer_ai_stage_action')).length,1);
 assert.ok(!f.calls.some(c=>/confirm_action|customer_create_booking/.test(c.url)));
 const search=f.calls.filter(c=>c.url.endsWith('customer_search_services')).at(-1);
 assert.equal(search.body.p_keyword,'pingu');assert.equal(search.body.p_city,null);
});

test('booking options reports unavailable requested time without substituting another',async()=>{
 const f=fixture({slots:[{scheduled_time:'10:00:00'}],gemini:(n,b)=>{
  if(!n)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'booking_options',args:{date:'2026-10-15',time:'14:00'}}}]}}]});
  const option=b.contents.at(-1).parts[0].functionResponse.response.result.services[0];
  assert.equal(option.requested_time_available,false);assert.deepEqual(option.available_times,['10:00']);
  return response({candidates:[{content:{role:'model',parts:[{text:'2pm is unavailable. Would 10am work?'}]}}]});
 }});
 assert.equal((await handleAssistant(req({mode:'assist'}),f.deps)).status,200);
 assert.ok(!f.calls.some(c=>c.url.endsWith('customer_ai_stage_action')));
});

test('booking planner rejects foreign address and reports missing addresses honestly',async()=>{
 for(const foreign of [true,false]){
  const f=fixture({addresses:[],gemini:(n,b)=>{
   if(!n)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'booking_options',args:foreign?{address_id:uid}:{}}}]}}]});
   const result=b.contents.at(-1).parts[0].functionResponse.response.result;
   if(foreign)assert.match(result.error,/your saved addresses/);
   else {assert.deepEqual(result.saved_addresses,[]);assert.match(result.next_step,/real service address/);}
   return response({candidates:[{content:{role:'model',parts:[{text:'Please add your service address.'}]}}]});
  }});
  assert.equal((await handleAssistant(req({mode:'assist'}),f.deps)).status,200);
  assert.ok(!f.calls.some(c=>c.url.endsWith('customer_ai_stage_action')));
 }
});

test('empty keyword search returns labelled alternatives rather than a false no-provider conclusion',async()=>{
 const f=fixture({gemini:(n,b)=>{
  if(!n)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'search_services',args:{keyword:'plumber',city:'Wrong city'}}}]}}]});
  const result=b.contents.at(-1).parts[0].functionResponse.response.result;
  assert.deepEqual(result.services,[]);assert.equal(result.alternatives[0].service_name,'Cleaner');assert.equal(result.match_type,'no_exact_match');
  return response({candidates:[{content:{role:'model',parts:[{text:'Here are broader alternatives.'}]}}]});
 }});
 const fetch=f.deps.fetch;f.deps.fetch=async(url,init)=>url.endsWith('customer_search_services')&&JSON.parse(init.body).p_keyword?response([]):fetch(url,init);
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
});

test('missing coordinates remain unknown instead of being treated as outside coverage',async()=>{
 const f=fixture({addresses:[{address_id:rid,coordinates:','}],gemini:(n,b)=>{
  if(!n)return response({candidates:[{content:{role:'model',parts:[{functionCall:{name:'nearby_providers',args:{address_id:rid}}}]}}]});
  const result=b.contents.at(-1).parts[0].functionResponse.response.result;
  assert.match(result.notice,/unknown/);assert.deepEqual(result.providers,[]);
  return response({candidates:[{content:{role:'model',parts:[{text:'The provider can confirm coverage.'}]}}]});
 }});
 assert.equal((await handleAssistant(req(),f.deps)).status,200);
 assert.ok(!f.calls.some(c=>c.url.endsWith('customer_provider_coverage')));
});
