-- Allow the trusted deletion transaction to anonymize booking PII only.
create or replace function private.guard_customer_booking() returns trigger language plpgsql security definer set search_path='' as $$
begin
 -- Deletion preparation has already validated obligations, recorded its private
 -- marker and detached the customer identity. Permit only the exact PII scrub.
 -- Return before taking the provider lock: deletion already holds booking locks,
 -- and ordinary booking writers acquire the provider lock before the booking.
 if tg_op='UPDATE'
 and new.customer_address='Deleted customer'
 and new.customer_coordinates is null and new.special_instructions is null
 and (to_jsonb(new)-array['customer_address','customer_coordinates','special_instructions'])
     = (to_jsonb(old)-array['customer_address','customer_coordinates','special_instructions'])
 and exists(
  select 1 from private.customer_deletions d
  join public.customer_profiles c on c.user_id=d.user_id
  join public.users u on u.user_id=d.user_id
  where c.customer_id=old.customer_id and u.auth_user_id is null and u.is_active is false
 ) then
  return new;
 end if;
 -- Clearing the request token must not turn an app booking into a legacy row
 -- and bypass its immutable contract fields.
 if tg_op='UPDATE' and old.request_id is not null and new.request_id is distinct from old.request_id then
  raise exception 'An existing booking keeps its agreed service, price, address and time';
 end if;
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
