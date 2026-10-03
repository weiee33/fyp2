-- Run after the existing four regression files, in the SAME rolled-back transaction.
reset role;
update public.users set is_active=true where user_id in (pg_temp.fixture_id('customer_user'),pg_temp.fixture_id('provider_user'));
update public.provider_profiles set verification_status='Verified',city='Regression City' where provider_id=pg_temp.fixture_id('provider_profile');
update public.services set is_active=true,availability_status=true,service_name='Customer module fixture',pricing_type='Hourly',base_price=120,estimated_duration=90 where service_id=pg_temp.fixture_id('service');
update public.service_categories set is_active=true where category_id in (pg_temp.fixture_id('root_category'),pg_temp.fixture_id('child_category'));
insert into public.provider_working_hours(provider_id,day_of_week,start_time,end_time,is_active)
select pg_temp.fixture_id('provider_profile'),day,'09:00','18:00',true from generate_series(0,6) day
on conflict(provider_id,day_of_week) do update set start_time='09:00',end_time='18:00',is_active=true;
create temporary table customer_module_ids(name text primary key,id uuid) on commit drop;
grant select,insert on customer_module_ids to authenticated;
insert into public.saved_addresses(address_id,customer_id,label,address_line,city,state,postcode,coordinates)
values('eeeeeeee-0000-4000-8000-000000000001',pg_temp.fixture_id('customer_profile'),'Regression','123 Original Street','Regression City','Selangor','50000','3,101');
create function pg_temp.module_booking() returns uuid language sql stable as $$ select id from customer_module_ids where name='booking' $$;
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('customer search returns safe service projection with hourly quote',
 (public.customer_search_services(p_keyword=>'Customer module fixture')->0->>'quoted_amount')::numeric=180
 and not (public.customer_search_services(p_keyword=>'Customer module fixture')->0 ? 'business_license'));
select pg_temp.test_assert('customer city filter is real',jsonb_array_length(public.customer_search_services(p_city=>'Not a city'))=0);
select pg_temp.test_assert('provider detail hides licence and credential file paths',
 not (public.customer_provider_details(pg_temp.fixture_id('provider_profile')) ? 'business_license')
 and not coalesce(public.customer_provider_details(pg_temp.fixture_id('provider_profile'))->'certifications'->0 ? 'file_url',false));
select public.customer_profile_update('Customer module test','+6000000099999',array['Cleaning']);
select pg_temp.test_assert('customer profile and preferences update together',
 (select full_name='Customer module test' from public.users where user_id=pg_temp.fixture_id('customer_user'))
 and (select service_preferences=array['Cleaning'] from public.customer_profiles where customer_id=pg_temp.fixture_id('customer_profile')));
select pg_temp.test_error('profile cannot persist another account image',
 $$select public.customer_profile_update('Bad image','+6000000099999',array['Cleaning'],'https://evil.invalid/storage/v1/object/public/profiles/other/avatars/file.jpg')$$,'42501');
select pg_temp.test_assert('availability uses working hours and service duration',
 jsonb_array_length(public.customer_booking_slots(pg_temp.fixture_id('service'),(now() at time zone 'Asia/Kuala_Lumpur')::date+2))=16);
insert into customer_module_ids values('booking',(public.customer_create_booking(pg_temp.fixture_id('service'),
 'eeeeeeee-0000-4000-8000-000000000001',(now() at time zone 'Asia/Kuala_Lumpur')::date+2,'09:00','Regression booking instructions','Medium',
 'eeeeeeee-0000-4000-8000-000000000002')->>'booking_id')::uuid);
select pg_temp.test_assert('new request derives price and denies payment before provider approval',
 (public.customer_booking_detail(pg_temp.module_booking())->>'total_amount')::numeric=180
 and public.customer_booking_detail(pg_temp.module_booking())->>'can_pay'='false'
 and public.customer_booking_detail(pg_temp.module_booking())->>'booking_status'='Pending');
select pg_temp.test_assert('booking retry returns the original identity',
 public.customer_create_booking(pg_temp.fixture_id('service'),'eeeeeeee-0000-4000-8000-000000000001',
 (now() at time zone 'Asia/Kuala_Lumpur')::date+2,'09:00','Regression booking instructions','Medium','eeeeeeee-0000-4000-8000-000000000002')->>'booking_id'=pg_temp.module_booking()::text);
select pg_temp.test_error('overlapping provider reservation is rejected',
 $$select public.customer_create_booking(pg_temp.fixture_id('service'),'eeeeeeee-0000-4000-8000-000000000001',(now() at time zone 'Asia/Kuala_Lumpur')::date+2,'09:30',null,'Medium','eeeeeeee-0000-4000-8000-000000000003')$$,'23P01');
select pg_temp.test_assert('reserved slots disappear from availability',
 not exists(select 1 from jsonb_array_elements(public.customer_booking_slots(pg_temp.fixture_id('service'),(now() at time zone 'Asia/Kuala_Lumpur')::date+2)) slot where slot->>'scheduled_time' in ('09:00:00','09:30:00','10:00:00')));
select pg_temp.test_error('unpaid booking has no receipt',
 'select public.customer_booking_receipt(pg_temp.module_booking())','P0001');
select pg_temp.test_assert('pending booking is not reviewable',not public.customer_review_eligibility(pg_temp.module_booking()));
select pg_temp.test_error('customer cannot approve its own slot',
 'select public.provider_booking_reply(pg_temp.module_booking(),true)','42501');
select pg_temp.login_as('provider_auth','aal1');
select pg_temp.test_error('provider cannot use customer APIs','select public.customer_bookings()','42501');
select public.provider_booking_reply(pg_temp.module_booking(),true);
select pg_temp.test_error('provider cannot start service before payment',
 $$select public.provider_booking_progress(pg_temp.module_booking(),'In-Progress')$$,'P0001');
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('provider approval unlocks payment without fabricating success',
 public.customer_booking_detail(pg_temp.module_booking())->>'can_pay'='true'
 and public.customer_booking_detail(pg_temp.module_booking())->>'booking_status'='Confirmed'
 and public.customer_booking_detail(pg_temp.module_booking())->'payment'='null'::jsonb);
select pg_temp.test_error('customer cannot write a paid record directly',
 $$insert into public.payments(booking_id,customer_id,payment_amount,payment_status) values(pg_temp.module_booking(),pg_temp.fixture_id('customer_profile'),1,'Success')$$,'42501');
select public.customer_delete_address('eeeeeeee-0000-4000-8000-000000000001');
select pg_temp.test_assert('deleting an address preserves the booking address snapshot',
 public.customer_booking_detail(pg_temp.module_booking())->>'customer_address' like '123 Original Street%');
select pg_temp.test_assert('booking events are visible in the customer inbox',
 (select count(*)>=2 from public.notifications where booking_id=pg_temp.module_booking()));
select public.customer_notification_dismiss((select notification_id from public.notifications where booking_id=pg_temp.module_booking() order by created_at limit 1));
select pg_temp.test_assert('notification dismissal persists',
 exists(select 1 from public.notifications where booking_id=pg_temp.module_booking() and dismissed_at is not null and is_read));
reset role;
-- Trusted payment fixture, never a client payment or external gateway call.
insert into public.payments(booking_id,customer_id,payment_amount,payment_status,escrow_held)
values(pg_temp.module_booking(),pg_temp.fixture_id('customer_profile'),180,'Success',false);
update public.bookings set booking_status='Completed',completed_at=now(),reservation_expires_at=null where booking_id=pg_temp.module_booking();
set local role authenticated;
select pg_temp.login_as('customer_auth','aal1');
select pg_temp.test_assert('completed paid booking enables a verified review',public.customer_review_eligibility(pg_temp.module_booking()));
select public.customer_submit_review(pg_temp.module_booking(),5,'The service was completed as requested.');
select pg_temp.test_assert('submitted review is included in customer history',
 exists(select 1 from jsonb_array_elements(public.customer_my_reviews()) r where r->>'booking_id'=pg_temp.module_booking()::text and r->>'rating_score'='5'));
select pg_temp.test_error('duplicate review is rejected even after moderation',
 $$select public.customer_submit_review(pg_temp.module_booking(),1,'Duplicate review')$$,'P0001');
select pg_temp.test_assert('receipt uses stored payment rather than caller amounts',
 (public.customer_booking_receipt(pg_temp.module_booking())->'payment'->>'payment_amount')::numeric=180);
select public.customer_open_dispute(pg_temp.module_booking(),'Service quality concern','Please review the service outcome and assist with this booking.');
select pg_temp.test_assert('customer dispute is linked to booking detail',
 jsonb_array_length(public.customer_booking_detail(pg_temp.module_booking())->'disputes')=1);
select pg_temp.login_as('provider_auth','aal1');
select pg_temp.test_error('provider cannot fetch customer receipt','select public.customer_booking_receipt(pg_temp.module_booking())','42501');
reset role;
select pg_temp.test_assert('review updates the provider rating aggregate',
 (select total_reviews=1 and overall_rating=5 from public.provider_profiles where provider_id=pg_temp.fixture_id('provider_profile')));
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as customer_modules_result from pg_temp.admin_regression_results;
