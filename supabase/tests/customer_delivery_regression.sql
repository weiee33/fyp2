-- Run after admin_regression.sql, customer_modules_regression.sql and customer_fpx_regression.sql, in a rolled-back transaction.
reset role;
select pg_temp.test_assert('delivery worker and secrets are inaccessible to clients',
 not has_function_privilege('authenticated','public.claim_deliveries(text)','execute')
 and not has_function_privilege('anon','public.delivery_configuration()','execute')
 and not has_function_privilege('authenticated','public.delivery_configuration()','execute')
 and not has_function_privilege('authenticated','public.gateway_record_payment_delivery(text,uuid,text,bigint,text,text,text,text,text,text)','execute'));
insert into auth.sessions(id,user_id) values('dddddddd-0000-4000-8000-000000000001',pg_temp.fixture_id('customer_auth'));
select pg_temp.login_as('customer_auth','aal1');
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb||'{"session_id":"dddddddd-0000-4000-8000-000000000001"}'::jsonb)::text,true);
set local role authenticated;
select public.customer_register_push(repeat('test-device-',8),'en');
select pg_temp.test_error('customers cannot read device tokens','select * from private.push_devices','42501');
reset role;
select pg_temp.test_assert('device uses app user and authenticated session',exists(select 1 from private.push_devices where user_id=pg_temp.fixture_id('customer_user') and session_id='dddddddd-0000-4000-8000-000000000001'));
create temporary table dispatch_before as select count(*) as requests from net.http_request_queue;
select private.customer_event(pg_temp.fixture_id('customer_user'),pg_temp.fpx_booking(),'Booking Update','Booking declined','Fixture only');
select pg_temp.test_assert('delivery enqueue schedules an immediate post-commit worker request',(select count(*) from net.http_request_queue)>(select requests from dispatch_before));
select pg_temp.test_assert('important booking event enqueued once per device',(select count(*)=1 from private.delivery_outbox where device_id=(select id from private.push_devices where token=repeat('test-device-',8))));
select private.customer_event(pg_temp.fixture_id('customer_user'),null,'System','Profile preferences updated','Fixture only');
select pg_temp.test_assert('routine profile changes do not create phone alerts',(select count(*)=1 from private.delivery_outbox where device_id=(select id from private.push_devices where token=repeat('test-device-',8))));
update public.notifications set is_read=true where notification_id in (select notification_id from private.delivery_outbox where device_id=(select id from private.push_devices where token=repeat('test-device-',8)));
create temporary table claimed_delivery as select value as job from jsonb_array_elements(public.claim_deliveries('push')) where value->>'token'=repeat('test-device-',8);
select pg_temp.test_assert('in-app read status does not suppress important phone delivery',(select count(*)=1 from claimed_delivery));
select pg_temp.test_assert('concurrent claims cannot duplicate active leases',not exists(select 1 from jsonb_array_elements(public.claim_deliveries('push')) where value->>'token'=repeat('test-device-',8)));
select public.finish_delivery((job->>'id')::uuid,gen_random_uuid(),'sent') from claimed_delivery;
select pg_temp.test_assert('stale worker cannot acknowledge another lease',(select state='sending' from private.delivery_outbox where id=(select (job->>'id')::uuid from claimed_delivery)));
select public.finish_delivery((job->>'id')::uuid,(job->>'lease_id')::uuid,'retry') from claimed_delivery;
select pg_temp.test_assert('failure has bounded delayed retry',(select state='pending' and attempts=1 and available_at>now() from private.delivery_outbox where id=(select (job->>'id')::uuid from claimed_delivery)));
select private.customer_event(pg_temp.fixture_id('customer_user'),pg_temp.fpx_booking(),'Booking Update','Booking requested','Fixture only');
select pg_temp.test_assert('new booking requests also enqueue a phone confirmation',exists(select 1 from private.delivery_outbox where device_id=(select id from private.push_devices where token=repeat('test-device-',8)) and payload->>'title'='Booking requested'));
delete from auth.sessions where id='dddddddd-0000-4000-8000-000000000001';
select pg_temp.test_assert('logout revocation removes device and queued alerts',not exists(select 1 from private.push_devices where token=repeat('test-device-',8)) and not exists(select 1 from private.delivery_outbox where id=(select (job->>'id')::uuid from claimed_delivery)));
select public.gateway_record_payment_delivery('evt_paid_fixture',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','paid','pi_fixture','fpx','customer@example.invalid','https://pay.stripe.com/receipts/payment/fixture');
select public.gateway_record_payment_delivery('evt_paid_fixture',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','paid','pi_fixture','fpx','customer@example.invalid','https://pay.stripe.com/receipts/payment/fixture');
select pg_temp.test_assert('payment replay yields only one immutable receipt email',(select count(*)=1 from private.delivery_outbox where kind='email' and payload->>'email'='customer@example.invalid'));
select pg_temp.test_assert('receipt queue preserves verified amount',(select (payload->>'amount_sen')::integer=18000 from private.delivery_outbox where kind='email' and payload->>'email'='customer@example.invalid'));
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) from pg_temp.admin_regression_results;
