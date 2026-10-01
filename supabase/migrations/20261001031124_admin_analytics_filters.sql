-- Keep the two-date API call compatible by using one signature with three optional
-- filters. Removing the prior signatures avoids ambiguous defaulted overloads.
drop function public.admin_analytics(date,date);
drop function private.admin_analytics(date,date);

create function private.admin_analytics(
 date_from date,date_to date,category_filter uuid,region_filter text,provider_filter uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 result jsonb;
 start_at timestamptz;
 end_at timestamptz;
 filter_category uuid:=category_filter;
 filter_region text:=nullif(trim(region_filter),'');
 filter_provider uuid:=provider_filter;
begin
 perform private.admin_actor();
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>366 then
  raise exception 'Choose a date range of at most 367 days';
 end if;
 if filter_category is not null and not exists(select 1 from public.service_categories c where c.category_id=filter_category) then
  raise exception 'Selected category no longer exists';
 end if;
 if filter_provider is not null and not exists(select 1 from public.provider_profiles p where p.provider_id=filter_provider) then
  raise exception 'Selected provider no longer exists';
 end if;
 if filter_region is not null and not exists(
  select 1 from unnest(enum_range(null::public.service_area_region)) known(region_name)
  where known.region_name::text=filter_region
 ) then raise exception 'Invalid service region'; end if;
 start_at=date_from::timestamp at time zone 'Asia/Kuala_Lumpur';
 end_at=(date_to+1)::timestamp at time zone 'Asia/Kuala_Lumpur';

 with recursive selected_categories(category_id) as (
  select c.category_id from public.service_categories c where c.category_id=filter_category
  union
  select c.category_id from public.service_categories c join selected_categories parent on c.parent_category_id=parent.category_id
 ), matching_bookings as materialized (
  select b.*,s.category_id,c.category_name,p.business_name,p.region::text as provider_region
  from public.bookings b
  join public.services s on s.service_id=b.service_id
  join public.service_categories c on c.category_id=s.category_id
  join public.provider_profiles p on p.provider_id=b.provider_id
  where (filter_category is null or s.category_id in(select category_id from selected_categories))
   and (filter_region is null or p.region::text=filter_region)
   and (filter_provider is null or b.provider_id=filter_provider)
 ), period_bookings as materialized (
  select b.* from matching_bookings b where b.created_at>=start_at and b.created_at<end_at
 ), collected_payments as materialized (
  -- Gross collected includes historically collected payments later fully refunded;
  -- it excludes Pending/Failed and is never presented as net revenue.
  select pay.payment_id,pay.booking_id,pay.payment_amount,
   coalesce(pay.payment_timestamp,pay.created_at) as collected_at,b.provider_id,b.category_id
  from public.payments pay join matching_bookings b using(booking_id)
  where pay.payment_status in ('Success','Refunded')
   and coalesce(pay.payment_timestamp,pay.created_at)>=start_at
   and coalesce(pay.payment_timestamp,pay.created_at)<end_at
 ), bookings_by_day as (
  select (b.created_at at time zone 'Asia/Kuala_Lumpur')::date as day,count(*) as bookings
  from period_bookings b group by 1
 ), payments_by_day as (
  select (p.collected_at at time zone 'Asia/Kuala_Lumpur')::date as day,sum(p.payment_amount) as gross_collected
  from collected_payments p group by 1
 ), users_by_day as (
  select (u.created_at at time zone 'Asia/Kuala_Lumpur')::date as day,count(*) as users
  from public.users u where u.created_at>=start_at and u.created_at<end_at group by 1
 ), bookings_by_category as (
  select b.category_id,count(*) as bookings,count(*) filter(where b.booking_status='Completed') as completed
  from period_bookings b group by b.category_id
 ), payments_by_category as (
  select p.category_id,sum(p.payment_amount) as gross_collected from collected_payments p group by p.category_id
 ), category_totals as (
  select coalesce(b.category_id,p.category_id) as category_id,coalesce(b.bookings,0) as bookings,
   coalesce(b.completed,0) as completed,coalesce(p.gross_collected,0) as gross_collected
  from bookings_by_category b full join payments_by_category p using(category_id)
 ), bookings_by_provider as (
  select b.provider_id,count(*) as bookings,count(*) filter(where b.booking_status='Completed') as completed
  from period_bookings b group by b.provider_id
 ), payments_by_provider as (
  select p.provider_id,sum(p.payment_amount) as gross_collected from collected_payments p group by p.provider_id
 ), provider_totals as (
  select coalesce(b.provider_id,p.provider_id) as provider_id,coalesce(b.bookings,0) as bookings,
   coalesce(b.completed,0) as completed,coalesce(p.gross_collected,0) as gross_collected
  from bookings_by_provider b full join payments_by_provider p using(provider_id)
 )
 select jsonb_build_object(
  'from',date_from,'to',date_to,'timezone','Asia/Kuala_Lumpur',
  'selected_filters',jsonb_build_object('category_id',filter_category,'region',filter_region,'provider_id',filter_provider),
  'scope_note','User totals, registrations and the pending-provider verification queue are global. Other metrics follow the selected booking category, provider and provider region. Booking counts use booking creation dates; gross collected uses payment receipt dates and includes collected payments later refunded. Active bookings and unresolved review/dispute queues span all dates. Categories and regions use the current catalogue and provider profiles.',
  'global_metrics',jsonb_build_array('users','new_users','daily.users','pending_providers'),
  'users',(select count(*) from public.users),
  'new_users',(select count(*) from public.users where created_at>=start_at and created_at<end_at),
  'bookings',(select count(*) from period_bookings),
  'active_bookings',(select count(*) from matching_bookings where booking_status in ('Pending','Confirmed','In-Progress')),
  'pending_providers',(select count(*) from public.provider_profiles where verification_status='Pending'),
  'open_disputes',(select count(*) from public.booking_disputes d join matching_bookings b using(booking_id) where d.status in ('Open','Under Review')),
  'flagged_reviews',(select count(*) from public.reviews r join matching_bookings b using(booking_id) where r.is_flagged),
  'gross_collected',(select coalesce(sum(payment_amount),0) from collected_payments),
  'platform_fees',(select coalesce(sum(e.platform_fee),0) from public.provider_earnings e join matching_bookings b using(booking_id) where e.created_at>=start_at and e.created_at<end_at),
  'refunds_requested',(select coalesce(sum(r.amount),0) from public.refund_requests r join public.payments p using(payment_id) join matching_bookings b on b.booking_id=p.booking_id where r.created_at>=start_at and r.created_at<end_at and r.status in ('Requested','Processing')),
  'avg_rating',(select coalesce(round(avg(r.rating_score),2),0) from public.reviews r join matching_bookings b using(booking_id) where r.moderation_status='visible' and not r.is_flagged and r.created_at>=start_at and r.created_at<end_at),
  'daily',coalesce((select jsonb_agg(jsonb_build_object('date',d.day::date,'bookings',coalesce(b.bookings,0),'users',coalesce(u.users,0),'gross_collected',coalesce(p.gross_collected,0)) order by d.day)
   from generate_series(date_from::timestamp,date_to::timestamp,interval '1 day') d(day)
   left join bookings_by_day b on b.day=d.day::date
   left join payments_by_day p on p.day=d.day::date
   left join users_by_day u on u.day=d.day::date),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(to_jsonb(x) order by x.bookings desc,x.category_name,x.category_id)
   from(select c.category_id,c.category_name,t.bookings,t.completed,t.gross_collected
    from category_totals t join public.service_categories c using(category_id))x),'[]'::jsonb),
  'providers',coalesce((select jsonb_agg(to_jsonb(x) order by x.completed desc,x.business_name,x.provider_id)
   from(select p.provider_id,p.business_name,p.region::text as region,t.bookings,t.completed,t.gross_collected,p.overall_rating
    from provider_totals t join public.provider_profiles p using(provider_id)
    order by t.completed desc,p.business_name,p.provider_id limit 20)x),'[]'::jsonb),
  'category_choices',coalesce((select jsonb_agg(jsonb_build_object('category_id',c.category_id,'category_name',c.category_name,'parent_category_id',c.parent_category_id,'parent_name',parent.category_name) order by c.category_name,c.category_id)
   from public.service_categories c left join public.service_categories parent on parent.category_id=c.parent_category_id),'[]'::jsonb),
  'region_choices',coalesce((select jsonb_agg(x.region order by x.region) from(select distinct p.region::text as region from public.provider_profiles p where p.region is not null)x),'[]'::jsonb),
  'provider_choices',coalesce((select jsonb_agg(jsonb_build_object('provider_id',p.provider_id,'business_name',p.business_name,'region',p.region::text) order by p.business_name,p.provider_id) from public.provider_profiles p),'[]'::jsonb)
 ) into result;
 return result;
end $$;

create function public.admin_analytics(
 date_from date,date_to date,category_filter uuid default null,region_filter text default null,provider_filter uuid default null
) returns jsonb language sql security invoker set search_path='' as $$
 select private.admin_analytics(date_from,date_to,category_filter,region_filter,provider_filter)
$$;
revoke all on function private.admin_analytics(date,date,uuid,text,uuid),public.admin_analytics(date,date,uuid,text,uuid) from public,anon;
grant execute on function private.admin_analytics(date,date,uuid,text,uuid),public.admin_analytics(date,date,uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';
