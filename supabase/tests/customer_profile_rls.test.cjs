const {test}=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync,readdirSync}=require('node:fs');
const {join}=require('node:path');
const {PGlite}=require('@electric-sql/pglite');
const id=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;

test('profile RLS limits customer reads and preserves provider joins',async t=>{
 const db=new PGlite();t.after(()=>db.close());
 await db.exec(`
 create schema private;create schema auth;create role anon;create role authenticated;
 create table public.users(user_id uuid primary key,auth_user_id uuid,is_active boolean,role text);
 create table customer_profiles(customer_id uuid primary key,user_id uuid);
 create table provider_profiles(provider_id uuid primary key,user_id uuid);
 create table bookings(customer_id uuid,provider_id uuid);
 create table reviews(customer_id uuid,provider_id uuid);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.auth',true),'')::uuid$$;
 create function private.current_user_id() returns uuid language sql stable security definer set search_path='' as $$select user_id from public.users where auth_user_id=auth.uid() and is_active$$;
 create function private.customer_viewer_user_id() returns uuid language sql stable security definer set search_path='' as $$select user_id from public.users where auth_user_id=auth.uid() and role='customer'$$;
 grant usage on schema public,private,auth to authenticated,anon;
 grant select on public.users,customer_profiles,provider_profiles,bookings,reviews to authenticated;
 alter table public.users enable row level security;alter table customer_profiles enable row level security;alter table bookings enable row level security;
 create policy legacy_all_users on public.users for select to authenticated using(true);
 create policy legacy_all_profiles on customer_profiles for select to authenticated using(true);
 create policy booking_party on bookings for select to authenticated using(customer_id in(select customer_id from customer_profiles where user_id=private.current_user_id()) or provider_id in(select provider_id from provider_profiles where user_id=private.current_user_id()));
 insert into public.users values('${id(1)}','${id(1)}',true,'customer'),('${id(2)}','${id(2)}',true,'customer'),('${id(3)}','${id(3)}',true,'customer'),('${id(4)}','${id(4)}',true,'provider');
 insert into customer_profiles values('${id(11)}','${id(1)}'),('${id(12)}','${id(2)}'),('${id(13)}','${id(3)}');
 insert into provider_profiles values('${id(14)}','${id(4)}');
 insert into bookings values('${id(11)}','${id(14)}');
 insert into reviews values('${id(12)}','${id(14)}');
 `);
 const dir=join(__dirname,'../migrations');
 await db.exec(readFileSync(join(dir,readdirSync(dir).find(f=>f.endsWith('_customer_profile_read_scope.sql'))),'utf8'));
 const as=async n=>db.exec(`reset role;select set_config('test.auth','${id(n)}',false);set role authenticated;`);
 await t.test('customer sees only their profile despite the legacy permissive policy',async()=>{
  await as(1);assert.deepEqual((await db.query('select customer_id from customer_profiles')).rows,[{customer_id:id(11)}]);
  assert.equal((await db.query('select * from bookings')).rows.length,1);
 });
 await t.test('provider retains booked customers and review authors without recursion',async()=>{
  await as(4);assert.deepEqual((await db.query('select customer_id from customer_profiles order by customer_id')).rows,[{customer_id:id(11)},{customer_id:id(12)}]);
  assert.equal((await db.query('select b.customer_id from bookings b join customer_profiles c using(customer_id) join public.users u using(user_id)')).rows.length,1);
 });
 await t.test('suspended customer can still see their own profile',async()=>{
  await db.exec(`reset role;update public.users set is_active=false where user_id='${id(1)}'`);
  await as(1);assert.equal((await db.query('select * from customer_profiles')).rows.length,1);
 });
 await t.test('detached identity loses user and customer profile access with old claims',async()=>{
  await db.exec(`reset role;update public.users set auth_user_id=null where user_id='${id(1)}'`);
  await as(1);assert.deepEqual((await db.query('select * from customer_profiles')).rows,[]);
  assert.deepEqual((await db.query('select * from public.users')).rows,[]);
 });
 await db.exec('reset role');
 assert.equal((await db.query("select has_function_privilege('anon','private.can_read_customer_profile(uuid)','execute') allowed")).rows[0].allowed,false);
});
