-- Transactional, fail-fast regression suite for the admin foundation.
-- Run as the database owner AFTER the migration in the SAME transaction:
-- BEGIN; <migration if not installed>; <this file>; ROLLBACK;
-- Do not commit: all Auth users, profiles, payments and documents below are synthetic.
-- This suite does not exercise actual Auth emails, gateways, or Storage HTTP APIs.

create temporary table admin_regression_results (
  test_name text primary key,
  passed boolean not null default true
) on commit drop;
create temporary table admin_regression_ids (
  fixture_name text primary key,
  fixture_id uuid not null unique
) on commit drop;

insert into admin_regression_ids values
 ('super_auth','ffffffff-0000-4000-8000-000000000001'),
 ('staff_auth','ffffffff-0000-4000-8000-000000000002'),
 ('customer_auth','ffffffff-0000-4000-8000-000000000003'),
 ('provider_auth','ffffffff-0000-4000-8000-000000000004'),
 ('super_user','ffffffff-1000-4000-8000-000000000001'),
 ('staff_user','ffffffff-1000-4000-8000-000000000002'),
 ('customer_user','ffffffff-1000-4000-8000-000000000003'),
 ('provider_user','ffffffff-1000-4000-8000-000000000004'),
 ('super_profile','ffffffff-2000-4000-8000-000000000001'),
 ('staff_profile','ffffffff-2000-4000-8000-000000000002'),
 ('customer_profile','ffffffff-2000-4000-8000-000000000003'),
 ('provider_profile','ffffffff-2000-4000-8000-000000000004'),
 ('root_category','ffffffff-3000-4000-8000-000000000001'),
 ('child_category','ffffffff-3000-4000-8000-000000000002'),
 ('unused_category','ffffffff-3000-4000-8000-000000000003'),
 ('service','ffffffff-4000-4000-8000-000000000001'),
 ('booking_paid','ffffffff-5000-4000-8000-000000000001'),
 ('booking_unpaid','ffffffff-5000-4000-8000-000000000002'),
 ('booking_review5','ffffffff-5000-4000-8000-000000000003'),
 ('booking_review3','ffffffff-5000-4000-8000-000000000004'),
 ('payment_paid','ffffffff-6000-4000-8000-000000000001'),
 ('payment_failed','ffffffff-6000-4000-8000-000000000002'),
 ('review5','ffffffff-7000-4000-8000-000000000001'),
 ('review3','ffffffff-7000-4000-8000-000000000002'),
 ('credential_current','ffffffff-8000-4000-8000-000000000001'),
 ('credential_expired','ffffffff-8000-4000-8000-000000000002'),
 ('invitation_identity','ffffffff-0000-4000-8000-000000000005');

create function pg_temp.fixture_id(fixture text) returns uuid language sql stable
security invoker set search_path='' as $$
 select fixture_id from pg_temp.admin_regression_ids where fixture_name=fixture
$$;
create function pg_temp.test_assert(test_name text,condition boolean) returns void
language plpgsql security invoker set search_path='' as $$
begin
 if condition is distinct from true then raise exception 'FAIL: %',test_name; end if;
 insert into pg_temp.admin_regression_results(test_name) values(test_name);
end $$;
create function pg_temp.test_error(test_name text,statement text,expected_state text default null,expected_message text default null)
returns void language plpgsql security invoker set search_path='' as $$
declare caught boolean:=false; actual_state text; actual_message text;
begin
 begin
  execute statement;
 exception when others then
  caught:=true;
  get stacked diagnostics actual_state=returned_sqlstate,actual_message=message_text;
 end;
 if not caught then raise exception 'FAIL: % unexpectedly succeeded',test_name; end if;
 if expected_state is not null and actual_state<>expected_state then
  raise exception 'FAIL: % expected SQLSTATE %, got %: %',test_name,expected_state,actual_state,actual_message;
 end if;
 if expected_message is not null and position(lower(expected_message) in lower(actual_message))=0 then
  raise exception 'FAIL: % expected message containing %, got %',test_name,expected_message,actual_message;
 end if;
 insert into pg_temp.admin_regression_results(test_name) values(test_name);
end $$;
create function pg_temp.login_as(fixture text,assurance text default 'aal2') returns void
language plpgsql security invoker set search_path='' as $$
declare identity uuid:=pg_temp.fixture_id(fixture);
begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',identity,'role','authenticated','aal',assurance)::text,true);
 perform set_config('request.jwt.claim.sub',identity::text,true);
end $$;

-- GRANT does not resolve the pg_temp alias the way object/function lookup does.
-- The tables above initialize the concrete pg_temp_N schema for this session.
do $$begin
 execute format('grant usage on schema %I to authenticated,anon',pg_my_temp_schema()::regnamespace::text);
end $$;
grant select on pg_temp.admin_regression_ids to authenticated,anon;
grant select,insert on pg_temp.admin_regression_results to authenticated,anon;
grant execute on function pg_temp.fixture_id(text),pg_temp.test_assert(text,boolean),
 pg_temp.test_error(text,text,text,text),pg_temp.login_as(text,text) to authenticated,anon;

-- Auth identifiers deliberately differ from application user identifiers.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select fixture_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 '__admin_regression_'||fixture_name||'@example.invalid','',now(),'{"provider":"email","providers":["email"]}',
 case when fixture_name in ('super_auth','staff_auth') then '{"role":"admin"}'::jsonb
      when fixture_name='provider_auth' then '{"role":"provider"}'::jsonb else '{"role":"customer"}'::jsonb end,
 now(),now()
from pg_temp.admin_regression_ids where fixture_name like '%_auth';

-- The live Auth signup trigger must ignore attempted admin elevation from user metadata.
select pg_temp.test_assert('signup ignores administrator role injection in user metadata',
 (select role='customer' from public.users where auth_user_id=pg_temp.fixture_id('super_auth')));
select pg_temp.test_assert('signup permits ordinary provider registration',
 (select role='provider' from public.users where auth_user_id=pg_temp.fixture_id('provider_auth')));
-- Remove only automatically-created synthetic profiles. Recreate them below with
-- application IDs deliberately differing from Auth IDs to test the mapping boundary.
delete from public.customer_profiles where user_id in
 (select fixture_id from pg_temp.admin_regression_ids where fixture_name like '%_auth');
delete from public.provider_profiles where user_id in
 (select fixture_id from pg_temp.admin_regression_ids where fixture_name like '%_auth');
delete from public.users where user_id in
 (select fixture_id from pg_temp.admin_regression_ids where fixture_name like '%_auth');

insert into public.users(user_id,auth_user_id,email,password_hash,full_name,role,email_verified)
values
 (pg_temp.fixture_id('super_user'),pg_temp.fixture_id('super_auth'),'__admin_regression_super_auth@example.invalid','regression-only-noncredential','Regression Super Admin','admin',true),
 (pg_temp.fixture_id('staff_user'),pg_temp.fixture_id('staff_auth'),'__admin_regression_staff_auth@example.invalid','regression-only-noncredential','Regression Staff Admin','admin',true),
 (pg_temp.fixture_id('customer_user'),pg_temp.fixture_id('customer_auth'),'__admin_regression_customer_auth@example.invalid','regression-only-noncredential','Regression Customer','customer',true),
 (pg_temp.fixture_id('provider_user'),pg_temp.fixture_id('provider_auth'),'__admin_regression_provider_auth@example.invalid','regression-only-noncredential','Regression Provider','provider',true);
insert into public.admin_profiles(admin_id,user_id,admin_role_level) values
 (pg_temp.fixture_id('super_profile'),pg_temp.fixture_id('super_user'),'super_admin'),
 (pg_temp.fixture_id('staff_profile'),pg_temp.fixture_id('staff_user'),'staff');
insert into public.customer_profiles(customer_id,user_id)
values(pg_temp.fixture_id('customer_profile'),pg_temp.fixture_id('customer_user'));
insert into public.provider_profiles(provider_id,user_id,business_name,business_license)
values(pg_temp.fixture_id('provider_profile'),pg_temp.fixture_id('provider_user'),'__Admin Regression Services','QA-LICENCE-0001');
insert into public.service_categories(category_id,category_name,parent_category_id,color_code) values
 (pg_temp.fixture_id('root_category'),'__Admin Regression Root',null,'#EA580C'),
 (pg_temp.fixture_id('child_category'),'__Admin Regression Child',pg_temp.fixture_id('root_category'),'#EA580C'),
 (pg_temp.fixture_id('unused_category'),'__Admin Regression Unused',null,'#EA580C');
insert into public.services(service_id,provider_id,category_id,service_name,description,base_price)
values(pg_temp.fixture_id('service'),pg_temp.fixture_id('provider_profile'),pg_temp.fixture_id('child_category'),
 '__Admin Regression Service','Synthetic fixture for transactional database tests',100);
insert into public.bookings(booking_id,customer_id,provider_id,service_id,booking_date,scheduled_time,
 scheduled_datetime,customer_address,total_amount,booking_status)
select fixture_id,pg_temp.fixture_id('customer_profile'),pg_temp.fixture_id('provider_profile'),pg_temp.fixture_id('service'),
 current_date+1,'10:00:00',(current_date+1+time '10:00:00') at time zone 'Asia/Kuala_Lumpur',
 'Synthetic address for transactional regression tests',100,
 case when fixture_name in ('booking_review5','booking_review3') then 'Completed'::public.booking_status else 'Pending'::public.booking_status end
from pg_temp.admin_regression_ids where fixture_name like 'booking_%';
insert into public.payments(payment_id,booking_id,customer_id,payment_amount,payment_status) values
 (pg_temp.fixture_id('payment_paid'),pg_temp.fixture_id('booking_paid'),pg_temp.fixture_id('customer_profile'),100,'Success'),
 (pg_temp.fixture_id('payment_failed'),pg_temp.fixture_id('booking_unpaid'),pg_temp.fixture_id('customer_profile'),100,'Failed');
insert into public.reviews(review_id,booking_id,customer_id,provider_id,rating_score,review_comment) values
 (pg_temp.fixture_id('review5'),pg_temp.fixture_id('booking_review5'),pg_temp.fixture_id('customer_profile'),pg_temp.fixture_id('provider_profile'),5,'Synthetic five-star review'),
 (pg_temp.fixture_id('review3'),pg_temp.fixture_id('booking_review3'),pg_temp.fixture_id('customer_profile'),pg_temp.fixture_id('provider_profile'),3,'Synthetic three-star review');
insert into public.provider_certifications(certification_id,provider_id,certification_name,expiry_date,file_url,is_verified) values
 (pg_temp.fixture_id('credential_current'),pg_temp.fixture_id('provider_profile'),'Current regression credential',current_date+30,'provider-documents/'||pg_temp.fixture_id('provider_auth')::text||'/regression-current.pdf',false),
 (pg_temp.fixture_id('credential_expired'),pg_temp.fixture_id('provider_profile'),'Expired regression credential',current_date-1,'provider-documents/'||pg_temp.fixture_id('provider_auth')::text||'/regression-expired.pdf',true);

-- Capability boundaries include direct private-function access.
select pg_temp.test_assert('anonymous cannot execute admin list',not has_function_privilege('anon','public.admin_list(text,text,text,integer)','EXECUTE'));
select pg_temp.test_assert('authenticated cannot execute internal authorizer',not has_function_privilege('authenticated','private.admin_actor(boolean)','EXECUTE'));
select pg_temp.test_assert('authenticated cannot execute notification writer',not has_function_privilege('authenticated','private.admin_notify(uuid,text,text,uuid)','EXECUTE'));
select pg_temp.test_assert('authenticated cannot mutate invitation records',not has_table_privilege('authenticated','private.admin_invitations','INSERT,UPDATE,DELETE,TRUNCATE'));
select pg_temp.test_assert('authenticated cannot truncate public users',not has_table_privilege('authenticated','public.users','TRUNCATE'));
select pg_temp.test_assert('authenticated cannot read password hashes',not has_column_privilege('authenticated','public.users','password_hash','SELECT'));
select pg_temp.test_assert('authenticated cannot assign its role',not has_column_privilege('authenticated','public.users','role','UPDATE'));
select pg_temp.test_assert('authenticated cannot assign Auth linkage',not has_column_privilege('authenticated','public.users','auth_user_id','UPDATE'));

set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select set_config('request.jwt.claim.sub','',true);
select pg_temp.test_error('anonymous admin RPC is denied','select public.admin_list(''users'')','42501');

set local role authenticated;
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('canonical Auth linkage returns application user',private.current_user_id()=pg_temp.fixture_id('customer_user'));
select pg_temp.test_assert('customer can read own profile with distinct Auth ID',(select count(*)=1 from public.customer_profiles where customer_id=pg_temp.fixture_id('customer_profile')));
select pg_temp.test_assert('customer can read own bookings with distinct Auth ID',(select count(*)=4 from public.bookings where customer_id=pg_temp.fixture_id('customer_profile')));
select pg_temp.test_assert('customer cannot discover unverified provider',(select count(*)=0 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_assert('customer cannot discover unverified provider services',(select count(*)=0 from public.services where service_id=pg_temp.fixture_id('service')));
select pg_temp.test_error('customer cannot call admin RPC','select public.admin_list(''users'')','42501','administrator');
select pg_temp.test_error('customer cannot request credential signing path','select public.admin_document(pg_temp.fixture_id(''credential_current''))','42501','administrator');
select pg_temp.test_error('customer cannot call private admin RPC','select private.admin_list(''users'','''','''',1)','42501','administrator');
select pg_temp.test_error('customer cannot call private notification helper','select private.admin_notify(pg_temp.fixture_id(''customer_user''),''x'',''y'',null)','42501');
select pg_temp.test_error('customer cannot read password hash','select password_hash from public.users','42501');
select pg_temp.test_error('customer cannot escalate role','update public.users set role=''admin'' where user_id=pg_temp.fixture_id(''customer_user'')','42501');
select pg_temp.test_error('customer cannot alter account activity','update public.users set is_active=false where user_id=pg_temp.fixture_id(''customer_user'')','42501');
update public.users set full_name='Regression Customer Updated' where user_id=pg_temp.fixture_id('customer_user');
select pg_temp.test_assert('customer may edit allowed own profile columns',(select full_name='Regression Customer Updated' from public.users where user_id=pg_temp.fixture_id('customer_user')));
do $$declare changed integer; begin
 update public.users set full_name='Unauthorized change' where user_id=pg_temp.fixture_id('provider_user');
 get diagnostics changed=row_count;
 perform pg_temp.test_assert('customer cannot edit another user',changed=0);
end $$;

select pg_temp.login_as('provider_auth');
select pg_temp.test_assert('provider can read own unverified profile',(select count(*)=1 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_assert('provider can read own credentials with distinct Auth ID',(select count(*)=2 from public.provider_certifications where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_error('provider cannot verify its own business','update public.provider_profiles set verification_status=''Verified'' where provider_id=pg_temp.fixture_id(''provider_profile'')','42501');
select pg_temp.test_error('provider cannot call admin RPC','select public.admin_list(''providers'')','42501','administrator');

select pg_temp.login_as('staff_auth','aal1');
select pg_temp.test_assert('admin identity works before MFA',(public.admin_identity()->>'mfa_verified')::boolean=false);
select pg_temp.test_error('AAL1 administrator cannot list data','select public.admin_list(''users'')','42501','authenticator');
select pg_temp.test_error('AAL1 administrator cannot request credential signing path','select public.admin_document(pg_temp.fixture_id(''credential_current''))','42501','authenticator');
select pg_temp.test_error('AAL1 administrator cannot mutate data','select public.admin_mutate(''category_save'',null,null,''{"name":"Unauthorized","active":true}''::jsonb)','42501','authenticator');
select pg_temp.login_as('staff_auth','aal2');
select pg_temp.test_assert('AAL2 staff can list administrative users',(public.admin_list('users','__admin_regression_')->>'total')::integer=4);
select pg_temp.test_assert('admin list does not expose password hashes',position('password_hash' in public.admin_list('users','__admin_regression_')::text)=0);
select pg_temp.test_assert('admin detail does not expose password hashes',not(public.admin_detail('users',pg_temp.fixture_id('customer_user')) ? 'password_hash'));
select pg_temp.test_error('staff cannot list audit logs','select public.admin_list(''audit'')','42501','Super Admin');
select pg_temp.test_error('staff cannot request refunds',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''payment''->>''version'',''{"amount":1,"reason":"Regression refund reason"}''::jsonb)','42501','Super Admin');

select pg_temp.login_as('super_auth');
select pg_temp.test_assert('Super Admin identity resolves assigned level',public.admin_identity()->>'role_level'='super_admin');
select pg_temp.test_assert('AAL2 administrator receives private credential object path',
 public.admin_document(pg_temp.fixture_id('credential_current'))->>'path'=pg_temp.fixture_id('provider_auth')::text||'/regression-current.pdf');
select pg_temp.test_error('list rejects invalid resource','select public.admin_list(''arbitrary_table'')','P0001','Unknown resource');
select pg_temp.test_error('list rejects invalid page','select public.admin_list(''users'','''','''',0)','P0001','Invalid page');
select pg_temp.test_error('list rejects null page','select public.admin_list(''users'','''','''',null)','P0001','Invalid page');
select pg_temp.test_error('mutation rejects non-object JSON','select public.admin_mutate(''category_save'',null,null,''[]''::jsonb)','P0001','Invalid form data');
select pg_temp.test_error('mutation rejects SQL-null JSON','select public.admin_mutate(''category_save'',null,null,null)','P0001','Invalid form data');
select pg_temp.test_error('user status rejects missing active',
 'select public.admin_mutate(''user_status'',pg_temp.fixture_id(''customer_user''),public.admin_detail(''users'',pg_temp.fixture_id(''customer_user''))->>''version'',''{"reason":"Regression validation reason"}''::jsonb)','P0001','Invalid account status');
select pg_temp.test_error('provider verification rejects null status',
 'select public.admin_mutate(''provider_verify'',pg_temp.fixture_id(''provider_profile''),public.admin_detail(''providers'',pg_temp.fixture_id(''provider_profile''))->>''version'',''{"status":null,"reason":"Regression validation reason"}''::jsonb)','P0001','Invalid verification status');
select pg_temp.test_error('review moderation rejects missing decision',
 'select public.admin_mutate(''review_moderate'',pg_temp.fixture_id(''review5''),public.admin_detail(''reviews'',pg_temp.fixture_id(''review5''))->>''version'',''{"reason":"Regression validation reason"}''::jsonb)','P0001','Invalid moderation decision');
select pg_temp.test_error('category saving rejects missing activity',
 'select public.admin_mutate(''category_save'',null,null,''{"name":"Missing activity"}''::jsonb)','P0001','Invalid category status');
select pg_temp.test_error('certificate verification rejects missing choice',
 'select public.admin_mutate(''certificate_verify'',pg_temp.fixture_id(''credential_current''),(select c->>''version'' from jsonb_array_elements(public.admin_detail(''providers'',pg_temp.fixture_id(''provider_profile''))->''certifications'') c where c->>''certification_id''=pg_temp.fixture_id(''credential_current'')::text),''{"reason":"Regression validation reason"}''::jsonb)','P0001','Invalid verification choice');
select pg_temp.test_error('mutation rejects stale version',
 'select public.admin_mutate(''user_status'',pg_temp.fixture_id(''customer_user''),''stale-version'',''{"active":false,"reason":"Regression suspension reason"}''::jsonb)','40001','changed');
select pg_temp.test_error('administrator accounts cannot be suspended',
 'select public.admin_mutate(''user_status'',pg_temp.fixture_id(''staff_user''),public.admin_detail(''users'',pg_temp.fixture_id(''staff_user''))->>''version'',''{"active":false,"reason":"Regression suspension reason"}''::jsonb)','P0001','Administrator accounts');

-- All mutations use the version obtained through the actual public read API.
select public.admin_mutate('user_status',pg_temp.fixture_id('customer_user'),
 public.admin_detail('users',pg_temp.fixture_id('customer_user'))->>'version',
 '{"active":false,"reason":"Regression suspension reason"}');
select pg_temp.test_assert('suspension changes application state',(public.admin_detail('users',pg_temp.fixture_id('customer_user'))->>'is_active')::boolean=false);
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('suspended identity has no active application actor',private.current_user_id() is null);
select pg_temp.test_assert('suspended customer cannot read bookings',(select count(*)=0 from public.bookings where customer_id=pg_temp.fixture_id('customer_profile')));
do $$declare changed integer; begin
 update public.users set full_name='Suspended mutation' where user_id=pg_temp.fixture_id('customer_user');
 get diagnostics changed=row_count;
 perform pg_temp.test_assert('suspended customer cannot update own profile',changed=0);
end $$;
select pg_temp.login_as('super_auth');
select public.admin_mutate('user_status',pg_temp.fixture_id('customer_user'),
 public.admin_detail('users',pg_temp.fixture_id('customer_user'))->>'version',
 '{"active":true,"reason":"Regression reactivation reason"}');

-- Hierarchy and deletion guards preserve dependent services and history.
select pg_temp.test_error('category cycle is rejected',
 'select public.admin_mutate(''category_save'',pg_temp.fixture_id(''root_category''),public.admin_detail(''categories'',pg_temp.fixture_id(''root_category''))->>''version'',jsonb_build_object(''name'',''__Admin Regression Root'',''active'',true,''parent_id'',pg_temp.fixture_id(''child_category'')))','P0001','ancestor');
select pg_temp.test_error('category self-parent is rejected',
 'select public.admin_mutate(''category_save'',pg_temp.fixture_id(''root_category''),public.admin_detail(''categories'',pg_temp.fixture_id(''root_category''))->>''version'',jsonb_build_object(''name'',''__Admin Regression Root'',''active'',true,''parent_id'',pg_temp.fixture_id(''root_category'')))','P0001','ancestor');
select pg_temp.test_error('parent with active child cannot be deactivated',
 'select public.admin_mutate(''category_save'',pg_temp.fixture_id(''root_category''),public.admin_detail(''categories'',pg_temp.fixture_id(''root_category''))->>''version'',''{"name":"__Admin Regression Root","active":false}''::jsonb)','P0001','subcategories');
select pg_temp.test_error('category with subcategory cannot be deleted',
 'select public.admin_mutate(''category_delete'',pg_temp.fixture_id(''root_category''),public.admin_detail(''categories'',pg_temp.fixture_id(''root_category''))->>''version'')','P0001','in use');
select pg_temp.test_error('category with service cannot be deleted',
 'select public.admin_mutate(''category_delete'',pg_temp.fixture_id(''child_category''),public.admin_detail(''categories'',pg_temp.fixture_id(''child_category''))->>''version'')','P0001','in use');
select pg_temp.test_error('case-insensitive duplicate category is rejected',
 'select public.admin_mutate(''category_save'',null,null,''{"name":"__admin regression root","active":true}''::jsonb)','P0001','already exists');
select public.admin_mutate('category_delete',pg_temp.fixture_id('unused_category'),
 public.admin_detail('categories',pg_temp.fixture_id('unused_category'))->>'version');
select pg_temp.test_error('unused category can be deleted',
 'select public.admin_detail(''categories'',pg_temp.fixture_id(''unused_category''))','P0002','not found');

-- An expired credential must be rejectable, while new approval requires a current document.
select pg_temp.test_error('expired credential cannot be approved',
 'select public.admin_mutate(''certificate_verify'',pg_temp.fixture_id(''credential_expired''),(select c->>''version'' from jsonb_array_elements(public.admin_detail(''providers'',pg_temp.fixture_id(''provider_profile''))->''certifications'') c where c->>''certification_id''=pg_temp.fixture_id(''credential_expired'')::text),''{"verified":true,"reason":"Regression credential review"}''::jsonb)','P0001','current credential');
select public.admin_mutate('certificate_verify',pg_temp.fixture_id('credential_expired'),
 (select c->>'version' from jsonb_array_elements(public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->'certifications') c where c->>'certification_id'=pg_temp.fixture_id('credential_expired')::text),
 '{"verified":false,"reason":"Regression expired credential revocation"}');
select pg_temp.test_assert('expired credential verification can be revoked',
 (select (c->>'is_verified')::boolean=false from jsonb_array_elements(public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->'certifications') c where c->>'certification_id'=pg_temp.fixture_id('credential_expired')::text));

-- Admin account and verification changes must affect actual marketplace discovery.
select public.admin_mutate('provider_verify',pg_temp.fixture_id('provider_profile'),
 public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'version',
 '{"status":"Verified","reason":"Regression provider licence review"}');
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select set_config('request.jwt.claim.sub','',true);
select pg_temp.test_assert('anonymous can discover verified active provider',
 (select count(*)=1 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_assert('anonymous can discover verified active service',
 (select count(*)=1 from public.services where service_id=pg_temp.fixture_id('service')));
set local role authenticated;
select pg_temp.login_as('super_auth');
select public.admin_mutate('user_status',pg_temp.fixture_id('provider_user'),
 public.admin_detail('users',pg_temp.fixture_id('provider_user'))->>'version',
 '{"active":false,"reason":"Regression provider account suspension"}');
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('suspended provider is removed from customer discovery',
 (select count(*)=0 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_assert('suspended provider service is removed from customer discovery',
 (select count(*)=0 from public.services where service_id=pg_temp.fixture_id('service')));
select pg_temp.login_as('super_auth');
select public.admin_mutate('user_status',pg_temp.fixture_id('provider_user'),
 public.admin_detail('users',pg_temp.fixture_id('provider_user'))->>'version',
 '{"active":true,"reason":"Regression provider account reactivation"}');
select public.admin_mutate('provider_verify',pg_temp.fixture_id('provider_profile'),
 public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'version',
 '{"status":"Rejected","reason":"Regression provider rejection review"}');
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('rejected provider service is removed from customer discovery',
 (select count(*)=0 from public.services where service_id=pg_temp.fixture_id('service')));
select pg_temp.login_as('super_auth');
select public.admin_mutate('provider_verify',pg_temp.fixture_id('provider_profile'),
 public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'version',
 '{"status":"Verified","reason":"Regression provider verification restored"}');
select public.admin_mutate('category_save',pg_temp.fixture_id('child_category'),
 public.admin_detail('categories',pg_temp.fixture_id('child_category'))->>'version',
 jsonb_build_object('name','__Admin Regression Child','active',false,'parent_id',pg_temp.fixture_id('root_category')));
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('inactive category service is removed from customer discovery',
 (select count(*)=0 from public.services where service_id=pg_temp.fixture_id('service')));
select pg_temp.login_as('super_auth');
select public.admin_mutate('category_save',pg_temp.fixture_id('child_category'),
 public.admin_detail('categories',pg_temp.fixture_id('child_category'))->>'version',
 jsonb_build_object('name','__Admin Regression Child','active',true,'parent_id',pg_temp.fixture_id('root_category')));
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('reactivation restores eligible service discovery',
 (select count(*)=1 from public.services where service_id=pg_temp.fixture_id('service')));
select pg_temp.login_as('super_auth');

-- Payment gating and attributed history are verified through real triggers.
select pg_temp.test_error('unpaid booking cannot be confirmed',
 'select public.admin_mutate(''booking_status'',pg_temp.fixture_id(''booking_unpaid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_unpaid''))->>''version'',''{"status":"Confirmed","reason":"Regression booking confirmation"}''::jsonb)','P0001','successful payment');
select pg_temp.test_error('pending booking cannot skip to completed',
 'select public.admin_mutate(''booking_status'',pg_temp.fixture_id(''booking_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->>''version'',''{"status":"Completed","reason":"Regression invalid transition"}''::jsonb)','P0001','transition');
select public.admin_mutate('booking_status',pg_temp.fixture_id('booking_paid'),
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->>'version',
 '{"status":"Confirmed","reason":"Regression booking confirmation"}');
select pg_temp.test_assert('paid booking confirms with acceptance timestamp',
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->>'booking_status'='Confirmed'
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->>'accepted_at' is not null);
select pg_temp.test_assert('booking history records administrator and reason',
 exists(select 1 from jsonb_array_elements(public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'history') h
 where h->>'new_status'='Confirmed' and h->>'changed_by'=pg_temp.fixture_id('super_user')::text
 and h->>'notes'='Regression booking confirmation'));
select public.admin_mutate('booking_status',pg_temp.fixture_id('booking_paid'),
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->>'version',
 '{"status":"Cancelled","reason":"Regression cancellation after payment"}');
select pg_temp.test_assert('cancelling a booking preserves collected payment state',
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'payment'->>'payment_status'='Success');

-- Administrative disputes have one active case, explicit transitions and attributed closure.
select public.admin_mutate('dispute_open',pg_temp.fixture_id('booking_paid'),
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->>'version',
 '{"subject":"Regression booking dispute","reason":"Regression disputed booking details"}');
select pg_temp.test_assert('dispute opening records administrator identity and open state',
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'status'='Open'
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'opened_by'=pg_temp.fixture_id('super_user')::text);
select pg_temp.test_error('booking has only one active dispute',
 'select public.admin_mutate(''dispute_open'',pg_temp.fixture_id(''booking_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->>''version'',''{"subject":"Duplicate regression dispute","reason":"Regression disputed booking details"}''::jsonb)','23505');
select pg_temp.test_error('dispute rejects null transition status',
 'select public.admin_mutate(''dispute_resolve'',(public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''disputes''->0->>''dispute_id'')::uuid,public.admin_detail(''disputes'',(public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''disputes''->0->>''dispute_id'')::uuid)->>''version'',''{"status":null,"reason":"Regression dispute resolution"}''::jsonb)','P0001','transition');
select public.admin_mutate('dispute_resolve',
 (public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'dispute_id')::uuid,
 public.admin_detail('disputes',(public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'dispute_id')::uuid)->>'version',
 '{"status":"Under Review","reason":"Regression dispute investigation"}');
select pg_temp.test_assert('dispute under review has no premature closure identity',
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'status'='Under Review'
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'resolved_at' is null);
select public.admin_mutate('dispute_resolve',
 (public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'dispute_id')::uuid,
 public.admin_detail('disputes',(public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'dispute_id')::uuid)->>'version',
 '{"status":"Resolved","reason":"Regression dispute resolution"}');
select pg_temp.test_assert('resolved dispute records resolution and responsible administrator',
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'status'='Resolved'
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'resolved_by'=pg_temp.fixture_id('super_profile')::text
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'resolution'='Regression dispute resolution'
 and public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'disputes'->0->>'resolved_at' is not null);
select pg_temp.test_error('resolved dispute cannot return to under review',
 'select public.admin_mutate(''dispute_resolve'',(public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''disputes''->0->>''dispute_id'')::uuid,public.admin_detail(''disputes'',(public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''disputes''->0->>''dispute_id'')::uuid)->>''version'',''{"status":"Under Review","reason":"Regression invalid reopening"}''::jsonb)','P0001','transition');

-- Refunds are requests, never fabricated gateway success. Totals cannot exceed paid funds.
select pg_temp.test_error('failed payment cannot be refunded',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_failed''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_unpaid''))->''payment''->>''version'',''{"amount":1,"reason":"Regression refund request"}''::jsonb)','P0001','successful payments');
select pg_temp.test_error('refund cannot exceed collected amount',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''payment''->>''version'',''{"amount":100.01,"reason":"Regression refund request"}''::jsonb)','P0001','remaining paid amount');
select pg_temp.test_error('refund rejects fractions of a sen',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''payment''->>''version'',''{"amount":1.001,"reason":"Regression refund request"}''::jsonb)','P0001','two decimal');
select public.admin_mutate('refund_request',pg_temp.fixture_id('payment_paid'),
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'payment'->>'version',
 '{"amount":40,"reason":"Regression partial refund request"}');
select pg_temp.test_assert('refund request is recorded as requested',
 exists(select 1 from jsonb_array_elements(public.admin_list('refunds','Regression partial refund request')->'items') r
 where r->>'payment_id'=pg_temp.fixture_id('payment_paid')::text and r->>'status'='Requested' and (r->>'amount')::numeric=40));
select pg_temp.test_error('only one pending refund is permitted',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''payment''->>''version'',''{"amount":10,"reason":"Regression duplicate refund"}''::jsonb)','23505');
reset role;
update public.refund_requests set status='Succeeded' where payment_id=pg_temp.fixture_id('payment_paid');
set local role authenticated;
select pg_temp.login_as('super_auth');
select pg_temp.test_error('succeeded refund reduces remaining refundable funds',
 'select public.admin_mutate(''refund_request'',pg_temp.fixture_id(''payment_paid''),public.admin_detail(''bookings'',pg_temp.fixture_id(''booking_paid''))->''payment''->>''version'',''{"amount":60.01,"reason":"Regression excessive total refund"}''::jsonb)','P0001','remaining paid amount');
select public.admin_mutate('refund_request',pg_temp.fixture_id('payment_paid'),
 public.admin_detail('bookings',pg_temp.fixture_id('booking_paid'))->'payment'->>'version',
 '{"amount":60,"reason":"Regression remaining refund request"}');

-- Moderation and DELETE must recalculate provider rating correctly.
select pg_temp.test_assert('visible reviews contribute rating average',
 (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'overall_rating')::numeric=4
 and (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'total_reviews')::integer=2);
select public.admin_mutate('review_moderate',pg_temp.fixture_id('review5'),
 public.admin_detail('reviews',pg_temp.fixture_id('review5'))->>'version',
 '{"decision":"hide","reason":"Regression review moderation"}');
select pg_temp.test_assert('hidden review is excluded from aggregate',
 (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'overall_rating')::numeric=3
 and (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'total_reviews')::integer=1);
select pg_temp.login_as('customer_auth');
select pg_temp.test_assert('hidden review is excluded from customer reads',
 (select count(*)=0 from public.reviews where review_id=pg_temp.fixture_id('review5')));
select pg_temp.login_as('super_auth');
select public.admin_mutate('review_moderate',pg_temp.fixture_id('review5'),
 public.admin_detail('reviews',pg_temp.fixture_id('review5'))->>'version',
 '{"decision":"dismiss","reason":"Regression review flag dismissal"}');
select pg_temp.test_assert('dismissed flag restores visible review aggregate',
 (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'overall_rating')::numeric=4
 and (public.admin_detail('providers',pg_temp.fixture_id('provider_profile'))->>'total_reviews')::integer=2);
reset role;
delete from public.reviews where review_id=pg_temp.fixture_id('review5');
select pg_temp.test_assert('review DELETE refreshes remaining rating',
 (select overall_rating=3 and total_reviews=1 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
delete from public.reviews where review_id=pg_temp.fixture_id('review3');
select pg_temp.test_assert('last review DELETE resets aggregate to zero',
 (select overall_rating=0 and total_reviews=0 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select pg_temp.test_assert('mutation queues notification without claiming email delivery',
 exists(select 1 from private.notification_outbox o join public.notifications n using(notification_id)
 where o.recipient_user_id=pg_temp.fixture_id('customer_user') and o.status='pending' and n.is_email_sent=false));
select pg_temp.test_assert('user audit excludes password hash values',
 not exists(select 1 from public.audit_logs where actor_id=pg_temp.fixture_id('super_user')
 and target_table='users' and (old_values ? 'password_hash' or new_values ? 'password_hash')));
select pg_temp.test_error('resolved dispute constraint rejects null resolution',
 'insert into public.booking_disputes(booking_id,opened_by,subject,description,status,resolved_by,resolved_at) values(pg_temp.fixture_id(''booking_paid''),pg_temp.fixture_id(''super_user''),''Regression invalid closure'',''Regression invalid closure detail'',''Resolved'',pg_temp.fixture_id(''super_profile''),now())','23514');

-- Reserved signup has no mobile profile; verified activation creates its admin profile.
insert into private.admin_invitations(email,role_level)
values('__admin_bootstrap_regression@example.invalid','super_admin');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(pg_temp.fixture_id('invitation_identity'),'00000000-0000-0000-0000-000000000000',
 'authenticated','authenticated','__admin_bootstrap_regression@example.invalid','',now(),
 '{"provider":"email","providers":["email"]}','{"role":"admin"}',now(),now());
select pg_temp.test_assert('invited signup does not create a customer profile',
 not exists(select 1 from public.users where auth_user_id=pg_temp.fixture_id('invitation_identity')));
set local role authenticated;
select pg_temp.login_as('invitation_identity','aal1');
select pg_temp.test_assert('verified invitation creates Super Admin profile',
 public.admin_identity()->>'role_level'='super_admin');
select pg_temp.test_assert('repeated invitation acceptance remains idempotent',
 public.admin_identity()->>'role_level'='super_admin');
select pg_temp.test_error('newly invited administrator still requires MFA for data access',
 'select public.admin_list(''users'')','42501','authenticator');
reset role;
select pg_temp.test_assert('invitation acceptance stores verified Auth identity',
 (select accepted_by=pg_temp.fixture_id('invitation_identity') and accepted_at is not null
 from private.admin_invitations where email='__admin_bootstrap_regression@example.invalid'));
select pg_temp.test_assert('invitation creates exactly one administrator profile',
 (select count(*)=1 from public.admin_profiles a join public.users u using(user_id)
 where u.auth_user_id=pg_temp.fixture_id('invitation_identity')));

select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as admin_regression_result
from pg_temp.admin_regression_results;
-- The caller MUST execute ROLLBACK after the result above.
