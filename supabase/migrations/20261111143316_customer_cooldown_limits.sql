-- Customer cancellation policy. The customer lock serializes cancellation and
-- all booking inserts, including AI bookings and requests from other devices.
create table private.customer_service_cooldowns (
 customer_id uuid not null references public.customer_profiles(customer_id) on delete cascade,
 service_id uuid not null references public.services(service_id) on delete cascade,
 expires_at timestamptz not null,
 primary key(customer_id,service_id)
);
alter table private.customer_service_cooldowns enable row level security;
revoke all on private.customer_service_cooldowns from public,anon,authenticated;

create function private.enforce_customer_booking_cooldown() returns trigger
language plpgsql security definer set search_path='' as $$
declare retry_at timestamptz;
begin
 perform 1 from public.customer_profiles where customer_id=new.customer_id for update;
 select expires_at into retry_at from private.customer_service_cooldowns
 where customer_id=new.customer_id and service_id=new.service_id;
 if retry_at>clock_timestamp() then
  raise exception 'Wait 30 minutes after cancelling before booking this service again.'
   using errcode='P0001', detail=jsonb_build_object('code','service_cooldown','retry_at',retry_at)::text;
 end if;
 return new;
end $$;
revoke all on function private.enforce_customer_booking_cooldown() from public,anon,authenticated;
create trigger customer_booking_cooldown before insert on public.bookings
 for each row execute function private.enforce_customer_booking_cooldown();

-- Keep only a keyed fingerprint of a deleted customer's normalized email.
-- No raw email or login credentials are retained in the cooldown table.
create table private.customer_email_fingerprint_key (
 singleton boolean primary key default true check(singleton),
 secret text not null default (gen_random_uuid()::text||gen_random_uuid()::text)
);
insert into private.customer_email_fingerprint_key(singleton) values(true);
create table private.customer_email_cooldowns (
 email_fingerprint bytea primary key,
 expires_at timestamptz not null
);
create index customer_email_cooldowns_expiry on private.customer_email_cooldowns(expires_at);
alter table private.customer_email_fingerprint_key enable row level security;
alter table private.customer_email_cooldowns enable row level security;
revoke all on private.customer_email_fingerprint_key,private.customer_email_cooldowns from public,anon,authenticated;

create function private.customer_email_fingerprint(p_email text) returns bytea
language sql stable security definer set search_path='' as $$
 select sha256(convert_to(secret||':'||lower(btrim(p_email)),'UTF8'))
 from private.customer_email_fingerprint_key where singleton
$$;
revoke all on function private.customer_email_fingerprint(text) from public,anon,authenticated;

-- The Auth DELETE and restriction commit together. Preparation/storage failure
-- does not start the clock, and a lost finish-RPC response cannot skip the ban.
create function private.remember_deleted_customer_email() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.email is not null and exists(
  select 1 from private.customer_deletions where auth_user_id=old.id
 ) then
  perform pg_advisory_xact_lock(hashtextextended(lower(btrim(old.email)),720));
  delete from private.customer_email_cooldowns where expires_at<=clock_timestamp();
  insert into private.customer_email_cooldowns(email_fingerprint,expires_at)
   values(private.customer_email_fingerprint(old.email),clock_timestamp()+interval '14 days')
   on conflict(email_fingerprint) do update set expires_at=excluded.expires_at;
 end if;
 return old;
end $$;
revoke all on function private.remember_deleted_customer_email() from public,anon,authenticated;
create trigger remember_deleted_customer_email before delete on auth.users
 for each row execute function private.remember_deleted_customer_email();

create function private.enforce_deleted_customer_email() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.email is null then return new; end if;
 if tg_op='UPDATE' and lower(btrim(new.email)) is not distinct from lower(btrim(old.email)) then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended(lower(btrim(new.email)),720));
 if exists(select 1 from private.customer_email_cooldowns
  where email_fingerprint=private.customer_email_fingerprint(new.email) and expires_at>clock_timestamp()) then
  raise exception 'This email can be used again 14 days after account deletion.' using errcode='P0001';
 end if;
 return new;
end $$;
revoke all on function private.enforce_deleted_customer_email() from public,anon,authenticated;
create trigger enforce_deleted_customer_email before insert or update of email on auth.users
 for each row execute function private.enforce_deleted_customer_email();

-- Minimal registration preflight for readable UI feedback. The Auth trigger is
-- authoritative and also prevents alternate-role and email-change bypasses.
create function private.customer_registration_check(p_email text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if p_email is null or length(p_email)>320 then raise exception 'Enter a valid email address'; end if;
 if exists(select 1 from private.customer_email_cooldowns
  where email_fingerprint=private.customer_email_fingerprint(p_email) and expires_at>clock_timestamp()) then
  raise exception 'This email can be used again 14 days after account deletion.' using errcode='P0001';
 end if;
end $$;
create function public.customer_registration_check(p_email text) returns void
language sql security invoker set search_path='' as $$select private.customer_registration_check(p_email)$$;
revoke all on function private.customer_registration_check(text),public.customer_registration_check(text) from public;
grant execute on function private.customer_registration_check(text),public.customer_registration_check(text) to anon,authenticated;

create or replace function private.customer_cancel_booking(p_booking_id uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); booking public.bookings%rowtype; provider_user uuid;
begin
 if p_reason is null or length(trim(p_reason)) not between 5 and 500 then raise exception 'Enter a cancellation reason (5-500 characters)'; end if;
 -- Match create-booking lock order to prevent cancellation/rebooking races.
 perform 1 from public.customer_profiles where customer_id=cid for update;
 select provider_id into booking.provider_id from public.bookings where booking_id=p_booking_id and customer_id=cid;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(booking.provider_id::text,0));
 select * into booking from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
 if booking.booking_status='Cancelled' then return private.customer_booking_json(p_booking_id,cid); end if;
 if booking.booking_status not in ('Pending','Confirmed') or booking.scheduled_datetime<=now() then raise exception 'This booking can no longer be cancelled. Contact support through a booking dispute.'; end if;
 perform set_config('app.action_reason',trim(p_reason),true);
 update public.bookings set booking_status='Cancelled',cancelled_at=now(),cancellation_reason=trim(p_reason),reservation_expires_at=now() where booking_id=p_booking_id;
 insert into private.customer_service_cooldowns(customer_id,service_id,expires_at)
 values(cid,booking.service_id,clock_timestamp()+interval '30 minutes')
 on conflict(customer_id,service_id) do update set expires_at=excluded.expires_at;
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
