-- Run after admin_regression.sql in the SAME transaction. Roll back all fixtures.
reset role;
insert into private.admin_invitations(email) select email from auth.users where id=pg_temp.fixture_id('customer_auth');
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('canonical account identity ignores edited metadata',public.account_identity()->>'role'='customer');
select pg_temp.test_assert('canonical user ID can differ from Auth ID',public.account_identity()->>'user_id'=pg_temp.fixture_id('customer_user')::text);
select pg_temp.test_error('inviting an existing customer cannot convert their role','select public.admin_identity()','42501');
select pg_temp.test_assert('first address automatically becomes default',
 (public.customer_save_address('Home','10 Test Street','Kuala Lumpur','WP Kuala Lumpur','50000',3.14,101.69,false)->>'is_default')::boolean);
select pg_temp.test_assert('new default address is saved atomically',
 (public.customer_save_address('Work','20 Test Street','Kuala Lumpur','WP Kuala Lumpur','50000',3.15,101.70,true)->>'is_default')::boolean);
select pg_temp.test_assert('only one default address exists',
 (select count(*)=1 from public.saved_addresses where customer_id=(public.account_identity()->>'customer_id')::uuid and is_default));
select pg_temp.test_assert('address header matches selected default',
 (select default_address like '20 Test Street%' from public.customer_profiles where user_id=pg_temp.fixture_id('customer_user')));
select pg_temp.test_error('unknown address cannot change default',
 $$select public.customer_set_default_address('ffffffff-eeee-4000-8000-000000000099')$$,'42501');
select pg_temp.test_error('invalid coordinates rejected',
 $$select public.customer_save_address('Home','Test Street','KL','WP','50000',999,101,false)$$,'P0001');
select pg_temp.test_assert('failed change preserves the current default',
 (select count(*)=1 from public.saved_addresses where is_default));
select pg_temp.test_assert('customer directory is an array',jsonb_typeof(public.customer_provider_directory())='array');
select pg_temp.login_as('provider_auth','aal1');
select pg_temp.test_error('provider cannot mutate customer addresses',
 $$select public.customer_save_address('Home','Test Street','KL','WP','50000',3,101,false)$$,'42501');
reset role;
update public.users set is_active=false where user_id=pg_temp.fixture_id('customer_user');
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_error('suspended account identity is denied','select public.account_identity()','42501');
select pg_temp.test_error('suspended account address writes denied',
 $$select public.customer_save_address('Home','Test Street','KL','WP','50000',3,101,false)$$,'42501');
reset role;
update public.users set is_active=true where user_id=pg_temp.fixture_id('customer_user');
select pg_temp.test_error('nonpositive service duration rejected',
 $$update public.services set estimated_duration=0 where service_id=pg_temp.fixture_id('service')$$,'23514');
select pg_temp.test_assert('exactly one rating trigger remains',
 (select count(*)=1 from pg_trigger where tgrelid='public.reviews'::regclass and not tgisinternal));
select pg_temp.test_assert('Auth signup uses the canonical identity trigger',
 exists(select 1 from pg_trigger where tgrelid='auth.users'::regclass and tgname='on_auth_user_created' and tgfoid='private.handle_new_auth_user()'::regprocedure));
insert into public.users(user_id,email,full_name,role) values
 ('ffffffff-dddd-4000-8000-000000000001','__other_customer@example.invalid','Other Customer','customer'),
 ('ffffffff-dddd-4000-8000-000000000002','__other_provider@example.invalid','Other Provider','provider');
insert into public.customer_profiles(customer_id,user_id) values('ffffffff-dddd-4000-8000-000000000011','ffffffff-dddd-4000-8000-000000000001');
insert into public.provider_profiles(provider_id,user_id,business_name) values('ffffffff-dddd-4000-8000-000000000012','ffffffff-dddd-4000-8000-000000000002','Other Provider');
select pg_temp.test_error('booking cannot select another service provider',
 $$update public.bookings set provider_id='ffffffff-dddd-4000-8000-000000000012' where booking_id=pg_temp.fixture_id('booking_unpaid')$$,'23503');
select pg_temp.test_error('payment cannot name another customer',
 $$update public.payments set customer_id='ffffffff-dddd-4000-8000-000000000011' where payment_id=pg_temp.fixture_id('payment_paid')$$,'23503');
select pg_temp.test_error('review cannot name another customer',
 $$insert into public.reviews(booking_id,customer_id,provider_id,rating_score) values(pg_temp.fixture_id('booking_unpaid'),'ffffffff-dddd-4000-8000-000000000011',pg_temp.fixture_id('provider_profile'),5)$$,'23503');
select pg_temp.test_error('earnings cannot name another provider',
 $$insert into public.provider_earnings(provider_id,booking_id,gross_amount) values('ffffffff-dddd-4000-8000-000000000012',pg_temp.fixture_id('booking_unpaid'),10)$$,'23503');
select pg_temp.test_error('earnings fee cannot exceed amount',
 $$insert into public.provider_earnings(provider_id,booking_id,gross_amount,platform_fee) values(pg_temp.fixture_id('provider_profile'),pg_temp.fixture_id('booking_unpaid'),10,11)$$,'23514');
select pg_temp.test_error('working hours cannot end before start',
 $$insert into public.provider_working_hours(provider_id,day_of_week,start_time,end_time) values('ffffffff-dddd-4000-8000-000000000012',0,'17:00','09:00')$$,'23514');
set local role anon;
select pg_temp.test_error('anonymous account identity rejected','select public.account_identity()','42501');
select pg_temp.test_error('anonymous address writes rejected',
 $$select public.customer_save_address('Home','Test Street','KL','WP','50000',3,101,false)$$,'42501');
select pg_temp.test_error('noninvited registration rejected',
 $$select public.admin_registration_check('not-invited@example.invalid')$$,'42501');
reset role;
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as auth_customer_regression_result from pg_temp.admin_regression_results;
