-- Refund state is written only by the verified gateway, never by an admin form.
alter table public.refund_requests add column submitted_at timestamptz,
 add column completed_at timestamptz, add column gateway_status text;
create index refund_completed_idx on public.refund_requests(completed_at) where status='Succeeded';

-- Link requests to a customer-owned support case without overwriting its response.
create function private.link_refund_support() returns trigger language plpgsql security definer set search_path='' as $$
declare bid uuid; uid uuid; did uuid;
begin
 select p.booking_id,c.user_id into bid,uid from public.payments p join public.customer_profiles c using(customer_id) where p.payment_id=new.payment_id;
 perform pg_advisory_xact_lock(hashtextextended('refund-support:'||bid::text,0));
 select dispute_id into did from public.booking_disputes where booking_id=bid and (opened_by=uid or status in ('Open','Under Review')) order by (status in ('Open','Under Review')) desc,created_at desc limit 1;
 if did is null then
  insert into public.booking_disputes(booking_id,opened_by,subject,description,status)
  values(bid,uid,'Booking refund','A refund review has been opened for this booking. Refund progress appears below.','Under Review') returning dispute_id into did;
 end if;
 new.dispute_id:=did;
 return new;
end $$;
revoke all on function private.link_refund_support() from public,anon,authenticated;
create trigger refund_support before insert on public.refund_requests for each row execute function private.link_refund_support();
-- Backfill existing requests through the same linking code without sending funds.
create trigger refund_support_backfill before update on public.refund_requests for each row when(new.dispute_id is null) execute function private.link_refund_support();
update public.refund_requests set updated_at=updated_at where dispute_id is null;
drop trigger refund_support_backfill on public.refund_requests;

-- Preserve the existing mutation's authorization, audit and concurrency checks.
-- A pending refund reserves the payment even when its amount is only partial.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.admin_mutate(text,uuid,text,jsonb)'::regprocedure);
 body:=replace(body,'select coalesce(sum(amount),0) into refund_total',
 'if exists(select 1 from public.refund_requests where payment_id=record_id and status in (''Requested'',''Processing'')) then raise exception ''A refund is already pending. Open its refund record to process or refresh it.''; end if;
 select coalesce(sum(amount),0) into refund_total');
 body:=replace(body,'Refund request recorded. Funds have not been refunded; gateway processing is still required.','Refund request saved. Open the refund record to submit it to Stripe.');
 execute body;
end $$;

create function public.admin_prepare_refund(p_refund_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.admin_actor(); r public.refund_requests%rowtype; p public.payments%rowtype;
begin
 if not exists(select 1 from public.admin_profiles where user_id=actor and admin_role_level='super_admin') then raise exception 'Only a Super Admin can process refunds' using errcode='42501'; end if;
 select pay.* into p from public.payments pay join public.refund_requests req on req.payment_id=pay.payment_id where req.refund_id=p_refund_id for update of pay;
 if not found then raise exception 'Refund not found'; end if;
 select * into r from public.refund_requests where refund_id=p_refund_id for update;
 if r.status in ('Failed','Cancelled') then raise exception 'This refund is closed. Review the booking before requesting a new refund.'; end if;
 if r.status='Requested' then
  if p.payment_status<>'Success' or p.fpx_transaction_ref !~ '^pi_[a-zA-Z0-9]+$' or p.fpx_transaction_ref is null then raise exception 'A verified Stripe payment is required'; end if;
  if r.amount+(select coalesce(sum(amount),0) from public.refund_requests where payment_id=p.payment_id and refund_id<>r.refund_id and status in ('Requested','Processing','Succeeded'))>p.payment_amount then raise exception 'Refund exceeds the remaining paid amount'; end if;
  update public.refund_requests set status='Processing',submitted_at=now(),updated_at=now() where refund_id=r.refund_id returning * into r;
  insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values) values(actor,'admin','refund_process','refund_requests',r.refund_id,jsonb_build_object('status','Requested'),to_jsonb(r));
 end if;
 return jsonb_build_object('refund_id',r.refund_id,'payment_intent',p.fpx_transaction_ref,'amount_sen',(r.amount*100)::bigint,'status',r.status,'gateway_reference',r.gateway_reference,'submitted_at',r.submitted_at);
end $$;
revoke all on function public.admin_prepare_refund(uuid) from public,anon;
grant execute on function public.admin_prepare_refund(uuid) to authenticated;

create function public.gateway_reject_refund(p_refund_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.refund_requests%rowtype; uid uuid; bid uuid;
begin
 -- Only the trusted gateway worker calls this after a definitive POST rejection.
 -- Serialize against preparation and confirmation; never release an accepted refund.
 perform 1 from public.payments p join public.refund_requests rr using(payment_id) where rr.refund_id=p_refund_id for update of p;
 select * into r from public.refund_requests where refund_id=p_refund_id for update;
 if r.status='Processing' and r.gateway_reference is null then
  update public.refund_requests set status='Failed',gateway_status='rejected',updated_at=now() where refund_id=p_refund_id;
  select p.booking_id,c.user_id into bid,uid from public.payments p join public.customer_profiles c using(customer_id) where p.payment_id=r.payment_id;
  perform private.customer_event(uid,bid,'Payment','Refund update','Your refund could not be completed. Contact support in Help Centre.');
  insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values) values(null,null,'refund_gateway_rejected','refund_requests',r.refund_id,to_jsonb(r),jsonb_build_object('status','Failed'));
 end if;
 return jsonb_build_object('recorded',true);
end $$;
revoke all on function public.gateway_reject_refund(uuid) from public,anon,authenticated;
grant execute on function public.gateway_reject_refund(uuid) to service_role;

create function public.gateway_record_refund(p_refund_id uuid,p_reference text,p_payment_intent text,p_amount_sen bigint,p_currency text,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.refund_requests%rowtype; p public.payments%rowtype; bid uuid; pid uuid; uid uuid; next_status text; refunded numeric;
begin
 if p_reference is null or p_reference !~ '^re_[a-zA-Z0-9]+$' or p_currency is distinct from 'myr' or p_status is null or p_status not in ('pending','requires_action','succeeded','failed','canceled') then raise exception 'Invalid refund confirmation'; end if;
 select pay.booking_id,b.provider_id into bid,pid from public.refund_requests req join public.payments pay using(payment_id) join public.bookings b using(booking_id) where req.refund_id=p_refund_id;
 if bid is null then raise exception 'Unknown refund'; end if;
 -- Same ordering as provider booking writers: provider, booking, payment, refund.
 perform pg_advisory_xact_lock(hashtextextended(pid::text,0));
 perform 1 from public.bookings where booking_id=bid for update;
 select * into p from public.payments where booking_id=bid for update;
 select * into r from public.refund_requests where refund_id=p_refund_id for update;
 if p_payment_intent is distinct from p.fpx_transaction_ref or p_amount_sen is distinct from (r.amount*100)::bigint or (r.gateway_reference is not null and r.gateway_reference<>p_reference) then raise exception 'Refund confirmation does not match the request'; end if;
 if r.status='Requested' then raise exception 'Refund was not submitted'; end if;
 next_status:=case p_status when 'succeeded' then 'Succeeded' when 'failed' then 'Failed' when 'canceled' then 'Cancelled' else 'Processing' end;
 -- A refund can fail after initially succeeding (bank return). Never regress a
 -- terminal state to pending when an earlier webhook is delivered late.
 if r.status in ('Failed','Cancelled') or (r.status='Succeeded' and next_status='Processing') then return jsonb_build_object('status',r.status); end if;
 if next_status='Succeeded' and r.amount+(select coalesce(sum(amount),0) from public.refund_requests where payment_id=p.payment_id and refund_id<>r.refund_id and status='Succeeded')>p.payment_amount then raise exception 'Refund exceeds collected payment'; end if;
 update public.refund_requests set status=next_status,gateway_reference=p_reference,gateway_status=p_status,
 completed_at=case when next_status='Succeeded' then coalesce(completed_at,now()) else null end,updated_at=case when status is distinct from next_status or gateway_status is distinct from p_status then now() else updated_at end where refund_id=r.refund_id;
 select coalesce(sum(amount),0) into refunded from public.refund_requests where payment_id=p.payment_id and status='Succeeded';
 update public.payments set payment_status=case when refunded>=payment_amount then 'Refunded'::public.payment_status else 'Success'::public.payment_status end where payment_id=p.payment_id;
 if refunded>=p.payment_amount then
  perform set_config('app.action_reason','Full payment refunded by Stripe.',true);
  update public.bookings set booking_status='Cancelled',cancelled_at=now(),cancellation_reason='Full payment refunded by Stripe.',reservation_expires_at=now() where booking_id=bid and booking_status in ('Pending','Confirmed','In-Progress');
 end if;
 if r.status is distinct from next_status then
  select user_id into uid from public.customer_profiles where customer_id=p.customer_id;
  perform private.customer_event(uid,bid,'Payment','Refund update',case next_status when 'Succeeded' then 'Your refund has been confirmed by Stripe. Check Help Centre for the amount and reference. Your bank may take additional time to credit it.' when 'Failed' then 'Your refund could not be completed. Contact support in Help Centre.' when 'Cancelled' then 'Your refund was cancelled. Contact support in Help Centre.' else 'Your refund is being processed. Follow its progress in Help Centre.' end);
  insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values) values(null,null,'refund_gateway_update','refund_requests',r.refund_id,to_jsonb(r),jsonb_build_object('status',next_status,'gateway_reference',p_reference));
 end if;
 return jsonb_build_object('status',next_status);
end $$;
revoke all on function public.gateway_record_refund(uuid,text,text,bigint,text,text) from public,anon,authenticated;
grant execute on function public.gateway_record_refund(uuid,text,text,bigint,text,text) to service_role;

-- Redacted refund history for the authenticated owner, including suspended users.
create or replace function private.customer_support_requests(p_id uuid default null,p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.customer_viewer_user_id();
begin
 perform private.customer_viewer_id();
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset<0 then raise exception 'Invalid page.' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(to_jsonb(d)) from (
  select dispute_id,booking_id,
   case when opened_by=uid then subject else 'Booking refund' end as subject,
   case when opened_by=uid then description else 'A refund review has been opened for this booking. Refund progress appears below.' end as description,
   case when opened_by=uid then status else 'Under Review' end as status,
   case when opened_by=uid then resolution end as resolution,created_at,updated_at,
   case when opened_by=uid then attachment_paths else '{}'::text[] end as attachment_paths,
   coalesce((select jsonb_agg(jsonb_build_object('refund_id',r.refund_id,'amount',r.amount,'status',r.status,'gateway_reference',r.gateway_reference,'created_at',r.created_at,'updated_at',r.updated_at) order by r.created_at) from public.refund_requests r join public.payments p using(payment_id) where p.booking_id=b.booking_id),'[]') as refunds
  from public.booking_disputes b where (opened_by=uid or exists(select 1 from public.refund_requests r join public.payments p using(payment_id) join public.customer_profiles c using(customer_id) where r.dispute_id=b.dispute_id and c.user_id=uid)) and (p_id is null or dispute_id=p_id)
  order by created_at desc,dispute_id desc limit p_limit offset p_offset)d),'[]');
end $$;

alter function private.admin_detail(text,uuid) rename to admin_detail_before_refunds;
revoke all on function private.admin_detail_before_refunds(text,uuid) from public,anon,authenticated;
create function private.admin_detail(resource text,record_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; bid uuid; pay jsonb;
begin
 perform private.admin_actor();
 if resource='refunds' then
  select to_jsonb(r)||jsonb_build_object('booking_id',p.booking_id) into result from public.refund_requests r join public.payments p using(payment_id) where refund_id=record_id;
  if result is null then raise exception 'Refund not found'; end if;
  return result;
 end if;
 result:=private.admin_detail_before_refunds(resource,record_id);
 if resource in ('bookings','disputes') then
  bid:=case when resource='bookings' then record_id else (result->>'booking_id')::uuid end;
  select to_jsonb(p)||jsonb_build_object('version',md5(to_jsonb(p)::text),'refunds',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.refund_requests r where r.payment_id=p.payment_id),'[]'),'remaining',p.payment_amount-(select coalesce(sum(amount),0) from public.refund_requests where payment_id=p.payment_id and status in ('Requested','Processing','Succeeded'))) into pay from public.payments p where p.booking_id=bid;
  result:=result||jsonb_build_object('payment',pay);
 end if;
 return result;
end $$;
revoke all on function private.admin_detail(text,uuid) from public,anon;
grant execute on function private.admin_detail(text,uuid) to authenticated;

create or replace function private.admin_analytics(
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
 ), matching_refunds as materialized (
  select r.* from public.refund_requests r join public.payments p using(payment_id) join matching_bookings b using(booking_id)
 ), completed_refunds as materialized (
  select * from matching_refunds where status='Succeeded' and completed_at>=start_at and completed_at<end_at
 ), refunds_by_day as (
  select (completed_at at time zone 'Asia/Kuala_Lumpur')::date as day,sum(amount) as refunded from completed_refunds group by 1
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
  'scope_note','User totals, registrations and the pending-provider verification queue are global. Other metrics follow the selected booking category, provider and provider region. Booking counts use booking creation dates; gross collected uses payment receipt dates and includes collected payments later refunded. Active bookings and unresolved review/dispute queues span all dates. Confirmed refunds use confirmation dates, even for payments received earlier. Net collected is period collections minus period confirmed refunds, not profit. Pending refund amount spans all dates; status counts use request dates. Categories and regions use the current catalogue and provider profiles.',
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
  'generated_at',now(),
  'refunds_requested',(select coalesce(sum(amount),0) from matching_refunds where status in ('Requested','Processing')),
  'refunds_succeeded',(select coalesce(sum(amount),0) from completed_refunds),
  'net_collected',(select coalesce(sum(payment_amount),0) from collected_payments)-(select coalesce(sum(amount),0) from completed_refunds),
  'refund_statuses',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select status,count(*) as count,sum(amount) as amount from matching_refunds where created_at>=start_at and created_at<end_at group by status order by status)x),
  'avg_rating',(select coalesce(round(avg(r.rating_score),2),0) from public.reviews r join matching_bookings b using(booking_id) where r.moderation_status='visible' and not r.is_flagged and r.created_at>=start_at and r.created_at<end_at),
  'daily',coalesce((select jsonb_agg(jsonb_build_object('date',d.day::date,'bookings',coalesce(b.bookings,0),'users',coalesce(u.users,0),'gross_collected',coalesce(p.gross_collected,0),'refunded',coalesce(r.refunded,0)) order by d.day)
   from generate_series(date_from::timestamp,date_to::timestamp,interval '1 day') d(day)
   left join bookings_by_day b on b.day=d.day::date
   left join payments_by_day p on p.day=d.day::date
   left join users_by_day u on u.day=d.day::date
   left join refunds_by_day r on r.day=d.day::date),'[]'::jsonb),
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

