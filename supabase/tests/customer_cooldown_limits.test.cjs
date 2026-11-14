const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync,readdirSync} = require('node:fs');
const {join} = require('node:path');
const {PGlite} = require('@electric-sql/pglite');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const dir=join(__dirname,'../migrations');
const source=readFileSync(join(dir,'20261002080447_customer_module_integration.sql'),'utf8');

test('customer cooldown policies execute in PostgreSQL', async t => {
 const db=new PGlite(); t.after(()=>db.close());
 await db.exec(`
 create schema private; create schema auth;
 create role anon; create role authenticated;
 create type public.urgency_level as enum('Low','Medium','High','Emergency');
 create table customer_profiles(customer_id uuid primary key,user_id uuid);
 create table provider_profiles(provider_id uuid primary key,user_id uuid,business_name text);
 create table services(service_id uuid primary key,provider_id uuid,service_name text,pricing_type text,base_price numeric,estimated_duration int);
 create table saved_addresses(address_id uuid,customer_id uuid,address_line text,city text,state text,postcode text,coordinates text);
 create table bookings(booking_id uuid primary key default gen_random_uuid(),customer_id uuid,provider_id uuid,service_id uuid,
 booking_date date,scheduled_time time,scheduled_datetime timestamptz,booking_status text default 'Pending',
 cancelled_at timestamptz,cancellation_reason text,reservation_expires_at timestamptz,request_id uuid,
 customer_address text,customer_coordinates text,special_instructions text,urgency public.urgency_level,total_amount numeric,
 duration_minutes int,service_name_snapshot text,provider_name_snapshot text,pricing_type_snapshot text,unit_price_snapshot numeric);
 create table payments(booking_id uuid,payment_status text);
 create table booking_disputes(booking_id uuid,opened_by uuid,subject text,description text);
 create table booking_status_history(booking_id uuid,new_status text,changed_by uuid,notes text);
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
 create table private.customer_deletions(auth_user_id uuid primary key);
 create function private.customer_id() returns uuid language sql as $$ select current_setting('test.customer')::uuid $$;
 create function private.current_user_id() returns uuid language sql as $$ select private.customer_id() $$;
 create function private.customer_booking_json(uuid,uuid) returns jsonb language sql as $$select to_jsonb(b) from public.bookings b where booking_id=$1 and customer_id=$2$$;
 create function private.customer_event(uuid,uuid,text,text,text) returns void language sql as $$ select $$;
 create function private.customer_booking_slots(uuid,date) returns jsonb language sql as $$select '[{"scheduled_time":"12:00:00"}]'::jsonb$$;
 insert into customer_profiles values('${id(1)}','${id(1)}'),('${id(2)}','${id(2)}');
 insert into provider_profiles values('${id(3)}','${id(3)}','Provider');
 insert into services values('${id(4)}','${id(3)}','Service A','Fixed',50,60),('${id(5)}','${id(3)}','Service B','Fixed',50,60);
 insert into saved_addresses values('${id(6)}','${id(1)}','Street','City','State','12345',null),('${id(7)}','${id(2)}','Street','City','State','12345',null);
 select set_config('test.customer','${id(1)}',false);
 `);
 // Use the production booking RPC body. Only external price/slot/event services
 // are fixture boundaries; the locks, idempotency and insert paths run unchanged.
 const createBody=source.slice(source.indexOf('create function private.customer_create_booking('));
 await db.exec(createBody.slice(0,createBody.indexOf('end $$;')+7));
 await db.exec(readFileSync(join(dir,readdirSync(dir).find(f=>f.endsWith('_customer_cooldown_limits.sql'))),'utf8'));
 const policy=readFileSync(join(dir,readdirSync(dir).find(f=>f.endsWith('_customer_support_deletion_and_cooldown_display.sql'))),'utf8');
 await db.exec('-- Return only'+policy.split('-- Return only')[1]);
 const create = async (service=4,request=10,address=6) => (await db.query(`select private.customer_create_booking('${id(service)}','${id(address)}',current_date+2,'12:00',null,'Medium','${id(request)}') b`)).rows[0].b;
 const cancel = bid => db.query('select private.customer_cancel_booking($1,$2)',[bid,'Plans changed']);
 let first;
 await t.test('failed cancellation creates no restriction',async()=>{
  first=await create();
  await assert.rejects(db.query('select private.customer_cancel_booking($1,$2)',[first.booking_id,'x']),/cancellation reason/);
  assert.equal((await db.query('select * from private.customer_service_cooldowns')).rows.length,0);
 });
 await t.test('successful cancellation blocks a fresh request for the same service',async()=>{
  await cancel(first.booking_id);
  await assert.rejects(create(4,11),/Wait 30 minutes/);
  const row=(await db.query('select extract(epoch from (expires_at-clock_timestamp())) seconds from private.customer_service_cooldowns')).rows[0];
  assert.ok(Number(row.seconds)>1790 && Number(row.seconds)<=1800);
 });
 await t.test('deadline display is customer scoped and includes the authoritative server time',async()=>{
  const a=(await db.query('select public.customer_service_cooldowns($1) result',[id(3)])).rows[0].result;
  assert.equal(a.cooldowns.length,1);assert.equal(a.cooldowns[0].service_id,id(4));
  assert.ok(new Date(a.cooldowns[0].retry_at)>new Date(a.server_now));
  await db.exec(`select set_config('test.customer','${id(2)}',false)`);
  assert.deepEqual((await db.query('select public.customer_service_cooldowns($1) result',[id(3)])).rows[0].result.cooldowns,[]);
  await db.exec(`select set_config('test.customer','${id(1)}',false)`);
  assert.deepEqual((await db.query('select public.customer_service_cooldowns($1) result',[id(99)])).rows[0].result.cooldowns,[]);
  assert.equal((await db.query("select has_function_privilege('anon','public.customer_service_cooldowns(uuid)','execute') allowed")).rows[0].allowed,false);
 });
 await t.test('retrying cancellation does not extend the deadline',async()=>{
  const before=(await db.query('select expires_at::text expiry from private.customer_service_cooldowns')).rows[0].expiry;
  await cancel(first.booking_id);
  assert.equal((await db.query('select expires_at::text expiry from private.customer_service_cooldowns')).rows[0].expiry,before);
 });
 await t.test('same request token remains idempotent and creates no new booking',async()=>{
  const retry=await create(); assert.equal(retry.booking_id,first.booking_id); assert.equal(retry.booking_status,'Cancelled');
 });
 await t.test('other services and other customers remain eligible',async()=>{
  await create(5,12);
  await db.exec(`select set_config('test.customer','${id(2)}',false)`);
  await create(4,13,7);
  await db.exec(`select set_config('test.customer','${id(1)}',false)`);
 });
 await t.test('direct insert cannot bypass the booking restriction',async()=>{
  await assert.rejects(db.exec(`insert into bookings(customer_id,service_id) values('${id(1)}','${id(4)}')`),/Wait 30 minutes/);
 });
 await t.test('expiry permits booking without a cleanup job',async()=>{
  await db.exec("update private.customer_service_cooldowns set expires_at=clock_timestamp()+interval '1 minute'");
  await assert.rejects(create(4,14),/Wait 30 minutes/);
  await db.exec('update private.customer_service_cooldowns set expires_at=clock_timestamp()');
  await create(4,14);
 });
 await t.test('provider/admin cancellations do not impose the customer restriction',async()=>{
  await db.exec('delete from private.customer_service_cooldowns');
  const b=await create(4,15);
  await db.query("update bookings set booking_status='Cancelled',cancelled_at=now() where booking_id=$1",[b.booking_id]);
  await create(4,16);
 });
 await t.test('preparing deletion does not start the email restriction',async()=>{
  await db.exec(`insert into auth.users values('${id(20)}','Test@Example.invalid','{}'); insert into private.customer_deletions values('${id(20)}')`);
  await db.exec("select public.customer_registration_check('test@example.invalid')");
  assert.equal((await db.query('select * from private.customer_email_cooldowns')).rows.length,0);
 });
 await t.test('rolled-back Auth deletion does not leave an email restriction',async()=>{
  await db.exec(`begin; delete from auth.users where id='${id(20)}'; rollback;`);
  assert.equal((await db.query('select * from private.customer_email_cooldowns')).rows.length,0);
 });
 await t.test('successful deletion starts a 14-day restriction using a fingerprint',async()=>{
  await db.exec(`delete from auth.users where id='${id(20)}'`);
  const r=(await db.query('select octet_length(email_fingerprint) bytes,extract(epoch from(expires_at-clock_timestamp())) seconds from private.customer_email_cooldowns')).rows[0];
  assert.equal(r.bytes,32); assert.ok(Number(r.seconds)>1209590 && Number(r.seconds)<=1209600);
  await assert.rejects(db.exec("select public.customer_registration_check('  TEST@example.INVALID  ')"),e=>{
   const detail=JSON.parse(e.detail);assert.equal(detail.code,'email_cooldown');
   assert.ok(new Date(detail.retry_at)>new Date());return /14 days/.test(e.message);
  });
 });
 await t.test('direct signup and provider-role signup cannot bypass the email restriction',async()=>{
  for(const role of ['customer','provider']) await assert.rejects(db.exec(`insert into auth.users values('${id(21)}','test@example.invalid','{"role":"${role}"}')`),/14 days/);
  await db.exec(`insert into auth.users values('${id(22)}','other@example.invalid','{}')`);
  await assert.rejects(db.exec(`update auth.users set email='TEST@example.invalid' where id='${id(22)}'`),/14 days/);
 });
 await t.test('expired restriction accepts registration at the boundary',async()=>{
  await db.exec("update private.customer_email_cooldowns set expires_at=clock_timestamp()+interval '1 second'");
  await assert.rejects(db.exec("select public.customer_registration_check('test@example.invalid')"),/14 days/);
  await db.exec('update private.customer_email_cooldowns set expires_at=clock_timestamp()');
  await db.exec(`select public.customer_registration_check('test@example.invalid'); insert into auth.users values('${id(21)}','test@example.invalid','{}')`);
 });
 await t.test('unrelated Auth deletions do not create customer restrictions',async()=>{
  await db.exec(`delete from auth.users where id='${id(22)}'`);
  await db.exec("select public.customer_registration_check('other@example.invalid')");
  assert.equal((await db.query('select count(*)::int n from private.customer_email_cooldowns')).rows[0].n,1);
 });
 await t.test('clients cannot inspect fingerprints, secrets or change deadlines',async()=>{
  for(const role of ['anon','authenticated']) {
   for(const table of ['customer_email_cooldowns','customer_email_fingerprint_key','customer_service_cooldowns']) {
    const r=(await db.query(`select has_table_privilege('${role}','private.${table}','select,insert,update,delete') allowed`)).rows[0]; assert.equal(r.allowed,false);
   }
   assert.equal((await db.query(`select has_function_privilege('${role}','private.customer_email_fingerprint(text)','execute') allowed`)).rows[0].allowed,false);
   assert.equal((await db.query(`select has_function_privilege('${role}','public.customer_registration_check(text)','execute') allowed`)).rows[0].allowed,true);
  }
 });
});
