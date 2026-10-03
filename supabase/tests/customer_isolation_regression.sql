-- Run after customer_fpx_regression.sql. Always roll back all synthetic fixtures.
reset role;
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('eeeeeeee-0000-4000-8000-000000000021','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 '__customer_isolation@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{"role":"customer"}',now(),now());
set local role authenticated;
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000021',true);
select set_config('request.jwt.claims','{"sub":"eeeeeeee-0000-4000-8000-000000000021","role":"authenticated","aal":"aal1"}',true);
select pg_temp.test_assert('another customer sees no bookings',jsonb_array_length(public.customer_bookings())=0);
select pg_temp.test_error('another customer cannot read booking','select public.customer_booking_detail(pg_temp.fpx_booking())','42501');
select pg_temp.test_error('another customer cannot cancel booking', $$select public.customer_cancel_booking(pg_temp.fpx_booking(),'Other customer')$$,'42501');
select pg_temp.test_error('another customer cannot obtain receipt','select public.customer_booking_receipt(pg_temp.fpx_booking())','42501');
select pg_temp.test_error('another customer cannot start checkout','select public.customer_prepare_checkout(pg_temp.fpx_booking())','42501');
select pg_temp.test_error('customer cannot release payment attempt','select public.gateway_reject_checkout(pg_temp.fpx_attempt())','42501');
select pg_temp.test_error('another customer cannot delete saved address', $$select public.customer_delete_address('eeeeeeee-0000-4000-8000-000000000011')$$,'42501');
select pg_temp.login_as('provider_auth','aal1');
select pg_temp.test_assert('provider list joins return booking detail without ambiguous IDs',
 public.provider_booking_list(p_booking_id=>pg_temp.fpx_booking())->0->>'booking_id'=pg_temp.fpx_booking()::text);
reset role;
select public.gateway_reject_checkout(pg_temp.fpx_attempt());
select pg_temp.test_assert('checkout rejection cannot reverse a paid attempt',
 (select state='Paid' from private.checkout_attempts where attempt_id=pg_temp.fpx_attempt()));
insert into private.checkout_attempts(booking_id,amount_sen,expires_at)
values(pg_temp.fpx_booking(),18000,now()+interval '31 minutes');
select public.gateway_reject_checkout(attempt_id) from private.checkout_attempts where booking_id=pg_temp.fpx_booking() and state='Creating';
select pg_temp.test_assert('definitive creation rejection releases the retry slot',
 not exists(select 1 from private.checkout_attempts where booking_id=pg_temp.fpx_booking() and state='Creating'));
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as customer_isolation_result from pg_temp.admin_regression_results;
