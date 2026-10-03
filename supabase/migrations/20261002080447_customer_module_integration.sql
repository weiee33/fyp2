-- Customer modules 5-10 share authoritative ownership and transactional APIs.
-- Existing records and administrator APIs are preserved.
alter table public.bookings
 add column request_id uuid,
 add column reservation_expires_at timestamptz,
 add column duration_minutes integer check (duration_minutes between 1 and 1440),
 add column service_name_snapshot text,
 add column provider_name_snapshot text,
 add column pricing_type_snapshot text,
 add column unit_price_snapshot numeric(12,2);
update public.bookings b set duration_minutes=least(s.estimated_duration,1440),
 service_name_snapshot=s.service_name,provider_name_snapshot=p.business_name,
 pricing_type_snapshot=s.pricing_type::text,unit_price_snapshot=s.base_price
from public.services s,public.provider_profiles p where s.service_id=b.service_id and p.provider_id=b.provider_id;
create unique index booking_customer_request_idx on public.bookings(customer_id,request_id) where request_id is not null;
create index booking_provider_schedule_idx on public.bookings(provider_id,scheduled_datetime) where booking_status in ('Pending','Confirmed','In-Progress');
alter table public.notifications add column dismissed_at timestamptz;
create index notification_inbox_idx on public.notifications(user_id,created_at desc) where dismissed_at is null;
-- Collection is not an escrow arrangement. Only verified gateway results count.
alter table public.payments alter column escrow_held set default false;

create function private.customer_id() returns uuid language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 select c.customer_id into cid from public.customer_profiles c join public.users u using(user_id)
 join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=auth.uid() and u.role='customer' and u.is_active is true and a.email_confirmed_at is not null;
 if cid is null then raise exception 'Sign in with an active, verified customer account' using errcode='42501'; end if;
 return cid;
end $$;
revoke all on function private.customer_id() from public,anon,authenticated;

create function private.customer_event(p_user_id uuid,p_booking_id uuid,p_type public.notification_type,p_title text,p_message text)
returns void language plpgsql security definer set search_path='' as $$
declare nid uuid;
begin
 insert into public.notifications(user_id,booking_id,notification_type,title,message,deep_link)
 values(p_user_id,p_booking_id,p_type,left(p_title,150),left(p_message,500),case when p_booking_id is not null then 'booking/'||p_booking_id::text end)
 returning notification_id into nid;
 insert into private.notification_outbox(notification_id,recipient_user_id) values(nid,p_user_id);
end $$;
revoke all on function private.customer_event(uuid,uuid,public.notification_type,text,text) from public,anon,authenticated;

create function private.customer_search_services(p_category_id uuid default null,p_category_name text default null,p_keyword text default null,
 p_max_price numeric default null,p_min_rating numeric default null,p_limit integer default 20,p_offset integer default 0,p_city text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.customer_id();
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000
 or length(coalesce(p_keyword,''))>100 or length(coalesce(p_city,''))>100
 or p_max_price<0 or p_min_rating not between 0 and 5 then raise exception 'Invalid search filters'; end if;
 return coalesce((select jsonb_agg(to_jsonb(item)) from (
 select s.service_id,s.provider_id,s.category_id,c.category_name,s.service_name,s.description,s.base_price,s.max_price,
 s.pricing_type,s.estimated_duration,p.business_name,p.overall_rating,p.total_reviews,p.city,p.region,u.profile_photo_url,
 round(case when s.pricing_type='Hourly' then s.base_price*s.estimated_duration/60 else s.base_price end,2) as quoted_amount
 from public.services s join public.service_categories c using(category_id)
 join public.provider_profiles p using(provider_id) join public.users u on u.user_id=p.user_id
 where s.is_active is true and s.availability_status is true and c.is_active is true and u.is_active is true and p.verification_status='Verified'
 and (p_category_id is null or s.category_id=p_category_id or c.parent_category_id=p_category_id)
 and (nullif(trim(p_category_name),'') is null or c.category_name=p_category_name)
 and (nullif(trim(p_keyword),'') is null or position(lower(trim(p_keyword)) in lower(s.service_name||' '||s.description||' '||p.business_name||' '||c.category_name))>0)
 and (p_max_price is null or round(case when s.pricing_type='Hourly' then s.base_price*s.estimated_duration/60 else s.base_price end,2)<=p_max_price)
 and (p_min_rating is null or coalesce(p.overall_rating,0)>=p_min_rating)
 and (nullif(trim(p_city),'') is null or position(lower(trim(p_city)) in lower(coalesce(p.city,'')||' '||p.region::text))>0)
 order by p.overall_rating desc nulls last,p.total_reviews desc nulls last,s.service_id limit p_limit offset p_offset
 ) item),'[]'::jsonb);
end $$;
create function public.customer_search_services(p_category_id uuid default null,p_category_name text default null,p_keyword text default null,
 p_max_price numeric default null,p_min_rating numeric default null,p_limit integer default 20,p_offset integer default 0,p_city text default null)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.customer_search_services(p_category_id,p_category_name,p_keyword,p_max_price,p_min_rating,p_limit,p_offset,p_city) $$;

create function private.customer_provider_details(p_provider_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.customer_id();
 select jsonb_build_object('provider_id',p.provider_id,'business_name',p.business_name,'profile_photo_url',u.profile_photo_url,
 'overall_rating',p.overall_rating,'total_reviews',p.total_reviews,'review_count',p.total_reviews,'verification_status',p.verification_status,
 'bio',p.bio,'years_experience',p.years_experience,'service_radius_km',p.service_radius_km,'city',p.city,'region',p.region,
 'services',coalesce((select jsonb_agg(jsonb_build_object('service_id',s.service_id,'provider_id',s.provider_id,'category_id',s.category_id,
 'category_name',c.category_name,'service_name',s.service_name,'description',s.description,'base_price',s.base_price,'max_price',s.max_price,
 'pricing_type',s.pricing_type,'estimated_duration',s.estimated_duration,'quoted_amount',round(case when s.pricing_type='Hourly' then s.base_price*s.estimated_duration/60 else s.base_price end,2)) order by s.service_name,s.service_id)
 from public.services s join public.service_categories c using(category_id) where s.provider_id=p.provider_id and s.is_active is true and s.availability_status is true and c.is_active is true),'[]'),
 'certifications',coalesce((select jsonb_agg(jsonb_build_object('certification_name',pc.certification_name,'issuer',pc.issuer,'is_verified',true,'expiry_date',pc.expiry_date))
 from public.provider_certifications pc where pc.provider_id=p.provider_id and pc.is_verified is true and (pc.expiry_date is null or pc.expiry_date>=current_date)),'[]'),
 'reviews',coalesce((select jsonb_agg(to_jsonb(r)) from(select rating_score,review_comment,created_at,'Verified customer'::text as customer_name
 from public.reviews where provider_id=p.provider_id and moderation_status='visible' and is_verified_booking is true order by created_at desc,review_id limit 20) r),'[]'))
 into result from public.provider_profiles p join public.users u using(user_id)
 where p.provider_id=p_provider_id and p.verification_status='Verified' and u.is_active is true;
 if result is null then raise exception 'This provider is no longer available' using errcode='P0002'; end if;
 return result;
end $$;
create function public.customer_provider_details(p_provider_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select private.customer_provider_details(p_provider_id) $$;

create function private.customer_profile_update(p_full_name text,p_phone text,p_preferences text[],p_photo_url text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid; photo_path text;
begin
 select user_id into uid from public.customer_profiles where customer_id=cid for update;
 if p_full_name is null or length(trim(p_full_name)) not between 2 and 150 or p_phone is null
 or nullif(trim(p_phone),'') is not null and trim(p_phone)!~ '^\+?[0-9 ()-]{8,20}$'
 or p_preferences is null or cardinality(p_preferences)>20
 or exists(select 1 from unnest(p_preferences) v where v is null or length(trim(v)) not between 1 and 100) then raise exception 'Enter valid personal details and preferences'; end if;
 if p_photo_url is not null then
  photo_path:=split_part(p_photo_url,'/storage/v1/object/public/profiles/',2);
  if photo_path='' or split_part(photo_path,'/',1)<>auth.uid()::text or split_part(photo_path,'/',2)<>'avatars'
  or not exists(select 1 from storage.objects where bucket_id='profiles' and name=photo_path and owner_id=auth.uid()::text) then
   raise exception 'Choose your own uploaded profile image' using errcode='42501'; end if;
  -- Reconstruct the trusted project origin; do not persist an arbitrary external URL.
  p_photo_url:='https://znxhiymvmluxmdaxzxkt.supabase.co/storage/v1/object/public/profiles/'||photo_path;
 end if;
 update public.users set full_name=trim(p_full_name),phone=nullif(trim(p_phone),''),profile_photo_url=coalesce(p_photo_url,profile_photo_url) where user_id=uid;
 update public.customer_profiles set service_preferences=coalesce((select array_agg(distinct trim(v)) from unnest(p_preferences) v),'{}') where customer_id=cid;
 return jsonb_build_object('customer_id',cid,'user_id',uid);
end $$;
create function public.customer_profile_update(p_full_name text,p_phone text,p_preferences text[],p_photo_url text default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.customer_profile_update(p_full_name,p_phone,p_preferences,p_photo_url) $$;

create function private.customer_delete_address(p_address_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); removed_default boolean; replacement public.saved_addresses%rowtype;
begin
 perform 1 from public.customer_profiles where customer_id=cid for update;
 delete from public.saved_addresses where address_id=p_address_id and customer_id=cid returning is_default into removed_default;
 if not found then raise exception 'Address not found' using errcode='42501'; end if;
 if removed_default then
  select * into replacement from public.saved_addresses where customer_id=cid order by created_at,address_id limit 1;
  if found then
   update public.saved_addresses set is_default=true where address_id=replacement.address_id;
   update public.customer_profiles set default_address=concat_ws(', ',replacement.address_line,replacement.city,replacement.state,replacement.postcode),location_coordinates=replacement.coordinates where customer_id=cid;
  else update public.customer_profiles set default_address=null,location_coordinates=null where customer_id=cid; end if;
 end if;
end $$;
create function public.customer_delete_address(p_address_id uuid) returns void language sql security invoker set search_path='' as $$ select private.customer_delete_address(p_address_id) $$;

create function private.customer_notification_dismiss(p_notification_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 update public.notifications set dismissed_at=coalesce(dismissed_at,now()),is_read=true
 where notification_id=p_notification_id and user_id=(select user_id from public.customer_profiles where customer_id=cid);
 if not found then raise exception 'Notification not found' using errcode='42501'; end if;
end $$;
create function public.customer_notification_dismiss(p_notification_id uuid) returns void language sql security invoker set search_path='' as $$ select private.customer_notification_dismiss(p_notification_id) $$;

-- API projections deliberately do not return other customers or private provider data.
create function private.customer_booking_json(p_booking_id uuid,p_customer_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 select to_jsonb(b)||jsonb_build_object('service_name',coalesce(b.service_name_snapshot,s.service_name),
 'business_name',coalesce(b.provider_name_snapshot,p.business_name),'payment',
 (select jsonb_build_object('payment_id',pay.payment_id,'payment_status',pay.payment_status,'payment_amount',pay.payment_amount,
 'payment_method',pay.payment_method,'payment_timestamp',pay.payment_timestamp,'fpx_transaction_ref',pay.fpx_transaction_ref) from public.payments pay where pay.booking_id=b.booking_id),
 'has_review',exists(select 1 from public.reviews r where r.booking_id=b.booking_id),
 'can_review',b.booking_status='Completed' and exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success')
 and not exists(select 1 from public.reviews r where r.booking_id=b.booking_id),
 'can_pay',b.booking_status='Confirmed' and b.accepted_at is not null and b.scheduled_datetime>now()
 and (b.reservation_expires_at is null or b.reservation_expires_at>now())
 and not exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status in ('Success','Refunded')),
 'can_cancel',b.booking_status in ('Pending','Confirmed') and b.scheduled_datetime>now(),
 'reservation_expired',b.reservation_expires_at is not null and b.reservation_expires_at<=now()
 and not exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success'),
 'history',coalesce((select jsonb_agg(jsonb_build_object('status',h.new_status,'created_at',h.created_at,'notes',h.notes) order by h.created_at,h.history_id) from public.booking_status_history h where h.booking_id=b.booking_id),'[]'),
 'disputes',coalesce((select jsonb_agg(jsonb_build_object('dispute_id',d.dispute_id,'subject',d.subject,'status',d.status,'resolution',d.resolution,'created_at',d.created_at) order by d.created_at desc) from public.booking_disputes d where d.booking_id=b.booking_id),'[]'))
 into result from public.bookings b join public.services s on s.service_id=b.service_id join public.provider_profiles p on p.provider_id=b.provider_id
 where b.booking_id=p_booking_id and b.customer_id=p_customer_id;
 if result is null then raise exception 'Booking not found' using errcode='42501'; end if;
 return result;
end $$;
revoke all on function private.customer_booking_json(uuid,uuid) from public,anon,authenticated;

create function private.customer_booking_detail(p_booking_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin return private.customer_booking_json(p_booking_id,private.customer_id()); end $$;
create function public.customer_booking_detail(p_booking_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_booking_detail(p_booking_id) $$;
create function private.customer_bookings(p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000 then raise exception 'Invalid booking page'; end if;
 return coalesce((select jsonb_agg(private.customer_booking_json(b.booking_id,cid)) from
 (select booking_id from public.bookings where customer_id=cid order by created_at desc,booking_id limit p_limit offset p_offset) b),'[]');
end $$;
create function public.customer_bookings(p_limit integer default 20,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_bookings(p_limit,p_offset) $$;

create function private.customer_booking_slots(p_service_id uuid,p_date date) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare service public.services%rowtype; hours public.provider_working_hours%rowtype;
begin
 perform private.customer_id();
 if p_date is null or p_date<(now() at time zone 'Asia/Kuala_Lumpur')::date or p_date>(now() at time zone 'Asia/Kuala_Lumpur')::date+90 then raise exception 'Choose a date within the next 90 days'; end if;
 select s.* into service from public.services s join public.service_categories c using(category_id)
 join public.provider_profiles p using(provider_id) join public.users u on u.user_id=p.user_id
 where s.service_id=p_service_id and s.is_active is true and s.availability_status is true and c.is_active is true and p.verification_status='Verified' and u.is_active is true;
 if not found then raise exception 'This service is no longer available'; end if;
 select * into hours from public.provider_working_hours where provider_id=service.provider_id and day_of_week=extract(isodow from p_date)::int-1 and is_active is true;
 if not found then return '[]'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('scheduled_time',slot::time,'scheduled_datetime',slot at time zone 'Asia/Kuala_Lumpur') order by slot)
 from generate_series(p_date+hours.start_time,p_date+hours.end_time-make_interval(mins=>service.estimated_duration),interval '30 minutes') slot
 where slot at time zone 'Asia/Kuala_Lumpur'>now()+interval '1 hour'
 and not exists(select 1 from public.bookings b where b.provider_id=service.provider_id and b.booking_status in ('Pending','Confirmed','In-Progress')
 and (b.reservation_expires_at is null or b.reservation_expires_at>now() or exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success'))
 and tstzrange(b.scheduled_datetime,b.scheduled_datetime+make_interval(mins=>coalesce(b.duration_minutes,60)),'[)')
 && tstzrange(slot at time zone 'Asia/Kuala_Lumpur',(slot+make_interval(mins=>service.estimated_duration)) at time zone 'Asia/Kuala_Lumpur','[)'))),'[]');
end $$;
create function public.customer_booking_slots(p_service_id uuid,p_date date) returns jsonb language sql volatile security invoker set search_path='' as $$ select private.customer_booking_slots(p_service_id,p_date) $$;

create function private.customer_create_booking(p_service_id uuid,p_address_id uuid,p_booking_date date,p_scheduled_time time,
 p_special_instructions text,p_urgency text,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); service public.services%rowtype; address public.saved_addresses%rowtype;
 existing public.bookings%rowtype; bid uuid; start_at timestamptz; price numeric; provider_name text; provider_user uuid; slots jsonb;
begin
 if p_request_id is null or p_service_id is null or p_address_id is null or p_scheduled_time is null or p_booking_date is null then raise exception 'Choose a service, address and available slot'; end if;
 if p_urgency is null or p_urgency not in ('Low','Medium','High','Emergency') or length(coalesce(p_special_instructions,''))>2000 then raise exception 'Invalid booking instructions'; end if;
 -- Lock customer for idempotency and provider for competing reservations. Always use this order.
 perform 1 from public.customer_profiles where customer_id=cid for update;
 select * into existing from public.bookings where customer_id=cid and request_id=p_request_id;
 if found then
  if existing.service_id<>p_service_id or existing.booking_date<>p_booking_date or existing.scheduled_time<>p_scheduled_time then raise exception 'This request token belongs to another booking'; end if;
  return private.customer_booking_json(existing.booking_id,cid);
 end if;
 select * into service from public.services where service_id=p_service_id;
 if not found then raise exception 'Service not found'; end if;
 perform pg_advisory_xact_lock(hashtextextended(service.provider_id::text,0));
 select business_name,user_id into provider_name,provider_user from public.provider_profiles where provider_id=service.provider_id;
 select * into address from public.saved_addresses where address_id=p_address_id and customer_id=cid;
 if not found then raise exception 'Choose one of your saved addresses' using errcode='42501'; end if;
 if (select count(*) from public.bookings where customer_id=cid and booking_status='Pending' and reservation_expires_at>now())>=5 then raise exception 'You already have five pending requests. Cancel one or wait for a provider response.'; end if;
 slots:=private.customer_booking_slots(p_service_id,p_booking_date);
 if not exists(select 1 from jsonb_array_elements(slots) s where (s->>'scheduled_time')::time=p_scheduled_time) then raise exception 'The selected time is no longer available. Choose another slot.' using errcode='23P01'; end if;
 start_at:=(p_booking_date+p_scheduled_time) at time zone 'Asia/Kuala_Lumpur';
 price:=round(case when service.pricing_type='Hourly' then service.base_price*service.estimated_duration/60 else service.base_price end,2);
 if price<=0 then raise exception 'This service requires a valid price before booking'; end if;
 insert into public.bookings(customer_id,provider_id,service_id,booking_date,scheduled_time,scheduled_datetime,
 customer_address,customer_coordinates,special_instructions,urgency,total_amount,request_id,reservation_expires_at,
 duration_minutes,service_name_snapshot,provider_name_snapshot,pricing_type_snapshot,unit_price_snapshot)
 values(cid,service.provider_id,service.service_id,p_booking_date,p_scheduled_time,start_at,
 concat_ws(', ',address.address_line,address.city,address.state,address.postcode),address.coordinates,nullif(trim(p_special_instructions),''),p_urgency::public.urgency_level,price,p_request_id,
 least(now()+interval '24 hours',start_at-interval '30 minutes'),service.estimated_duration,service.service_name,provider_name,service.pricing_type::text,service.base_price)
 returning booking_id into bid;
 insert into public.booking_status_history(booking_id,new_status,changed_by,notes) values(bid,'Pending',private.current_user_id(),'Awaiting provider acceptance; payment is not yet available.');
 perform private.customer_event(private.current_user_id(),bid,'New Booking','Booking requested','Your requested slot is awaiting provider acceptance. Payment becomes available after acceptance.');
 perform private.customer_event(provider_user,bid,'New Booking','New booking request','Review and accept or decline the requested slot before the customer pays.');
 return private.customer_booking_json(bid,cid);
end $$;
-- Approval means that the provider accepted the slot, not that payment succeeded.
-- Preserve the older administrator safeguard for legacy bookings, while applying
-- the acceptance-first workflow to customer requests created by this migration.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.admin_mutate(text,uuid,text,jsonb)'::regprocedure);
 body:=replace(body,'if desired=''Confirmed'' and not exists(',
 'if desired=''Confirmed'' and (before_row->>''request_id'') is null and not exists(');
 -- Every booking writer takes the provider lock before locking the booking row.
 body:=replace(body,'if record_id is not null then',
 'if action_name=''booking_status'' then
 perform pg_advisory_xact_lock(hashtextextended((select provider_id::text from public.bookings where booking_id=record_id),0));
 end if;
 if record_id is not null then');
 execute body;
end $$;

create function private.guard_customer_booking() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.request_id is null then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.provider_id::text,0));
 if tg_op='UPDATE' then
  if (new.customer_id,new.provider_id,new.service_id,new.total_amount,new.scheduled_datetime,new.duration_minutes,new.customer_address)
  is distinct from (old.customer_id,old.provider_id,old.service_id,old.total_amount,old.scheduled_datetime,old.duration_minutes,old.customer_address) then
   raise exception 'An existing booking keeps its agreed service, price, address and time'; end if;
  if old.booking_status='Pending' and new.booking_status='Confirmed' then
   if old.reservation_expires_at<=now() or new.scheduled_datetime<=now()+interval '30 minutes' then raise exception 'This requested slot has expired'; end if;
   new.accepted_at:=now(); new.reservation_expires_at:=least(now()+interval '30 minutes',new.scheduled_datetime);
  end if;
  if new.booking_status in ('In-Progress','Completed') and not exists(select 1 from public.payments where booking_id=new.booking_id and payment_status='Success') then
   raise exception 'A verified payment is required before service starts'; end if;
 end if;
 if new.booking_status in ('Pending','Confirmed','In-Progress') and (new.reservation_expires_at is null or new.reservation_expires_at>now()
 or exists(select 1 from public.payments where booking_id=new.booking_id and payment_status='Success'))
 and exists(select 1 from public.bookings b where b.provider_id=new.provider_id and b.booking_id<>new.booking_id and b.booking_status in ('Pending','Confirmed','In-Progress')
 and (b.reservation_expires_at is null or b.reservation_expires_at>now() or exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success'))
 and tstzrange(b.scheduled_datetime,b.scheduled_datetime+make_interval(mins=>coalesce(b.duration_minutes,60)),'[)')
 && tstzrange(new.scheduled_datetime,new.scheduled_datetime+make_interval(mins=>new.duration_minutes),'[)')) then
  raise exception 'The selected provider time overlaps another booking' using errcode='23P01'; end if;
 return new;
end $$;
revoke all on function private.guard_customer_booking() from public,anon,authenticated;
create trigger guard_customer_booking before insert or update on public.bookings for each row execute function private.guard_customer_booking();
create function public.customer_create_booking(p_service_id uuid,p_address_id uuid,p_booking_date date,p_scheduled_time time,p_special_instructions text,p_urgency text,p_request_id uuid)
returns jsonb language sql security invoker set search_path='' as $$ select private.customer_create_booking(p_service_id,p_address_id,p_booking_date,p_scheduled_time,p_special_instructions,p_urgency,p_request_id) $$;

create function private.provider_booking_reply(p_booking_id uuid,p_accept boolean,p_reason text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pid uuid; booking public.bookings%rowtype; recipient uuid;
begin
 select p.provider_id into pid from public.provider_profiles p join public.users u using(user_id)
 where u.auth_user_id=auth.uid() and u.role='provider' and u.is_active is true and p.verification_status='Verified';
 if pid is null then raise exception 'An active verified provider account is required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,0));
 select * into booking from public.bookings where booking_id=p_booking_id and provider_id=pid for update;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 if p_accept is null then raise exception 'Choose accept or decline'; end if;
 if p_accept and booking.booking_status='Confirmed' and booking.accepted_at is not null then return jsonb_build_object('booking_id',p_booking_id,'status','Confirmed'); end if;
 if booking.booking_status<>'Pending' or booking.request_id is null or booking.reservation_expires_at<=now() or booking.scheduled_datetime<=now()+interval '30 minutes' then raise exception 'This booking request is no longer available'; end if;
 if not p_accept and length(trim(coalesce(p_reason,'')))<5 then raise exception 'Explain why the requested slot cannot be accepted'; end if;
 perform set_config('app.action_reason',case when p_accept then 'Provider accepted the slot; awaiting customer payment.' else trim(p_reason) end,true);
 update public.bookings set booking_status=case when p_accept then 'Confirmed'::public.booking_status else 'Cancelled'::public.booking_status end,
 accepted_at=case when p_accept then now() end,reservation_expires_at=case when p_accept then least(now()+interval '30 minutes',scheduled_datetime) else now() end,
 cancelled_at=case when not p_accept then now() end,cancellation_reason=case when not p_accept then trim(p_reason) end where booking_id=p_booking_id;
 select user_id into recipient from public.customer_profiles where customer_id=booking.customer_id;
 perform private.customer_event(recipient,p_booking_id,'Booking Update',case when p_accept then 'Your slot was accepted' else 'Booking declined' end,
 case when p_accept then 'The provider accepted your slot. Complete FPX payment within 30 minutes to retain it.' else trim(p_reason) end);
 return jsonb_build_object('booking_id',p_booking_id,'status',case when p_accept then 'Confirmed' else 'Cancelled' end);
end $$;
create function public.provider_booking_reply(p_booking_id uuid,p_accept boolean,p_reason text default null) returns jsonb language sql security invoker set search_path='' as $$ select private.provider_booking_reply(p_booking_id,p_accept,p_reason) $$;

create function private.customer_cancel_booking(p_booking_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); booking public.bookings%rowtype; provider_user uuid;
begin
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'Enter a cancellation reason (5-500 characters)'; end if;
 select provider_id into booking.provider_id from public.bookings where booking_id=p_booking_id and customer_id=cid;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(booking.provider_id::text,0));
 select * into booking from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
 if booking.booking_status='Cancelled' then return private.customer_booking_json(p_booking_id,cid); end if;
 if booking.booking_status not in ('Pending','Confirmed') or booking.scheduled_datetime<=now() then raise exception 'This booking can no longer be cancelled. Contact support through a booking dispute.'; end if;
 perform set_config('app.action_reason',trim(p_reason),true);
 update public.bookings set booking_status='Cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason),reservation_expires_at=now() where booking_id=p_booking_id;
 if exists(select 1 from public.payments where booking_id=p_booking_id and payment_status='Success') then
  insert into public.booking_disputes(booking_id,opened_by,subject,description)
  values(p_booking_id,private.current_user_id(),'Paid booking cancellation','Please review the payment refund for this cancellation: '||trim(p_reason))
  on conflict do nothing;
 end if;
 select user_id into provider_user from public.provider_profiles where provider_id=booking.provider_id;
 perform private.customer_event(private.current_user_id(),p_booking_id,'Cancellation','Booking cancelled','Your booking was cancelled. Any collected payment remains recorded; a paid cancellation is sent to administrators for refund review.');
 perform private.customer_event(provider_user,p_booking_id,'Cancellation','Customer cancelled a booking',trim(p_reason));
 return private.customer_booking_json(p_booking_id,cid);
end $$;
create function public.customer_cancel_booking(p_booking_id uuid,p_reason text) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_cancel_booking(p_booking_id,p_reason) $$;

create function private.customer_booking_receipt(p_booking_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare booking jsonb:=private.customer_booking_json(p_booking_id,private.customer_id());
begin
 if coalesce(booking->'payment'->>'payment_status','') not in ('Success','Refunded') then raise exception 'A receipt is available only after a verified payment'; end if;
 return jsonb_build_object('booking',booking,'payment',booking->'payment','currency','MYR');
end $$;
create function public.customer_booking_receipt(p_booking_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_booking_receipt(p_booking_id) $$;

create function private.customer_open_dispute(p_booking_id uuid,p_subject text,p_description text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); did uuid;
begin
 perform 1 from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 if p_subject is null or length(trim(p_subject)) not between 3 and 150 or p_description is null or length(trim(p_description)) not between 10 and 4000 then raise exception 'Enter a subject and a detailed explanation'; end if;
 insert into public.booking_disputes(booking_id,opened_by,subject,description) values(p_booking_id,private.current_user_id(),trim(p_subject),trim(p_description)) returning dispute_id into did;
 perform private.customer_event(private.current_user_id(),p_booking_id,'Booking Update','Dispute submitted','Your dispute is recorded for administrator review.');
 return jsonb_build_object('dispute_id',did);
end $$;
create function public.customer_open_dispute(p_booking_id uuid,p_subject text,p_description text) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_open_dispute(p_booking_id,p_subject,p_description) $$;

create function private.customer_review_eligibility(p_booking_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 return exists(select 1 from public.bookings b join public.payments pay using(booking_id) where b.booking_id=p_booking_id
 and b.customer_id=cid and b.booking_status='Completed' and pay.payment_status='Success')
 and not exists(select 1 from public.reviews where booking_id=p_booking_id);
end $$;
create function public.customer_review_eligibility(p_booking_id uuid) returns boolean language sql stable security invoker set search_path='' as $$ select private.customer_review_eligibility(p_booking_id) $$;
create function private.customer_submit_review(p_booking_id uuid,p_rating integer,p_comment text default null,p_image_url text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); booking public.bookings%rowtype; rid uuid;
begin
 select * into booking from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 if not private.customer_review_eligibility(p_booking_id) then raise exception 'Only completed, paid bookings without an existing review can be reviewed'; end if;
 if p_rating is null or p_rating not between 1 and 5 or length(coalesce(p_comment,''))>4000 then raise exception 'Choose 1-5 stars and a review under 4000 characters'; end if;
 if p_image_url is not null and (split_part(p_image_url,'/',1)<>auth.uid()::text or split_part(p_image_url,'/',2)<>'reviews'
 or split_part(p_image_url,'/',3)<>p_booking_id::text or not exists(select 1 from storage.objects where bucket_id='review-images' and name=p_image_url and owner_id=auth.uid()::text)) then
 raise exception 'Choose your own uploaded review photo' using errcode='42501'; end if;
 insert into public.reviews(booking_id,customer_id,provider_id,rating_score,review_comment,review_image_url,is_verified_booking)
 values(p_booking_id,cid,booking.provider_id,p_rating,nullif(trim(p_comment),''),p_image_url,true) returning review_id into rid;
 perform private.customer_event(private.current_user_id(),p_booking_id,'System','Review submitted','Thank you. Your verified booking review has been saved.');
 return jsonb_build_object('review_id',rid);
end $$;
create function public.customer_submit_review(p_booking_id uuid,p_rating integer,p_comment text default null,p_image_url text default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.customer_submit_review(p_booking_id,p_rating,p_comment,p_image_url) $$;
create function private.customer_my_reviews() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 return coalesce((select jsonb_agg(to_jsonb(item)) from (select r.review_id,r.booking_id,r.rating_score,r.review_comment,r.review_image_url,
 r.created_at,r.moderation_status,r.is_flagged,r.is_verified_booking,b.provider_id,b.service_id,
 coalesce(b.provider_name_snapshot,p.business_name) as business_name,coalesce(b.service_name_snapshot,s.service_name) as service_name
 from public.reviews r join public.bookings b using(booking_id) join public.provider_profiles p on p.provider_id=b.provider_id
 join public.services s on s.service_id=b.service_id where r.customer_id=cid order by r.created_at desc,r.review_id limit 200) item),'[]');
end $$;
create function public.customer_my_reviews() returns jsonb language sql stable security invoker set search_path='' as $$ select private.customer_my_reviews() $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('review-images','review-images',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
update storage.buckets set file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'] where id='profiles';
create function private.customer_review_object_allowed(p_name text,p_write boolean) returns boolean language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 if private.current_user_id() is null then return false; end if;
 if split_part(p_name,'/',1)=auth.uid()::text and split_part(p_name,'/',2)='reviews' then
  select customer_id into cid from public.customer_profiles where user_id=private.current_user_id();
  return exists(select 1 from public.bookings b where b.customer_id=cid and b.booking_id::text=split_part(p_name,'/',3)
  and (not p_write or (b.booking_status='Completed' and exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success')
  and not exists(select 1 from public.reviews r where r.booking_id=b.booking_id))));
 end if;
 return not p_write and exists(select 1 from public.reviews r where r.review_image_url=p_name and r.moderation_status='visible' and r.is_verified_booking is true);
end $$;
revoke all on function private.customer_review_object_allowed(text,boolean) from public,anon;
grant execute on function private.customer_review_object_allowed(text,boolean) to authenticated;
create policy review_image_insert on storage.objects for insert to authenticated
with check(bucket_id='review-images' and private.customer_review_object_allowed(name,true));
create policy review_image_read on storage.objects for select to authenticated
using(bucket_id='review-images' and private.customer_review_object_allowed(name,false));
create policy review_image_delete_unattached on storage.objects for delete to authenticated
using(bucket_id='review-images' and owner_id=auth.uid()::text and private.customer_review_object_allowed(name,true));

-- Explicit grants apply to public INVOKER wrappers and their guarded private implementations.
create function private.provider_booking_list(p_status text default null,p_booking_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare pid uuid;
begin
 select p.provider_id into pid from public.provider_profiles p join public.users u using(user_id)
 where u.auth_user_id=auth.uid() and u.role='provider' and u.is_active is true;
 if pid is null then raise exception 'An active provider account is required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(item)) from (select b.*,
 jsonb_build_object('users',jsonb_build_object('full_name',u.full_name,'phone',case when b.accepted_at is not null then u.phone end)) as customer_profiles,
 jsonb_build_object('service_name',coalesce(b.service_name_snapshot,s.service_name)) as services,
 pay.payment_status,b.booking_status='Pending' and b.reservation_expires_at>now() as can_accept,
 b.booking_status='Confirmed' and pay.payment_status='Success' as can_start
 from public.bookings b join public.customer_profiles c using(customer_id) join public.users u on u.user_id=c.user_id
 join public.services s using(service_id) left join public.payments pay using(booking_id)
 where b.provider_id=pid and (p_status is null or b.booking_status::text=p_status) and (p_booking_id is null or b.booking_id=p_booking_id)
 order by b.scheduled_datetime desc,b.booking_id limit 200) item),'[]');
end $$;
create function public.provider_booking_list(p_status text default null,p_booking_id uuid default null) returns jsonb language sql security invoker set search_path='' as $$ select private.provider_booking_list(p_status,p_booking_id) $$;
create function private.provider_booking_progress(p_booking_id uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare pid uuid; b public.bookings%rowtype; recipient uuid;
begin
 select p.provider_id into pid from public.provider_profiles p join public.users u using(user_id)
 where u.auth_user_id=auth.uid() and u.role='provider' and u.is_active is true and p.verification_status='Verified';
 if pid is null then raise exception 'An active verified provider account is required' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(pid::text,0));
 select * into b from public.bookings where booking_id=p_booking_id and provider_id=pid for update;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 if p_status is null or not ((b.booking_status='Confirmed' and p_status='In-Progress') or (b.booking_status='In-Progress' and p_status='Completed')) then raise exception 'Invalid service progress transition'; end if;
 if not exists(select 1 from public.payments where booking_id=p_booking_id and payment_status='Success') then raise exception 'Customer payment must succeed before service starts'; end if;
 if p_status='In-Progress' and b.scheduled_datetime>now()+interval '1 hour' then raise exception 'This service is not scheduled to start yet'; end if;
 perform set_config('app.action_reason','Provider marked the service '||p_status,true);
 update public.bookings set booking_status=p_status::public.booking_status,started_at=case when p_status='In-Progress' then now() else started_at end,
 completed_at=case when p_status='Completed' then now() else completed_at end where booking_id=p_booking_id;
 select user_id into recipient from public.customer_profiles where customer_id=b.customer_id;
 perform private.customer_event(recipient,p_booking_id,'Booking Update','Service '||p_status,case when p_status='Completed' then 'The provider marked your service completed. You can now leave a verified review or raise a dispute.' else 'The provider has started your service.' end);
end $$;
create function public.provider_booking_progress(p_booking_id uuid,p_status text) returns void language sql security invoker set search_path='' as $$ select private.provider_booking_progress(p_booking_id,p_status) $$;

do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private') and p.proname=any(array[
 'customer_search_services','customer_provider_details','customer_profile_update','customer_delete_address','customer_notification_dismiss',
 'customer_booking_detail','customer_bookings','customer_booking_slots','customer_create_booking','provider_booking_reply',
 'customer_cancel_booking','customer_booking_receipt','customer_open_dispute','customer_review_eligibility','customer_submit_review','customer_my_reviews','provider_booking_list','provider_booking_progress']) loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
-- RLS already restricts notification ownership; dismissed_at is server-write-only.
grant select(dismissed_at) on public.notifications to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
  alter publication supabase_realtime add table public.notifications;
 end if;
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='bookings') then
  alter publication supabase_realtime add table public.bookings;
 end if;
end $$;
