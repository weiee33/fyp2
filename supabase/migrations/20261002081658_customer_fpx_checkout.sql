-- Stripe FPX test checkout: a client can request a quote, never mark payment paid.
create table private.checkout_attempts(
 attempt_id uuid primary key default gen_random_uuid(),
 booking_id uuid not null references public.bookings(booking_id),
 amount_sen bigint not null check(amount_sen>0),
 state text not null default 'Creating' check(state in ('Creating','Open','Paid','Failed','Expired')),
 gateway_session_id text unique,
 checkout_url text,
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);
create index checkout_booking_idx on private.checkout_attempts(booking_id,created_at desc);
create unique index checkout_one_active_idx on private.checkout_attempts(booking_id) where state in ('Creating','Open');
create table private.payment_gateway_events(
 event_id text primary key,
 attempt_id uuid not null references private.checkout_attempts(attempt_id),
 outcome text not null,
 received_at timestamptz not null default now()
);
create index payment_gateway_attempt_idx on private.payment_gateway_events(attempt_id);
alter table private.checkout_attempts enable row level security;
alter table private.payment_gateway_events enable row level security;
revoke all on private.checkout_attempts,private.payment_gateway_events from public,anon,authenticated;

create function private.customer_prepare_checkout(p_booking_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); b public.bookings%rowtype; attempt private.checkout_attempts%rowtype; mail text;
begin
 select * into b from public.bookings where booking_id=p_booking_id and customer_id=cid;
 if not found then raise exception 'Booking not found' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(b.provider_id::text,0));
 select * into b from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
 if b.booking_status<>'Confirmed' or b.accepted_at is null then raise exception 'The provider must accept your requested slot before payment'; end if;
 if b.reservation_expires_at<=now() or b.scheduled_datetime<=now()+interval '35 minutes' then raise exception 'The payment window expired or the appointment is too close. Please request another slot.'; end if;
 if exists(select 1 from public.payments where booking_id=p_booking_id and payment_status in ('Success','Refunded')) then raise exception 'This booking already has a verified payment'; end if;
 update private.checkout_attempts set state='Expired' where booking_id=p_booking_id and state in ('Creating','Open') and expires_at<=now();
 select * into attempt from private.checkout_attempts where booking_id=p_booking_id and state in ('Creating','Open') for update;
 if not found then
  if (select count(*) from private.checkout_attempts where booking_id=p_booking_id and created_at>now()-interval '1 hour')>=5 then raise exception 'Too many checkout attempts. Please try again later.'; end if;
  insert into private.checkout_attempts(booking_id,amount_sen,expires_at) values(p_booking_id,(b.total_amount*100)::bigint,now()+interval '31 minutes') returning * into attempt;
  update public.bookings set reservation_expires_at=attempt.expires_at+interval '2 minutes' where booking_id=p_booking_id;
 end if;
 select u.email into mail from public.customer_profiles c join public.users u using(user_id) where c.customer_id=cid;
 return to_jsonb(attempt)||jsonb_build_object('customer_email',mail,'service_name',b.service_name_snapshot,'currency','myr');
end $$;
create function public.customer_prepare_checkout(p_booking_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.customer_prepare_checkout(p_booking_id) $$;
revoke all on function private.customer_prepare_checkout(uuid),public.customer_prepare_checkout(uuid) from public,anon;
grant execute on function private.customer_prepare_checkout(uuid),public.customer_prepare_checkout(uuid) to authenticated;

create function private.gateway_attach_checkout(p_attempt_id uuid,p_session_id text,p_checkout_url text,p_expires_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare a private.checkout_attempts%rowtype;
begin
 if p_session_id is null or p_session_id not like 'cs_test_%' or p_checkout_url is null or p_checkout_url !~ '^https://checkout\.stripe\.com/' then raise exception 'Invalid test checkout response'; end if;
 select * into a from private.checkout_attempts where attempt_id=p_attempt_id for update;
 if not found then raise exception 'Checkout attempt not found'; end if;
 if a.gateway_session_id is not null and a.gateway_session_id<>p_session_id then raise exception 'Checkout attempt is already linked'; end if;
 if p_expires_at is null or abs(extract(epoch from p_expires_at-a.expires_at))>2 then raise exception 'Checkout expiry mismatch'; end if;
 update private.checkout_attempts set gateway_session_id=p_session_id,checkout_url=p_checkout_url,
 state=case when state='Creating' then 'Open' else state end where attempt_id=p_attempt_id;
end $$;
create function public.gateway_attach_checkout(p_attempt_id uuid,p_session_id text,p_checkout_url text,p_expires_at timestamptz) returns void language sql security invoker set search_path='' as $$ select private.gateway_attach_checkout(p_attempt_id,p_session_id,p_checkout_url,p_expires_at) $$;

create function private.gateway_record_payment(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.checkout_attempts%rowtype; b public.bookings%rowtype; uid uuid; pid uuid;
begin
 if p_event_id is null or length(p_event_id)>255 or p_outcome is null or p_outcome not in ('paid','failed','expired') then raise exception 'Invalid gateway event'; end if;
 select * into a from private.checkout_attempts where attempt_id=p_attempt_id;
 if not found then raise exception 'Unknown checkout attempt'; end if;
 select * into b from public.bookings where booking_id=a.booking_id;
 perform pg_advisory_xact_lock(hashtextextended(b.provider_id::text,0));
 select * into b from public.bookings where booking_id=a.booking_id for update;
 select * into a from private.checkout_attempts where attempt_id=p_attempt_id for update;
 if a.gateway_session_id is null or a.gateway_session_id is distinct from p_session_id or p_amount_sen is distinct from a.amount_sen
 or p_amount_sen is distinct from (b.total_amount*100)::bigint or p_currency is distinct from 'myr' then raise exception 'Gateway amount, currency or checkout identity mismatch'; end if;
 insert into private.payment_gateway_events(event_id,attempt_id,outcome) values(p_event_id,p_attempt_id,p_outcome) on conflict do nothing;
 if not found then return jsonb_build_object('duplicate',true); end if;
 if a.state='Paid' then return jsonb_build_object('already_paid',true); end if;
 if p_outcome<>'paid' then
  update private.checkout_attempts set state=case when p_outcome='expired' then 'Expired' else 'Failed' end where attempt_id=p_attempt_id;
  return jsonb_build_object('recorded',true,'status',p_outcome);
 end if;
 if p_reference is null or length(p_reference) not between 3 and 200 then raise exception 'A gateway payment reference is required'; end if;
 if exists(select 1 from public.payments where booking_id=b.booking_id and payment_status in ('Success','Refunded')) then
  raise exception 'Another payment already exists for this booking; reconcile the duplicate charge'; end if;
 -- Never confirm a cancelled/expired appointment merely because a delayed payment arrived.
 if b.booking_status<>'Confirmed' or b.accepted_at is null or b.reservation_expires_at<=now() then
  perform set_config('app.action_reason','Gateway payment arrived after the slot was released; refund review required.',true);
  update public.bookings set booking_status='Cancelled',cancelled_at=coalesce(cancelled_at,now()),cancellation_reason='Payment received after reservation ended' where booking_id=b.booking_id;
 end if;
 insert into public.payments(booking_id,customer_id,payment_amount,payment_method,payment_status,escrow_held,payment_timestamp,fpx_transaction_ref)
 values(b.booking_id,b.customer_id,a.amount_sen::numeric/100,'FPX','Success',false,now(),p_reference)
 on conflict(booking_id) do update set payment_amount=excluded.payment_amount,payment_status='Success',payment_timestamp=excluded.payment_timestamp,
 fpx_transaction_ref=excluded.fpx_transaction_ref,escrow_held=false returning payment_id into pid;
 update private.checkout_attempts set state='Paid' where attempt_id=p_attempt_id;
 select user_id into uid from public.customer_profiles where customer_id=b.customer_id;
 if b.booking_status<>'Confirmed' or b.accepted_at is null or b.reservation_expires_at<=now() then
  insert into public.booking_disputes(booking_id,opened_by,subject,description)
  values(b.booking_id,uid,'Payment requires refund review','A verified FPX payment arrived after this booking was cancelled or its reserved slot expired. Please reconcile and refund it.') on conflict do nothing;
  perform private.customer_event(uid,b.booking_id,'Payment','Payment received; review required','Your payment is recorded but the appointment is unavailable. A refund review has been opened.');
 else
  update public.bookings set reservation_expires_at=null where booking_id=b.booking_id;
  perform private.customer_event(uid,b.booking_id,'Payment','FPX payment verified','Your payment was verified. Your accepted appointment is now paid, and its receipt is available.');
  select user_id into uid from public.provider_profiles where provider_id=b.provider_id;
  perform private.customer_event(uid,b.booking_id,'Payment','Customer payment verified','The accepted booking is now paid. View the booking for the scheduled service details.');
 end if;
 return jsonb_build_object('recorded',true,'payment_id',pid);
end $$;
create function public.gateway_record_payment(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text) returns jsonb
language sql security invoker set search_path='' as $$ select private.gateway_record_payment(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference) $$;
revoke all on function private.gateway_attach_checkout(uuid,text,text,timestamptz),public.gateway_attach_checkout(uuid,text,text,timestamptz),
 private.gateway_record_payment(text,uuid,text,bigint,text,text,text),public.gateway_record_payment(text,uuid,text,bigint,text,text,text) from public,anon,authenticated;
grant usage on schema private to service_role;
grant execute on function private.gateway_attach_checkout(uuid,text,text,timestamptz),public.gateway_attach_checkout(uuid,text,text,timestamptz),
 private.gateway_record_payment(text,uuid,text,bigint,text,text,text),public.gateway_record_payment(text,uuid,text,bigint,text,text,text) to service_role;
