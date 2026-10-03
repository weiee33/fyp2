-- Run after customer_modules_regression.sql in the same rolled-back transaction.
reset role;
insert into public.saved_addresses(address_id,customer_id,label,address_line,city,state,postcode,coordinates)
values('eeeeeeee-0000-4000-8000-000000000011',pg_temp.fixture_id('customer_profile'),'FPX','123 Test Street','Regression City','Selangor','50000','3,101');
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
insert into customer_module_ids values('fpx_booking',(public.customer_create_booking(pg_temp.fixture_id('service'),
 'eeeeeeee-0000-4000-8000-000000000011',(now() at time zone 'Asia/Kuala_Lumpur')::date+3,'09:00',null,'Medium',
 'eeeeeeee-0000-4000-8000-000000000012')->>'booking_id')::uuid);
create function pg_temp.fpx_booking() returns uuid language sql stable as $$select id from customer_module_ids where name='fpx_booking'$$;
create function pg_temp.fpx_attempt() returns uuid language sql stable as $$select id from customer_module_ids where name='fpx_attempt'$$;
select pg_temp.test_error('checkout rejects payment before provider acceptance','select public.customer_prepare_checkout(pg_temp.fpx_booking())','P0001');
select pg_temp.login_as('provider_auth','aal1');
select public.provider_booking_reply(pg_temp.fpx_booking(),true);
select pg_temp.test_error('provider cannot pay for customer','select public.customer_prepare_checkout(pg_temp.fpx_booking())','42501');
select pg_temp.login_as('customer_auth','aal1');
insert into customer_module_ids values('fpx_attempt',(public.customer_prepare_checkout(pg_temp.fpx_booking())->>'attempt_id')::uuid);
select pg_temp.test_assert('checkout retry reuses authoritative quote and identity',
 public.customer_prepare_checkout(pg_temp.fpx_booking())->>'attempt_id'=pg_temp.fpx_attempt()::text
 and (public.customer_prepare_checkout(pg_temp.fpx_booking())->>'amount_sen')::integer=18000);
select pg_temp.test_error('customer cannot call privileged gateway writer',
 $$select public.gateway_record_payment('evt_fake',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','paid','pi_fixture')$$,'42501');
reset role;
select public.gateway_attach_checkout(pg_temp.fpx_attempt(),'cs_test_fixture','https://checkout.stripe.com/c/pay/cs_test_fixture',
 (select expires_at from private.checkout_attempts where attempt_id=pg_temp.fpx_attempt()));
select pg_temp.test_error('payment rejects changed amount',
 $$select public.gateway_record_payment('evt_bad_amount',pg_temp.fpx_attempt(),'cs_test_fixture',1,'myr','paid','pi_fixture')$$,'P0001');
select pg_temp.test_error('payment rejects wrong currency',
 $$select public.gateway_record_payment('evt_bad_currency',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'usd','paid','pi_fixture')$$,'P0001');
select pg_temp.test_error('payment rejects another checkout session',
 $$select public.gateway_record_payment('evt_bad_session',pg_temp.fpx_attempt(),'cs_test_other',18000,'myr','paid','pi_fixture')$$,'P0001');
select public.gateway_record_payment('evt_paid_fixture',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','paid','pi_fixture');
select pg_temp.test_assert('duplicate callback is idempotent',
 public.gateway_record_payment('evt_paid_fixture',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','paid','pi_fixture')->>'duplicate'='true');
select public.gateway_record_payment('evt_expired_after_paid',pg_temp.fpx_attempt(),'cs_test_fixture',18000,'myr','expired',null);
select pg_temp.test_assert('out of order expiry never reverses a verified payment',
 (select payment_status='Success' and payment_amount=180 and escrow_held=false from public.payments where booking_id=pg_temp.fpx_booking())
 and (select state='Paid' from private.checkout_attempts where attempt_id=pg_temp.fpx_attempt()));
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('verified callback unlocks receipt and closes checkout',
 public.customer_booking_receipt(pg_temp.fpx_booking())->'payment'->>'payment_status'='Success'
 and public.customer_booking_detail(pg_temp.fpx_booking())->>'can_pay'='false');
select pg_temp.test_error('paid booking cannot open another checkout','select public.customer_prepare_checkout(pg_temp.fpx_booking())','P0001');
select public.customer_cancel_booking(pg_temp.fpx_booking(),'Cannot attend the accepted appointment');
select pg_temp.test_assert('paid cancellation opens refund review without claiming a refund',
 public.customer_booking_detail(pg_temp.fpx_booking())->>'booking_status'='Cancelled'
 and public.customer_booking_detail(pg_temp.fpx_booking())->'payment'->>'payment_status'='Success'
 and jsonb_array_length(public.customer_booking_detail(pg_temp.fpx_booking())->'disputes')=1);
insert into customer_module_ids values('late_booking',(public.customer_create_booking(pg_temp.fixture_id('service'),
 'eeeeeeee-0000-4000-8000-000000000011',(now() at time zone 'Asia/Kuala_Lumpur')::date+4,'09:00',null,'Medium',
 'eeeeeeee-0000-4000-8000-000000000013')->>'booking_id')::uuid);
create function pg_temp.late_booking() returns uuid language sql stable as $$select id from customer_module_ids where name='late_booking'$$;
create function pg_temp.late_attempt() returns uuid language sql stable as $$select id from customer_module_ids where name='late_attempt'$$;
select pg_temp.login_as('provider_auth','aal1');
select public.provider_booking_reply(pg_temp.late_booking(),true);
select pg_temp.login_as('customer_auth','aal1');
insert into customer_module_ids values('late_attempt',(public.customer_prepare_checkout(pg_temp.late_booking())->>'attempt_id')::uuid);
select public.customer_cancel_booking(pg_temp.late_booking(),'Cancelled before paying');
reset role;
select public.gateway_attach_checkout(pg_temp.late_attempt(),'cs_test_late','https://checkout.stripe.com/c/pay/cs_test_late',
 (select expires_at from private.checkout_attempts where attempt_id=pg_temp.late_attempt()));
select public.gateway_record_payment('evt_late_fixture',pg_temp.late_attempt(),'cs_test_late',18000,'myr','paid','pi_late_fixture');
select pg_temp.test_assert('late payment preserves cancelled slot and opens reconciliation',
 (select booking_status='Cancelled' from public.bookings where booking_id=pg_temp.late_booking())
 and (select count(*)=1 from public.booking_disputes where booking_id=pg_temp.late_booking())
 and (select payment_status='Success' from public.payments where booking_id=pg_temp.late_booking()));
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as customer_fpx_result from pg_temp.admin_regression_results;
