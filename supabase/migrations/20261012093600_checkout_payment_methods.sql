-- Bind an attempt to one checkout channel so switching cannot create parallel charges.
alter table private.checkout_attempts add column checkout_channel text not null default 'fpx' check(checkout_channel in ('fpx','wallet_card'));
alter table public.payments add column gateway_method text check(gateway_method in ('fpx','card','grabpay'));
create function private.customer_prepare_payment_checkout(p_booking_id uuid,p_channel text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); b public.bookings%rowtype; attempt private.checkout_attempts%rowtype; mail text;
begin
 if p_channel is null or p_channel not in ('fpx','wallet_card') then raise exception 'Invalid payment option'; end if;
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
  insert into private.checkout_attempts(booking_id,amount_sen,expires_at,checkout_channel) values(p_booking_id,(b.total_amount*100)::bigint,now()+interval '31 minutes',p_channel) returning * into attempt;
  update public.bookings set reservation_expires_at=attempt.expires_at+interval '2 minutes' where booking_id=p_booking_id;
 end if;
 if attempt.checkout_channel<>p_channel then raise exception 'A % checkout is already reserved. Continue that option or wait until its payment window ends before switching.',case when attempt.checkout_channel='fpx' then 'FPX' else 'Cards / GrabPay' end; end if;
 select u.email into mail from public.customer_profiles c join public.users u using(user_id) where c.customer_id=cid;
 return to_jsonb(attempt)||jsonb_build_object('customer_email',mail,'service_name',b.service_name_snapshot,'currency','myr');
end $$;

create function public.customer_prepare_payment_checkout(p_booking_id uuid,p_channel text default 'fpx') returns jsonb
language sql security invoker set search_path='' as $$select private.customer_prepare_payment_checkout(p_booking_id,p_channel)$$;
create or replace function private.customer_prepare_checkout(p_booking_id uuid) returns jsonb
language sql security definer set search_path='' as $$select private.customer_prepare_payment_checkout(p_booking_id,'fpx')$$;
revoke all on function private.customer_prepare_payment_checkout(uuid,text),public.customer_prepare_payment_checkout(uuid,text) from public,anon;
grant execute on function private.customer_prepare_payment_checkout(uuid,text),public.customer_prepare_payment_checkout(uuid,text) to authenticated;

-- The legacy writer retains its access controls and amount/idempotency/late-payment handling.
-- This wrapper records the actual server-verified Stripe method in the same transaction.
create function private.gateway_record_payment_method(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text,p_method text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if p_outcome='paid' and (p_method is null or p_method not in ('fpx','card','grabpay')) then raise exception 'Unsupported verified payment method'; end if;
 result:=private.gateway_record_payment(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference);
 if result ? 'payment_id' then
   update public.payments set gateway_method=p_method,payment_method=case p_method when 'fpx' then 'FPX'::public.payment_method when 'card' then 'CreditCard'::public.payment_method else 'E-Wallet'::public.payment_method end
   where payment_id=(result->>'payment_id')::uuid;
 end if;
 return result;
end $$;
create function public.gateway_record_payment_method(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text,p_method text) returns jsonb
language sql security invoker set search_path='' as $$select private.gateway_record_payment_method(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference,p_method)$$;
revoke all on function private.gateway_record_payment_method(text,uuid,text,bigint,text,text,text,text),public.gateway_record_payment_method(text,uuid,text,bigint,text,text,text,text) from public,anon,authenticated;
grant execute on function private.gateway_record_payment_method(text,uuid,text,bigint,text,text,text,text),public.gateway_record_payment_method(text,uuid,text,bigint,text,text,text,text) to service_role;
-- Keep existing receipt and detail shape while adding method and checkout channel.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.customer_booking_json(uuid,uuid)'::regprocedure);
 body:=replace(body,'''payment_method'', pay.payment_method','''gateway_method'', pay.gateway_method, ''payment_method'', pay.payment_method');
 body:=replace(body,'''payment_method'',pay.payment_method','''gateway_method'',pay.gateway_method,''payment_method'',pay.payment_method');
 body:=replace(body,'''has_review'',exists','''checkout_channel'',(select ca.checkout_channel from private.checkout_attempts ca where ca.booking_id=b.booking_id and ca.state in (''Creating'',''Open'') and ca.expires_at>now() limit 1),''has_review'',exists');
 execute body;
 body:=pg_get_functiondef('private.gateway_record_payment(text,uuid,text,bigint,text,text,text)'::regprocedure);
 body:=replace(body,'FPX payment verified','Payment verified');
 body:=replace(body,'A verified FPX payment arrived','A verified payment arrived');
 execute body;
end $$;
notify pgrst,'reload schema';
