-- Accept both Stripe refund identifier formats while preserving payment, amount and request checks.
create or replace function public.gateway_record_refund(p_refund_id uuid,p_reference text,p_payment_intent text,p_amount_sen bigint,p_currency text,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.refund_requests%rowtype; p public.payments%rowtype; bid uuid; pid uuid; uid uuid; next_status text; refunded numeric;
begin
 if p_reference is null or p_reference !~ '^(re|pyr)_[a-zA-Z0-9]+$' or p_currency is distinct from 'myr' or p_status is null or p_status not in ('pending','requires_action','succeeded','failed','canceled') then raise exception 'Invalid refund confirmation'; end if;
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
