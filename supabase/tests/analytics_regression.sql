-- Run AFTER admin_regression.sql in the same owner transaction; always ROLLBACK.
-- Adds isolated category/provider fixtures with fixed dates to test date boundaries.
reset role;
create temporary table analytics_regression_ids(fixture_name text primary key,fixture_id uuid unique not null) on commit drop;
insert into analytics_regression_ids values
 ('auth_a','fffffffe-0000-4000-8000-000000000001'),
 ('auth_b','fffffffe-0000-4000-8000-000000000002'),
 ('category_root','fffffffe-3000-4000-8000-000000000001'),
 ('category_child','fffffffe-3000-4000-8000-000000000002'),
 ('category_other','fffffffe-3000-4000-8000-000000000003'),
 ('service_a','fffffffe-4000-4000-8000-000000000001'),
 ('service_b','fffffffe-4000-4000-8000-000000000002'),
 ('service_other','fffffffe-4000-4000-8000-000000000003'),
 ('booking_1','fffffffe-5000-4000-8000-000000000001'),
 ('booking_2','fffffffe-5000-4000-8000-000000000002'),
 ('booking_3','fffffffe-5000-4000-8000-000000000003'),
 ('booking_4','fffffffe-5000-4000-8000-000000000004'),
 ('booking_5','fffffffe-5000-4000-8000-000000000005'),
 ('booking_6','fffffffe-5000-4000-8000-000000000006'),
 ('booking_7','fffffffe-5000-4000-8000-000000000007'),
 ('booking_8','fffffffe-5000-4000-8000-000000000008'),
 ('payment_1','fffffffe-6000-4000-8000-000000000001'),
 ('payment_2','fffffffe-6000-4000-8000-000000000002'),
 ('payment_3','fffffffe-6000-4000-8000-000000000003'),
 ('payment_4','fffffffe-6000-4000-8000-000000000004'),
 ('payment_5','fffffffe-6000-4000-8000-000000000005'),
 ('payment_6','fffffffe-6000-4000-8000-000000000006'),
 ('payment_7','fffffffe-6000-4000-8000-000000000007'),
 ('payment_8','fffffffe-6000-4000-8000-000000000008'),
 ('review_1','fffffffe-7000-4000-8000-000000000001'),
 ('review_2','fffffffe-7000-4000-8000-000000000002'),
 ('review_3','fffffffe-7000-4000-8000-000000000003');
create function pg_temp.analytics_id(fixture text) returns uuid language sql stable security invoker set search_path='' as $$
 select fixture_id from pg_temp.analytics_regression_ids where fixture_name=fixture
$$;
grant select on pg_temp.analytics_regression_ids to authenticated,anon;
grant execute on function pg_temp.analytics_id(text) to authenticated,anon;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
select fixture_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 '__analytics_regression_'||fixture_name||'@example.invalid','',now(),
 '{"provider":"email","providers":["email"]}','{"role":"provider","full_name":"Analytics regression provider"}',now(),now()
from pg_temp.analytics_regression_ids where fixture_name in ('auth_a','auth_b');
update public.provider_profiles set business_name='__Analytics Klang Provider',region='Klang Valley',verification_status='Verified'
where user_id=pg_temp.analytics_id('auth_a');
update public.provider_profiles set business_name='__Analytics Penang Provider',region='Penang',verification_status='Verified'
where user_id=pg_temp.analytics_id('auth_b');
insert into analytics_regression_ids
select 'provider_a',provider_id from public.provider_profiles where user_id=pg_temp.analytics_id('auth_a')
union all
select 'provider_b',provider_id from public.provider_profiles where user_id=pg_temp.analytics_id('auth_b');
insert into public.service_categories(category_id,category_name,parent_category_id) values
 (pg_temp.analytics_id('category_root'),'__Analytics Regression Parent',null),
 (pg_temp.analytics_id('category_child'),'__Analytics Regression Child',pg_temp.analytics_id('category_root')),
 (pg_temp.analytics_id('category_other'),'__Analytics Regression Other',null);
insert into public.services(service_id,provider_id,category_id,service_name,description,base_price) values
 (pg_temp.analytics_id('service_a'),pg_temp.analytics_id('provider_a'),pg_temp.analytics_id('category_child'),'__Analytics Service A','Synthetic analytics fixture',100),
 (pg_temp.analytics_id('service_b'),pg_temp.analytics_id('provider_b'),pg_temp.analytics_id('category_child'),'__Analytics Service B','Synthetic analytics fixture',200),
 (pg_temp.analytics_id('service_other'),pg_temp.analytics_id('provider_a'),pg_temp.analytics_id('category_other'),'__Analytics Other Service','Synthetic analytics fixture',300);

insert into public.bookings(booking_id,customer_id,provider_id,service_id,booking_date,scheduled_time,scheduled_datetime,customer_address,total_amount,booking_status,created_at)
select pg_temp.analytics_id('booking_'||x.n),pg_temp.fixture_id('customer_profile'),
 case when x.n=3 then pg_temp.analytics_id('provider_b') else pg_temp.analytics_id('provider_a') end,
 case when x.n=3 then pg_temp.analytics_id('service_b') when x.n=4 then pg_temp.analytics_id('service_other') else pg_temp.analytics_id('service_a') end,
 '2025-01-03','10:00:00','2025-01-03 10:00:00+08','Synthetic analytics fixture address',x.amount,x.status::public.booking_status,x.created_at::timestamptz
from(values
 (1,100,'Completed','2024-12-31 16:00:00+00'), -- Jan 1 exactly at KL midnight: included.
 (2,50,'Completed','2025-01-01 10:00:00+00'),
 (3,200,'Completed','2025-01-01 02:00:00+00'),
 (4,300,'Completed','2025-01-01 03:00:00+00'),
 (5,90,'Pending','2025-01-01 16:00:00+00'), -- Jan 2 exactly at KL midnight: excluded from Jan 1.
 (6,70,'Completed','2024-12-31 15:59:59+00'), -- Booking is outside Jan 1; receipt below is inside.
 (7,80,'Pending','2025-01-01 04:00:00+00'),
 (8,60,'Cancelled','2025-01-01 05:00:00+00')
)x(n,amount,status,created_at);
insert into public.payments(payment_id,booking_id,customer_id,payment_amount,payment_status,payment_timestamp,created_at)
select pg_temp.analytics_id('payment_'||x.n),pg_temp.analytics_id('booking_'||x.n),pg_temp.fixture_id('customer_profile'),
 x.amount,x.status::public.payment_status,x.received_at::timestamptz,x.received_at::timestamptz
from(values
 (1,100,'Success','2024-12-31 16:00:00+00'),
 (2,50,'Refunded','2025-01-01 10:00:00+00'),
 (3,200,'Success','2025-01-01 02:00:00+00'),
 (4,300,'Success','2025-01-01 03:00:00+00'),
 (5,90,'Success','2025-01-01 16:00:00+00'),
 (6,70,'Success','2025-01-01 06:00:00+00'),
 (7,80,'Pending','2025-01-01 04:00:00+00'),
 (8,60,'Failed','2025-01-01 05:00:00+00')
)x(n,amount,status,received_at);
insert into public.provider_earnings(provider_id,booking_id,gross_amount,platform_fee,created_at) values
 (pg_temp.analytics_id('provider_a'),pg_temp.analytics_id('booking_1'),100,10,'2025-01-01 04:00:00+00'),
 (pg_temp.analytics_id('provider_a'),pg_temp.analytics_id('booking_4'),300,30,'2025-01-01 04:00:00+00');
insert into public.reviews(review_id,booking_id,customer_id,provider_id,rating_score,is_flagged,moderation_status,created_at) values
 (pg_temp.analytics_id('review_1'),pg_temp.analytics_id('booking_1'),pg_temp.fixture_id('customer_profile'),pg_temp.analytics_id('provider_a'),5,false,'visible','2025-01-01 04:00:00+00'),
 (pg_temp.analytics_id('review_2'),pg_temp.analytics_id('booking_2'),pg_temp.fixture_id('customer_profile'),pg_temp.analytics_id('provider_a'),3,false,'hidden','2025-01-01 04:00:00+00'),
 (pg_temp.analytics_id('review_3'),pg_temp.analytics_id('booking_3'),pg_temp.fixture_id('customer_profile'),pg_temp.analytics_id('provider_b'),1,true,'visible','2025-01-01 04:00:00+00');
insert into public.booking_disputes(booking_id,opened_by,subject,description,created_at)
values(pg_temp.analytics_id('booking_1'),pg_temp.fixture_id('super_user'),'Analytics regression dispute','Synthetic unresolved analytics dispute','2025-01-01 04:00:00+00');
insert into public.refund_requests(payment_id,amount,reason,requested_by,created_at)
values(pg_temp.analytics_id('payment_1'),20,'Synthetic analytics refund request',pg_temp.fixture_id('super_profile'),'2025-01-01 04:00:00+00');

select pg_temp.test_assert('only one public analytics signature is exposed',
 (select count(*)=1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='admin_analytics'));
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select set_config('request.jwt.claim.sub','',true);
select pg_temp.test_error('analytics anonymous access is denied','select public.admin_analytics(''2025-01-01'',''2025-01-01'')','42501');
set local role authenticated;
select pg_temp.login_as('customer_auth');
select pg_temp.test_error('analytics ordinary customer access is denied','select public.admin_analytics(''2025-01-01'',''2025-01-01'')','42501','administrator');
select pg_temp.login_as('super_auth','aal1');
select pg_temp.test_error('analytics AAL1 administrator access is denied','select public.admin_analytics(''2025-01-01'',''2025-01-01'')','42501','authenticator');
select pg_temp.login_as('super_auth');
select pg_temp.test_assert('analytics two-date positional call stays compatible',
 public.admin_analytics('2025-01-01','2025-01-01')->>'timezone'='Asia/Kuala_Lumpur');
select pg_temp.test_assert('analytics named date call stays compatible',
 public.admin_analytics(date_from=>'2025-01-01',date_to=>'2025-01-01')->>'timezone'='Asia/Kuala_Lumpur');
select pg_temp.test_error('analytics rejects invalid date order','select public.admin_analytics(''2025-01-02'',''2025-01-01'')','P0001','date range');
select pg_temp.test_error('analytics rejects invalid service region','select public.admin_analytics(''2025-01-01'',''2025-01-01'',null,''Invalid Region'',null)','P0001','service region');
select pg_temp.test_error('analytics rejects nonexistent category','select public.admin_analytics(''2025-01-01'',''2025-01-01'',''fffffffe-ffff-4000-8000-ffffffffffff'',null,null)','P0001','category');
select pg_temp.test_assert('analytics parent category includes child bookings',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->>'bookings')::integer=5);
select pg_temp.test_assert('analytics gross collected includes Refunded and excludes Pending Failed',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->>'gross_collected')::numeric=420);
select pg_temp.test_assert('analytics provider filter isolates matching category bookings',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),null,pg_temp.analytics_id('provider_a'))->>'bookings')::integer=4);
select pg_temp.test_assert('analytics receipt from earlier booking remains included',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley',pg_temp.analytics_id('provider_a'))->>'gross_collected')::numeric=220);
select pg_temp.test_assert('analytics region filter isolates Penang bookings and revenue',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'bookings')::integer=1
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'gross_collected')::numeric=200);
select pg_temp.test_assert('analytics contradictory provider region filters return zero',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley',pg_temp.analytics_id('provider_b'))->>'bookings')::integer=0
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley',pg_temp.analytics_id('provider_b'))->>'gross_collected')::numeric=0);
select pg_temp.test_assert('analytics daily revenue matches gross collected',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'daily'->0->>'gross_collected')::numeric=420);
select pg_temp.test_assert('analytics KL exclusive end boundary excludes next midnight',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'daily'->0->>'bookings')::integer=5
 and (public.admin_analytics('2025-01-01','2025-01-02',pg_temp.analytics_id('category_root'))->'daily'->1->>'bookings')::integer=1
 and (public.admin_analytics('2025-01-01','2025-01-02',pg_temp.analytics_id('category_root'))->'daily'->1->>'gross_collected')::numeric=90);
select pg_temp.test_assert('analytics empty days are zero-filled',
 (public.admin_analytics('2025-01-01','2025-01-03',pg_temp.analytics_id('category_root'))->'daily'->2->>'bookings')::integer=0
 and (public.admin_analytics('2025-01-01','2025-01-03',pg_temp.analytics_id('category_root'))->'daily'->2->>'gross_collected')::numeric=0);
select pg_temp.test_assert('analytics registration counts remain explicitly global',
 public.admin_analytics('2025-01-01','2025-01-01')->>'users'=public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'users'
 and public.admin_analytics('2025-01-01','2025-01-01')->>'new_users'=public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'new_users'
 and public.admin_analytics('2025-01-01','2025-01-01')->'global_metrics' ? 'new_users');
select pg_temp.test_assert('analytics category popularity follows selected dimensions',
 jsonb_array_length(public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'categories')=1
 and public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'categories'->0->>'category_id'=pg_temp.analytics_id('category_child')::text
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'categories'->0->>'bookings')::integer=5
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'))->'categories'->0->>'gross_collected')::numeric=420);
select pg_temp.test_assert('analytics fees and requested refunds use matching bookings',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley',pg_temp.analytics_id('provider_a'))->>'platform_fees')::numeric=10
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley',pg_temp.analytics_id('provider_a'))->>'refunds_requested')::numeric=20);
select pg_temp.test_assert('analytics review moderation and dispute queues follow filters',
 (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley')->>'avg_rating')::numeric=5
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Klang Valley')->>'open_disputes')::integer=1
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'flagged_reviews')::integer=1
 and (public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),'Penang')->>'open_disputes')::integer=0);
select pg_temp.test_assert('analytics filter choices contain actual category rows',
 exists(select 1 from jsonb_array_elements(public.admin_analytics('2025-01-01','2025-01-01')->'category_choices') c where c->>'category_id'=pg_temp.analytics_id('category_child')::text));
select pg_temp.test_assert('analytics filter choices contain actual provider rows',
 exists(select 1 from jsonb_array_elements(public.admin_analytics('2025-01-01','2025-01-01')->'provider_choices') p where p->>'provider_id'=pg_temp.analytics_id('provider_b')::text and p->>'region'='Penang'));
select pg_temp.test_assert('analytics filter choices contain actual regions',
 public.admin_analytics('2025-01-01','2025-01-01')->'region_choices' ? 'Penang');
select pg_temp.test_assert('analytics response echoes normalized selected filters',
 public.admin_analytics('2025-01-01','2025-01-01',pg_temp.analytics_id('category_root'),' Penang ',pg_temp.analytics_id('provider_b'))->'selected_filters'
 =jsonb_build_object('category_id',pg_temp.analytics_id('category_root'),'region','Penang','provider_id',pg_temp.analytics_id('provider_b')));
reset role;
select jsonb_build_object('passed',count(*),'tests',jsonb_agg(test_name order by test_name)) as admin_and_analytics_regression_result
from pg_temp.admin_regression_results;
