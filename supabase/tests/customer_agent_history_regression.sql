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
select set_config('test.agent_conversation',(public.customer_ai_create_conversation(gen_random_uuid())->>'id'),true);
select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,'eeeeeeee-1910-4000-8000-000000000001','goal','Find a plumber');
select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,'eeeeeeee-1910-4000-8000-000000000001','goal','Find a plumber');
select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,'eeeeeeee-1910-4000-8000-000000000002','question','Which day?');
select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,'eeeeeeee-1910-4000-8000-000000000003','reply','Tomorrow');
do $$declare h jsonb:=public.customer_ai_messages(current_setting('test.agent_conversation')::uuid); begin
 if jsonb_array_length(h)<>3 or h->1->>'origin'<>'agent' or h->1->>'role'<>'assistant' or h->2->>'role'<>'user' or h->1->'actions'<>'[]'::jsonb then raise exception 'Bad transcript'; end if;
end $$;
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,'eeeeeeee-1910-4000-8000-000000000001','goal','Changed')$q$,'22023');
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'payment','fake')$q$,'22023');
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'reply',chr(1))$q$,'22023');
select pg_temp.agent_expect_error('select * from private.ai_messages','42501');
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1900-4000-8000-000000000002","role":"authenticated","aal":"aal1"}',true);
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'reply','Foreign')$q$,'42501');
select pg_temp.agent_expect_error($q$select public.customer_ai_messages(current_setting('test.agent_conversation')::uuid)$q$,'42501');
select set_config('request.jwt.claims','{"sub":"eeeeeeee-1900-4000-8000-000000000001","role":"authenticated","aal":"aal1"}',true);
-- Chat receives the tagged history, preserving the trust boundary in the gateway.
do $$declare t jsonb:=public.customer_ai_begin_turn(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'Tell me more',null,'chat'); begin
 if t->'history'->1->>'origin'<>'agent' then raise exception 'Missing agent origin'; end if;
end $$;
select public.customer_ai_delete_conversation(current_setting('test.agent_conversation')::uuid);
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'result','Late completion')$q$,'42501');
reset role;
set local role anon;
select pg_temp.agent_expect_error($q$select public.customer_ai_agent_event(current_setting('test.agent_conversation')::uuid,gen_random_uuid(),'reply','Anonymous')$q$,'42501');
reset role;
select 'PASS: ordered transcript, idempotency, role tags, chat context, ownership, private isolation, deletion, anonymous rejection' as result;
rollback;
