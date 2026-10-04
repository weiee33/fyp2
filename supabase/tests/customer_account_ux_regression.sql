-- Append to the existing eight regression suites; always roll back fixtures.
reset role;
create temporary table ux_ids(name text primary key,id uuid not null) on commit drop;
insert into ux_ids values('auth',gen_random_uuid()),('notification',gen_random_uuid()),('other_notification',gen_random_uuid());
grant select on ux_ids to authenticated,service_role;
create function pg_temp.ux_id(p_name text) returns uuid language sql stable as $$select id from pg_temp.ux_ids where name=p_name$$;
grant execute on function pg_temp.ux_id(text) to authenticated,service_role;
insert into public.notifications(notification_id,user_id,notification_type,title,message) values
 (pg_temp.ux_id('notification'),pg_temp.fixture_id('customer_user'),'System','UX fixture','Own'),
 (pg_temp.ux_id('other_notification'),pg_temp.fixture_id('provider_user'),'System','UX fixture','Other');
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select public.customer_notification_pin(pg_temp.ux_id('notification'),true);
select pg_temp.test_assert('notification pin persists', (select is_pinned from public.notifications where notification_id=pg_temp.ux_id('notification')));
select pg_temp.test_error('cannot pin another account notification',$$select public.customer_notification_pin(pg_temp.ux_id('other_notification'),true)$$,'42501');
select public.customer_notification_pin(pg_temp.ux_id('notification'),false);
select pg_temp.test_assert('notification unpin persists',not(select is_pinned from public.notifications where notification_id=pg_temp.ux_id('notification')));
select public.customer_notification_dismiss(pg_temp.ux_id('notification'));
select pg_temp.test_error('cannot pin a deleted notification',$$select public.customer_notification_pin(pg_temp.ux_id('notification'),true)$$,'42501');
select pg_temp.test_error('client cannot delete arbitrary auth account',$$select public.customer_delete_prepare(pg_temp.ux_id('auth'))$$,'42501');
select pg_temp.test_error('client cannot inspect storage cleanup',$$select public.customer_delete_objects(pg_temp.ux_id('auth'))$$,'42501');
select pg_temp.test_error('client cannot consume geocoder slots',$$select public.customer_geocode_claim('x')$$,'42501');
reset role;
select pg_temp.test_error('active bookings block account deletion',$$select public.customer_delete_prepare(pg_temp.fixture_id('customer_auth'))$$,'P0001');
select pg_temp.test_error('provider deletion rejected',$$select public.customer_delete_prepare(pg_temp.fixture_id('provider_auth'))$$,'42501');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(pg_temp.ux_id('auth'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',pg_temp.ux_id('auth')||'@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{"role":"customer","full_name":"Delete fixture"}',now(),now());
insert into public.saved_addresses(customer_id,label,address_line,city,state,postcode,is_default)
select customer_id,'Home','Delete this address','Test','Test','50000',true from public.customer_profiles where user_id=pg_temp.ux_id('auth');
set local role service_role;
select public.customer_delete_prepare(pg_temp.ux_id('auth'));
select public.customer_delete_prepare(pg_temp.ux_id('auth')); -- retry is safe
reset role;
select pg_temp.test_assert('deletion detaches and anonymizes canonical identity', (select auth_user_id is null and is_active=false and phone is null and full_name='Deleted customer' and email like '%@deleted.invalid' from public.users where user_id=pg_temp.ux_id('auth')));
select pg_temp.test_assert('deletion removes saved addresses',not exists(select 1 from public.saved_addresses a join public.customer_profiles c using(customer_id) where c.user_id=pg_temp.ux_id('auth')));
set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.ux_id('auth')::text,true);
select set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.ux_id('auth'),'role','authenticated','aal','aal1')::text,true);
select pg_temp.test_error('old JWT cannot regain account access','select public.account_identity()','42501');
select pg_temp.test_error('old JWT cannot use customer RPC','select public.customer_bookings()','42501');
reset role;
select pg_temp.test_error('cannot finish before Auth removal',$$select public.customer_delete_finish(pg_temp.ux_id('auth'))$$,'P0001');
-- Simulate the Auth Admin API's deletion inside this transaction; never delete a real user.
delete from auth.users where id=pg_temp.ux_id('auth');
select public.customer_delete_finish(pg_temp.ux_id('auth'));
select pg_temp.test_assert('Auth user removed',not exists(select 1 from auth.users where id=pg_temp.ux_id('auth')));
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(gen_random_uuid(),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',pg_temp.ux_id('auth')||'@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{"role":"customer"}',now(),now());
select pg_temp.test_assert('same email requires and permits a fresh identity',(select count(*)=1 from public.users where email=pg_temp.ux_id('auth')||'@example.invalid' and auth_user_id<>pg_temp.ux_id('auth') and is_active));
update private.customer_geocode_gate set next_at=now()-interval '1 second';
select pg_temp.test_assert('geocoder first request allowed',(public.customer_geocode_claim('fixture:1')->>'allowed')::boolean);
select pg_temp.test_assert('geocoder shared gate throttles next request',not(public.customer_geocode_claim('fixture:2')->>'allowed')::boolean);
select public.customer_geocode_store('fixture:1','{"value":{"city":"Test"}}');
select pg_temp.test_assert('geocoder cache avoids upstream request',public.customer_geocode_claim('fixture:1')->'cached'->'value'->>'city'='Test');
