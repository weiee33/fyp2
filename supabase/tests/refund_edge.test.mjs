import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {handleRefund} from '../functions/_shared/refunds.ts';
import {handleWebhook} from '../functions/_shared/fpx.ts';
const id='11111111-2222-4333-8444-555555555555';
const now=Date.parse('2026-10-25T08:00:00Z');
const env={SUPABASE_URL:'https://project.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service',STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture'};
const refund={id:'re_fixture',payment_intent:'pi_fixture',amount:1000,currency:'myr',status:'succeeded',livemode:false,metadata:{refund_id:id}};
const quote={refund_id:id,payment_intent:'pi_fixture',amount_sen:1000,submitted_at:new Date(now).toISOString(),gateway_reference:null,status:'Processing'};
const json=(v,status=200)=>new Response(JSON.stringify(v),{status});
const request=(body={refund_id:id},token='Bearer admin')=>new Request('https://project.invalid/refund',{method:'POST',headers:{Authorization:token},body:JSON.stringify(body)});
function fixture(options={}) {
 const calls=[];
 const deps={env:k=>({...env,...options.env})[k],now:()=>now,fetch:async(url,init)=>{
  calls.push({url,init});
  if(url.endsWith('/admin_prepare_refund'))return json({...quote,...options.quote},options.authStatus??200);
  if(url.includes('/refunds?'))return json(options.list??{data:[],has_more:false});
  if(url.endsWith('/refunds')) {if(options.timeout)throw new Error('timeout');return json({...refund,...options.refund},options.stripeStatus??200);}
  if(url.endsWith('/refunds/re_fixture'))return json({...refund,...options.refund});
  if(url.endsWith('/gateway_record_refund'))return json({status:options.refund?.status==='pending'?'Processing':'Succeeded'});
  if(url.endsWith('/gateway_reject_refund'))return json({recorded:true});
  throw new Error(`Unexpected URL ${url}`);
 }};
 return {deps,calls};
}
test('authentication, injected amounts, oversize body rejected',async()=>{
 const {deps,calls}=fixture();
 assert.equal((await handleRefund(request({},''),deps)).status,401);
 assert.equal((await handleRefund(request({refund_id:id,amount:1}),deps)).status,400);
 assert.equal((await handleRefund(request({refund_id:'x'.repeat(2000)}),deps)).status,400);
 assert.equal(calls.length,0);
});
test('database authorization failure cannot call Stripe',async()=>{
 const {deps,calls}=fixture({authStatus:403});assert.equal((await handleRefund(request(),deps)).status,409);
 assert.equal(calls.length,1);
});
test('trusted quote, stable idempotency key and service-only confirmation',async()=>{
 const {deps,calls}=fixture();
 assert.equal((await handleRefund(request(),deps)).status,200);
 assert.equal((await handleRefund(request(),deps)).status,200);
 const posts=calls.filter(c=>c.url.endsWith('/refunds'));
 assert.equal(posts.length,2);
 for(const {init} of posts){assert.equal(init.headers['Idempotency-Key'],`local-life-refund-${id}`);assert.equal(init.body.get('amount'),'1000');assert.equal(init.body.get('payment_intent'),'pi_fixture');}
 const record=calls.find(c=>c.url.endsWith('/gateway_record_refund'));
 assert.equal(record.init.headers.Authorization,'Bearer service');
 assert.equal(JSON.parse(record.init.body).p_reference,'re_fixture');
});
test('recovery finds existing refund instead of making another',async()=>{
 const {deps,calls}=fixture({list:{data:[refund],has_more:false}});
 assert.equal((await handleRefund(request(),deps)).status,200);
 assert.equal(calls.filter(c=>c.url.endsWith('/refunds')).length,0);
});
test('known reference refresh never creates another refund',async()=>{
 const {deps,calls}=fixture({quote:{gateway_reference:'re_fixture'}});
 assert.equal((await handleRefund(request(),deps)).status,200);
 assert.equal(calls.filter(c=>c.url.includes('/refunds?')||c.url.endsWith('/refunds')).length,0);
});
test('old uncertain submissions cannot replay an expired idempotency key',async()=>{
 const {deps,calls}=fixture({quote:{submitted_at:'2026-10-23T08:00:00Z'}});
 assert.equal((await handleRefund(request(),deps)).status,409);
 assert.equal(calls.filter(c=>c.url.endsWith('/refunds')).length,0);
});
test('network uncertainty retains reservation and never claims success',async()=>{
 const {deps,calls}=fixture({timeout:true});assert.equal((await handleRefund(request(),deps)).status,409);
 assert.equal(calls.filter(c=>c.url.endsWith('/gateway_record_refund')).length,0);
});
test('pending Stripe response stays processing',async()=>{
 const {deps}=fixture({refund:{status:'pending'}});
 assert.equal((await (await handleRefund(request(),deps)).json()).status,'Processing');
});
test('definitive Stripe rejection releases reservation but rate limits do not',async()=>{
 for(const status of [400,429,500]) {
  const {deps,calls}=fixture({stripeStatus:status});
  assert.equal((await handleRefund(request(),deps)).status,409);
  assert.equal(calls.filter(c=>c.url.endsWith('/gateway_reject_refund')).length,status===400?1:0);
  assert.equal(calls.filter(c=>c.url.endsWith('/gateway_record_refund')).length,0);
 }
});
test('live key or mismatched metadata never records confirmation',async()=>{
 for(const options of [{env:{STRIPE_SECRET_KEY:'sk_live_fixture'}},{refund:{metadata:{refund_id:'other'}}},{refund:{livemode:true}}]){
  const {deps,calls}=fixture(options);assert.equal((await handleRefund(request(),deps)).status,409);
  assert.equal(calls.filter(c=>c.url.endsWith('/gateway_record_refund')).length,0);
 }
});
test('refund webhook requires signature and retrieves current Stripe state',async()=>{
 const body=JSON.stringify({id:'evt_fixture',type:'refund.updated',livemode:false,data:{object:{...refund,status:'pending'}}});
 const timestamp=now/1000;
 const sig=`t=${timestamp},v1=${createHmac('sha256',env.STRIPE_WEBHOOK_SECRET).update(`${timestamp}.${body}`).digest('hex')}`;
 const {deps,calls}=fixture();
 assert.equal((await handleWebhook(new Request('https://project.invalid',{method:'POST',body}),deps)).status,400);
 assert.equal(calls.length,0);
 assert.equal((await handleWebhook(new Request('https://project.invalid',{method:'POST',headers:{'Stripe-Signature':sig},body}),deps)).status,200);
 const record=calls.find(c=>c.url.endsWith('/gateway_record_refund'));
 assert.equal(JSON.parse(record.init.body).p_status,'succeeded');
});
