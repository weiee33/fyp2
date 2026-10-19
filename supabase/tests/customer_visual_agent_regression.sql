-- Execute as database owner. Synthetic records are always rolled back.
begin;
create function pg_temp.agent_expect_error(statement text, expected_state text) returns void
language plpgsql as $$
declare actual text;
begin
 begin execute statement;
 exception when others then
  get stacked diagnostics actual=returned_sqlstate;
  if actual=expected_state then return; end if;
  raise exception 'Expected %, got %',expected_state,actual;
 end;
 raise exception 'Expected failure: %',statement;
end $$;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 'visual-agent-'||id||'@example.invalid','',now(),'{"provider":"email","providers":["email"]}',
 '{"role":"customer","full_name":"Synthetic Visual Agent"}',now(),now()
from unnest(array['eeeeeeee-1900-4000-8000-000000000001'::uuid,'eeeeeeee-1900-4000-8000-000000000002'::uuid]) id;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1900-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',1);
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',1)$q$,'22023');
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',2)$q$,'P0001');
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',13)$q$,'22023');
select pg_temp.agent_expect_error('select * from private.customer_visual_runs','42501');
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1900-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',true);
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',2)$q$,'42501');
reset role;
update private.customer_visual_runs set updated_at=now()-interval '2 seconds' where id='eeeeeeee-1901-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1900-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',2);
select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000002',1);
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000003',1)$q$,'P0001');
reset role;
update private.customer_visual_runs set created_at=now()-interval '6 minutes',updated_at=now()-interval '2 seconds' where id='eeeeeeee-1901-4000-8000-000000000001';
set local role authenticated;
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000001',3)$q$,'22023');
reset role;
update public.users set role='provider' where auth_user_id='eeeeeeee-1900-4000-8000-000000000001';
set local role authenticated;
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000003',1)$q$,'42501');
reset role;
set local role anon;
select pg_temp.agent_expect_error($q$select public.customer_ai_visual_budget('eeeeeeee-1901-4000-8000-000000000003',1)$q$,'42501');
reset role;
select 'PASS: ownership, sequence, pacing, expiry, role, anonymous access, private table isolation, and per-minute budget' as result;
rollback;
