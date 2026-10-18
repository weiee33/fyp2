-- Run in a rolled-back transaction after the fixture setup section of
-- admin_regression.sql (before "Capability boundaries"). No real messages sent.
reset role;
create temporary table support_test(request_id uuid, ticket_id uuid, path text) on commit drop;
insert into support_test(request_id,path) values('dddddddd-0000-4000-8000-000000000018',
 pg_temp.fixture_id('customer_auth')::text||'/dddddddd-0000-4000-8000-000000000018/0');
grant select,update on support_test to authenticated;
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select public.customer_prepare_support((select request_id from support_test),null,'Account question','I need help with my saved address.',1);
select public.customer_prepare_support((select request_id from support_test),null,'Account question','I need help with my saved address.',1);
select pg_temp.test_error('draft payload cannot change', $$select public.customer_prepare_support((select request_id from support_test),null,'Changed question','I need help with my saved address.',1)$$,'22023');
select pg_temp.test_assert('reserved photo accepted',private.support_photo_access((select path from support_test),true));
select pg_temp.test_assert('unreserved photo slot denied',not private.support_photo_access(replace((select path from support_test),'/0','/1'),true));
select pg_temp.test_error('missing photo cannot submit', $$select public.customer_submit_support((select request_id from support_test))$$,'22023');
insert into storage.objects(bucket_id,name,owner_id,metadata)
 select 'support-photos',path,auth.uid()::text,'{"size":128,"mimetype":"image/png"}'::jsonb from support_test;
select pg_temp.test_assert('customer can read own staged photo',exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select pg_temp.login_as('staff_auth','aal2');
select pg_temp.test_assert('admin cannot read unsubmitted photo',not exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select pg_temp.login_as('provider_auth','aal1');
select pg_temp.test_error('provider cannot submit support as customer', $$select public.customer_submit_support((select request_id from support_test))$$,'42501');
select pg_temp.test_assert('provider cannot read photo',not exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select pg_temp.login_as('customer_auth','aal1');
update support_test set ticket_id=(public.customer_submit_support(request_id)->>'dispute_id')::uuid;
select pg_temp.test_assert('submission retry returns same ticket', (public.customer_submit_support((select request_id from support_test))->>'dispute_id')::uuid=(select ticket_id from support_test));
select pg_temp.test_assert('prepare retry recovers lost final response', (public.customer_prepare_support((select request_id from support_test),null,'Account question','I need help with my saved address.',1)->>'dispute_id')::uuid=(select ticket_id from support_test));
select pg_temp.test_assert('ticket includes private attachment',public.customer_support_requests((select ticket_id from support_test))->0->'attachment_paths'->>0=(select path from support_test));
select pg_temp.test_assert('submitted photo cannot be overwritten',not private.support_photo_access((select path from support_test),true));
select pg_temp.test_error('direct draft mutation denied', $$update private.customer_support_drafts set description='replacement text'$$,'42501');
select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000019',pg_temp.fixture_id('booking_unpaid'),'Booking question','Please check the details of my booking.',0);
select public.customer_submit_support('dddddddd-0000-4000-8000-000000000019');
select pg_temp.test_error('duplicate open booking support denied', $$select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000020',pg_temp.fixture_id('booking_unpaid'),'Booking question','Please check the details of my booking.',0)$$,'22023');
select pg_temp.test_error('unknown booking rejected', $$select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000021','dddddddd-0000-4000-8000-000000000099','Booking question','Please check the details of my booking.',0)$$,'42501');
select pg_temp.test_error('photo count is bounded', $$select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000022',null,'Account question','Please check my account details.',4)$$,'22023');
select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000025',null,'Expired draft','Please check my account details.',1);
reset role;
update private.customer_support_drafts set created_at=now()-interval '25 hours' where request_id='dddddddd-0000-4000-8000-000000000025';
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_error('expired draft cannot submit', $$select public.customer_submit_support('dddddddd-0000-4000-8000-000000000025')$$,'22023');
select pg_temp.test_assert('expired draft cannot upload',not private.support_photo_access(pg_temp.fixture_id('customer_auth')::text||'/dddddddd-0000-4000-8000-000000000025/0',true));
select public.customer_prepare_support(('dddddddd-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,null,'Rate limit fixture','Please check my account details.',0) from generate_series(30,37) n;
select pg_temp.test_error('draft quota enforced', $$select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000038',null,'Rate limit fixture','Please check my account details.',0)$$,'22023');
select pg_temp.login_as('staff_auth','aal1');
select pg_temp.test_assert('admin photo access requires MFA',not exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select pg_temp.login_as('staff_auth','aal2');
select pg_temp.test_assert('MFA admin can view submitted photo',exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select public.admin_mutate('dispute_resolve',(select ticket_id from support_test),
 public.admin_detail('disputes',(select ticket_id from support_test))->>'version',
 '{"status":"Resolved","reason":"Your address can be updated under My Addresses."}');
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('customer sees administrator response',public.customer_support_requests((select ticket_id from support_test))->0->>'resolution'='Your address can be updated under My Addresses.');
reset role;
-- A second verified customer must not obtain another customer's request or file.
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,raw_user_meta_data,created_at,updated_at)
 values('dddddddd-0000-4000-8000-000000000023','00000000-0000-0000-0000-000000000000','authenticated','authenticated','__support_other@example.invalid',now(),'{"role":"customer"}',now(),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','dddddddd-0000-4000-8000-000000000023',true);
select set_config('request.jwt.claims','{"sub":"dddddddd-0000-4000-8000-000000000023","role":"authenticated","aal":"aal1"}',true);
select pg_temp.test_assert('other customer cannot see request',jsonb_array_length(public.customer_support_requests((select ticket_id from support_test)))=0);
select pg_temp.test_assert('other customer cannot read photo',not exists(select 1 from storage.objects where bucket_id='support-photos' and name=(select path from support_test)));
select pg_temp.test_error('other customer cannot submit reserved draft', $$select public.customer_submit_support((select request_id from support_test))$$,'42501');
select pg_temp.test_error('other customer cannot use another booking', $$select public.customer_prepare_support('dddddddd-0000-4000-8000-000000000024',pg_temp.fixture_id('booking_paid'),'Booking question','Please check the details of my booking.',0)$$,'42501');
reset role;
select pg_temp.test_assert('anonymous submit denied',not has_function_privilege('anon','public.customer_submit_support(uuid)','execute'));
select pg_temp.test_assert('support bucket private and bounded',(select not public and file_size_limit=5242880 from storage.buckets where id='support-photos'));
select pg_temp.test_assert('immutable file has no customer update or delete policy',not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and cmd in ('UPDATE','DELETE','ALL') and coalesce(qual,'') like '%support-photos%'));
select pg_temp.test_assert('retry creates one ticket',(select count(*)=1 from public.booking_disputes where request_id=(select request_id from support_test)));
select pg_temp.test_assert('draft cannot block auth deletion',(select confdeltype='c' from pg_constraint where conrelid='private.customer_support_drafts'::regclass and conname='customer_support_drafts_auth_id_fkey'));
select jsonb_build_object('passed',count(*)) as support_regression from pg_temp.admin_regression_results;
