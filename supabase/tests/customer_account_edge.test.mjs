import test from 'node:test';
import assert from 'node:assert/strict';
import {handleDeleteAccount} from '../functions/_shared/customer-account.ts';
import {handleGeocode,addressFields} from '../functions/_shared/customer-geocode.ts';
const env = key => ({SUPABASE_URL:'https://fixture.invalid',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'secret'})[key];
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json'}});
const request=(body,auth=true)=>new Request('https://fixture.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer customer-token'}:{})},body:JSON.stringify(body)});
function deletionFixture({wrongPassword=false,blocked=false,storageError=false,finishError=false,objects=false}={}){
 const calls=[];let listed=0;
 const fetch=async(url,options)=>{
  const path=new URL(url).pathname;const body=options.body?JSON.parse(options.body):null;calls.push({path,body,auth:options.headers.Authorization});
  if(path==='/auth/v1/user')return reply({id:'customer-id',email:'fixture@example.invalid'});
  if(path==='/auth/v1/token')return wrongPassword?reply({},400):reply({user:{id:'customer-id'},access_token:'verification-token'});
  if(path==='/auth/v1/logout')return reply({});
  if(path==='/rest/v1/rpc/customer_delete_prepare')return blocked?reply({code:'P0001',message:'Resolve bookings first'},400):reply({prepared:true});
  if(path==='/rest/v1/rpc/customer_delete_objects')return reply(objects && listed++===0?[{bucket:'profiles',name:'customer-id/avatar.jpg'}]:[]);
  if(path==='/storage/v1/object/profiles')return storageError?reply({},500):reply({});
  if(path==='/auth/v1/admin/users/customer-id')return reply({});
  if(path==='/rest/v1/rpc/customer_delete_finish'){if(finishError)throw new Error('network');return reply(null);}
  throw new Error('Unexpected '+url);
 };return {calls,fetch};
}
test('deletion requires bearer and explicit confirmation',async()=>{
 let calls=0;const deps={env,fetch:async()=>{calls++;throw new Error('network');}};
 assert.equal((await handleDeleteAccount(request({confirm:'DELETE',password:'fixture'},false),deps)).status,401);
 assert.equal((await handleDeleteAccount(request({password:'fixture'}),deps)).status,400);assert.equal(calls,0);
});
test('wrong password cannot start deletion and is never persisted',async()=>{
 const f=deletionFixture({wrongPassword:true});assert.equal((await handleDeleteAccount(request({confirm:'DELETE',password:'wrong'}),{env,fetch:f.fetch})).status,403);
 assert.equal(f.calls.some(c=>c.path.includes('/rpc/')),false);
});
test('unfinished bookings return actionable failure without deleting Auth',async()=>{
 const f=deletionFixture({blocked:true});const r=await handleDeleteAccount(request({confirm:'DELETE',password:'fixture'}),{env,fetch:f.fetch});
 assert.equal(r.status,409);assert.equal((await r.json()).error,'Resolve bookings first');assert.equal(f.calls.some(c=>c.path.includes('/admin/users')),false);
 assert.ok(f.calls.some(c=>c.path==='/auth/v1/logout'));
});
test('deletion uses verified identity, Storage API then Auth API',async()=>{
 const f=deletionFixture({objects:true});const r=await handleDeleteAccount(request({confirm:'DELETE',password:'fixture',user_id:'other-user'}),{env,fetch:f.fetch});
 assert.deepEqual(await r.json(),{deleted:true});
 assert.equal(f.calls.find(c=>c.path.endsWith('customer_delete_prepare')).body.p_auth_id,'customer-id');
 const storage=f.calls.findIndex(c=>c.path.startsWith('/storage/')),auth=f.calls.findIndex(c=>c.path.includes('/admin/users/'));
 assert.ok(storage>=0 && storage<auth);assert.deepEqual(f.calls[storage].body,{prefixes:['customer-id/avatar.jpg']});
 assert.equal(f.calls.filter(c=>c.path.includes('/rpc/')).some(c=>JSON.stringify(c.body).includes('password')),false);
});
test('failed object cleanup leaves Auth retryable and reports incomplete deletion',async()=>{
 const f=deletionFixture({objects:true,storageError:true});const r=await handleDeleteAccount(request({confirm:'DELETE',password:'fixture'}),{env,fetch:f.fetch});
 assert.equal(r.status,503);assert.match((await r.json()).error,/cleanup has not finished/);assert.equal(f.calls.some(c=>c.path.includes('/admin/users/')),false);
});
test('completion-record outage does not misreport successful Auth deletion',async()=>{
 const f=deletionFixture({finishError:true});assert.deepEqual(await (await handleDeleteAccount(request({confirm:'DELETE',password:'fixture'}),{env,fetch:f.fetch})).json(),{deleted:true});
});
test('address parser handles federal territories and clears missing previous fields',()=>{
 assert.deepEqual(addressFields({properties:{countrycode:'MY',city:'Kuala Lumpur',street:'Lorong Kuda',housenumber:'10'}}),{addressLine:'10, Lorong Kuda',city:'Kuala Lumpur',state:'Kuala Lumpur',postcode:''});
 assert.deepEqual(addressFields({properties:{countrycode:'SG',city:'Singapore'}}),{addressLine:'',city:'',state:'',postcode:''});
});
function geocodeFixture({claim={allowed:true},role='customer',source=[]}={}){
 const calls=[];return {calls,fetch:async(url,options)=>{calls.push({url,options});
  if(url.includes('/account_identity'))return reply({role});
  if(url.includes('/customer_geocode_claim'))return reply(claim);
  if(url.includes('/customer_geocode_store'))return new Response(null,{status:204});
  if(url.startsWith('https://photon.komoot.io/'))return reply(source);
  throw new Error('Unexpected request');
 }};
}
test('geocoding rejects invalid coordinates before any upstream call',async()=>{
 const f=geocodeFixture();assert.equal((await handleGeocode(request({kind:'reverse',lat:91,lng:100}),{env,fetch:f.fetch})).status,400);assert.equal(f.calls.length,0);
});
test('geocoding requires a canonical customer role',async()=>{
 const f=geocodeFixture({role:'provider'});assert.equal((await handleGeocode(request({kind:'search',query:'Kuala Lumpur'}),{env,fetch:f.fetch})).status,403);assert.equal(f.calls.length,1);
});
test('global rate gate prevents external requests',async()=>{
 const f=geocodeFixture({claim:{allowed:false}});const r=await handleGeocode(request({kind:'search',query:'Kuala Lumpur'}),{env,fetch:f.fetch});
 assert.equal(r.status,429);assert.equal(r.headers.get('Retry-After'),'2');assert.equal(f.calls.length,2);
});
test('cached empty search is a valid result without another external call',async()=>{
 const f=geocodeFixture({claim:{cached:{value:null}}});const r=await handleGeocode(request({kind:'search',query:'Missing street'}),{env,fetch:f.fetch});assert.equal(r.status,200);assert.equal(await r.json(),null);assert.equal(f.calls.length,2);
});
test('search is Malaysia scoped, identified and cached including empty result',async()=>{
 const f=geocodeFixture();const r=await handleGeocode(request({kind:'search',query:'Kuala Lumpur'}),{env,fetch:f.fetch});assert.equal(await r.json(),null);
 const upstream=f.calls.find(c=>c.url.startsWith('https://photon'));assert.equal(new URL(upstream.url).searchParams.get('countrycode'),'MY');assert.match(upstream.options.headers['User-Agent'],/LocalLifeFYP/);
 assert.deepEqual(JSON.parse(f.calls.at(-1).options.body).p_result,{value:null});
});
