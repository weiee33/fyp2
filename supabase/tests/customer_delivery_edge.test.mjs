import {test} from 'node:test';
import assert from 'node:assert/strict';
import {handleDelivery, sendPush, sendReceipt, receiptMessage, pushCopy, fcmAccess} from '../functions/_shared/delivery.ts';
import {generateKeyPairSync, createVerify} from 'node:crypto';
const now=Date.UTC(2026,9,16);
const secret='a'.repeat(64);
const job={id:'job-1',lease_id:'lease-1',notification_id:'notice-1',token:'device-token',expires_at:new Date(now+600000).toISOString(),payload:{title:'Your slot was accepted',language:'en',test_mode:true,amount_sen:10000,email:'receipt@example.invalid',receipt_url:'https://pay.stripe.com/receipts/payment/fixture'}};
const env={DELIVERY_WORKER_SECRET:secret,SUPABASE_URL:'https://db.invalid',SUPABASE_SERVICE_ROLE_KEY:'service-fixture',RESEND_API_KEY:'email-fixture',RECEIPT_FROM_EMAIL:'Home Serve <receipts@example.invalid>'};
const deps=(fetch,extra={})=>({fetch,now:()=>now,env:n=>({...env,...extra})[n]});
const json=(x,status=200)=>new Response(JSON.stringify(x),{status});
const request=(token=secret)=>new Request('https://worker.invalid',{method:'POST',headers:{Authorization:`Bearer ${token}`}});
test('worker denies missing/wrong credentials before any network or queue access',async()=>{
 for(const token of ['',secret.slice(1),'b'.repeat(64)]) assert.equal((await handleDelivery(request(token),deps(()=>{throw Error('network must not run')}))).status,401);
});
test('unconfigured delivery channels do not claim jobs',async()=>{
 const r=await handleDelivery(request(),deps(()=>{throw Error('network must not run')}));assert.equal(r.status,200);assert.equal((await r.json()).sent,0);
});
test('receipt is labelled sandbox and cannot link to an injected host or real-money receipt',()=>{
 assert.match(receiptMessage(job.payload).text,/No real money/);
 for(const url of ['https://evil.invalid/receipts/a','https://pay.stripe.com.evil.invalid/receipts/a','https://evil@pay.stripe.com/receipts/a','http://pay.stripe.com/receipts/a']) assert.throws(()=>receiptMessage({...job.payload,receipt_url:url}));
 assert.throws(()=>receiptMessage({...job.payload,test_mode:false}));
});
test('receipt retries use the same provider idempotency key and stored checkout email',async()=>{
 const keys=[];const d=deps(async(url,options)=>{assert.equal(url,'https://api.resend.com/emails');keys.push(options.headers['Idempotency-Key']);assert.deepEqual(JSON.parse(options.body).to,['receipt@example.invalid']);return json({id:'email-1'});});
 assert.equal(await sendReceipt(job,d),'sent');await sendReceipt(job,d);assert.equal(keys[0],keys[1]);
});
test('successful email is acknowledged with the exact lease; transient email failure stays retryable',async()=>{
 for(const status of [200,429,503]){
  let finish;
  const d=deps(async(url,options)=>{
   if(url.endsWith('/claim_deliveries'))return json([job]);
   if(url==='https://api.resend.com/emails')return json({},status);
   if(url.endsWith('/finish_delivery')){finish=JSON.parse(options.body);return json(null);}
   throw Error('unexpected URL');
  },{DELIVERY_EMAIL_ENABLED:'true'});
  assert.equal((await handleDelivery(request(),d)).status,200);
  assert.deepEqual(finish,{p_id:job.id,p_lease:job.lease_id,p_result:status===200?'sent':'retry'});
 }
});
test('FCM includes high-priority Android channel, expiration and privacy-safe deep link',async()=>{
 const d=deps(async(url,options)=>{const m=JSON.parse(options.body).message;assert.equal(m.android.ttl,'600s');assert.equal(m.android.priority,'HIGH');assert.equal(m.android.notification.channel_id,'booking_alerts');assert.equal(m.android.notification.tag,job.notification_id);assert.deepEqual(m.data,{notification_id:job.notification_id});assert.ok(!JSON.stringify(m.notification).includes('receipt@example'));return json({name:'sent'});});
 assert.equal(await sendPush(job,{project:'home-serve',token:'access'},d),'sent');
 assert.equal(await sendPush({...job,expires_at:new Date(now-1000).toISOString()},{project:'home-serve',token:'access'},deps(()=>{throw Error('expired must not send')})),'rejected');
});
test('only an explicit UNREGISTERED FCM error removes a device',async()=>{
 const access={project:'home-serve',token:'access'};
 assert.equal(await sendPush(job,access,deps(async()=>json({error:{details:[{errorCode:'UNREGISTERED'}]}},404))),'invalid_token');
 assert.equal(await sendPush(job,access,deps(async()=>json({error:{status:'PERMISSION_DENIED'}},403))),'retry');
 assert.equal(await sendPush(job,access,deps(async()=>json({},429))),'retry');
});
test('alerts follow the registered device language',()=>{
 assert.match(pushCopy('Your slot was accepted','zh').title,/预约/);
 assert.equal(pushCopy('Your slot was accepted','ms').title,'Tempahan Diterima');
});

test('booking request and payment success have meaningful phone alert copy',()=>{
 assert.equal(pushCopy('Booking requested','en').title,'Booking Requested');
 assert.equal(pushCopy('Payment verified','en').title,'Payment Successful');
 assert.equal(pushCopy('FPX payment verified','ms').title,'Pembayaran Berjaya');
});

test('shared Resend sender requires an owner restriction and never redirects another customer receipt',async()=>{
 let calls=0;
 const fetch=async(_,options)=>{calls++;assert.deepEqual(JSON.parse(options.body).to,['receipt@example.invalid']);return json({id:'sent'});};
 const config={RECEIPT_FROM_EMAIL:'Home Serve <onboarding@resend.dev>'};
 await assert.rejects(()=>sendReceipt(job,deps(fetch,config)),/Test recipient required/);
 assert.equal(await sendReceipt(job,deps(fetch,{...config,RECEIPT_TEST_RECIPIENT:'someone@example.invalid'})),'rejected');
 assert.equal(calls,0);
 assert.equal(await sendReceipt(job,deps(fetch,{...config,RECEIPT_TEST_RECIPIENT:'receipt@example.invalid'})),'sent');
 assert.equal(calls,1);
});
test('Firebase assertion is signed with messaging-only scope and a bounded lifetime',async()=>{
 const pair=generateKeyPairSync('rsa',{modulusLength:2048});
 const account={project_id:'home-serve-test',client_email:'push@home-serve-test.iam.gserviceaccount.com',private_key:pair.privateKey.export({type:'pkcs8',format:'pem'})};
 const d=deps(async(url,options)=>{
  assert.equal(url,'https://oauth2.googleapis.com/token');const assertion=options.body.get('assertion');const [h,p,s]=assertion.split('.');
  const claim=JSON.parse(Buffer.from(p,'base64url'));assert.equal(claim.scope,'https://www.googleapis.com/auth/firebase.messaging');assert.equal(claim.exp-claim.iat,3600);
  const verify=createVerify('RSA-SHA256');verify.update(`${h}.${p}`);assert.ok(verify.verify(pair.publicKey,Buffer.from(s,'base64url')));return json({access_token:'short-lived'});
 },{FIREBASE_SERVICE_ACCOUNT:JSON.stringify(account)});
 assert.deepEqual(await fcmAccess(d),{project:'home-serve-test',token:'short-lived'});
});
