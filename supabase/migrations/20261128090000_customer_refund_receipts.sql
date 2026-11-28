-- A verified payment can issue an email even if Stripe did not supply a receipt link.
create or replace function private.gateway_record_payment_delivery(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text,p_method text,p_email text,p_receipt_url text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; pid uuid;
begin
 result:=private.gateway_record_payment_method(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference,p_method);
 if p_outcome='paid' and p_email is not null and length(p_email)<=254 and p_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 then
  select p.payment_id into pid from public.payments p join private.checkout_attempts a on a.booking_id=p.booking_id
  where a.attempt_id=p_attempt_id and a.state='Paid' and p.fpx_transaction_ref=p_reference and p.payment_status='Success';
  if pid is not null then
   insert into private.delivery_outbox(kind,dedupe_key,payload,expires_at)
   values('email','receipt:'||pid::text,jsonb_build_object('email',p_email,'receipt_url',case when p_receipt_url ~ '^https://pay\.stripe\.com/receipts/[^[:space:]]+$' and length(p_receipt_url)<4096 then p_receipt_url end,'amount_sen',p_amount_sen,'payment_id',pid,'test_mode',true),now()+interval '20 hours')
   on conflict(dedupe_key) do nothing;
  end if;
 end if;
 return result;
end $$;

-- Queue once for each confirmed (including partial) refund. The worker can
-- recover the original Checkout recipient after the payment email is redacted.
create function private.queue_refund_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
declare message_type text := case when new.status='Succeeded' then 'refund' else 'refund_returned' end;
begin
 if message_type='refund_returned' then
  update private.delivery_outbox set state='expired',payload='{}',last_error='refund_returned'
   where dedupe_key='refund-receipt:'||new.refund_id::text and state in ('pending','sending');
 end if;
 insert into private.delivery_outbox(kind,dedupe_key,payload,expires_at)
 select 'email', message_type || '-receipt:' || new.refund_id::text,
   jsonb_build_object('receipt_type',message_type,'email',o.payload->>'email',
     'payment_intent',p.fpx_transaction_ref,'amount_sen',(new.amount*100)::bigint,'test_mode',true),
   now()+interval '20 hours'
 from public.payments p
 left join private.delivery_outbox o on o.kind='email' and o.dedupe_key='receipt:'||p.payment_id::text
 where p.payment_id=new.payment_id
 on conflict(dedupe_key) do nothing;
 return new;
end $$;
revoke all on function private.queue_refund_receipt() from public,anon,authenticated;
create trigger confirmed_refund_receipt after update of status on public.refund_requests
 for each row when (old.status is distinct from new.status and (new.status='Succeeded' or (old.status='Succeeded' and new.status in ('Failed','Cancelled'))))
 execute function private.queue_refund_receipt();
