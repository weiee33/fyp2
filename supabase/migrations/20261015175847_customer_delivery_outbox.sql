-- Delivery data is private. Clients can only register their own authenticated device.
create table private.push_devices (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.users(user_id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 token text not null unique check(length(token) between 32 and 4096),
 language text not null default 'en' check(language in ('en','zh','ms')),
 updated_at timestamptz not null default now()
);
create index push_devices_user_idx on private.push_devices(user_id);
create index push_devices_session_idx on private.push_devices(session_id);
create table private.delivery_outbox (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('push','email')),
 dedupe_key text not null unique,
 device_id uuid references private.push_devices(id) on delete cascade,
 notification_id uuid references public.notifications(notification_id) on delete cascade,
 payload jsonb not null,
 state text not null default 'pending' check(state in ('pending','sending','sent','failed','expired')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(),
 expires_at timestamptz not null,
 lease_id uuid,
 last_error text,
 sent_at timestamptz,
 created_at timestamptz not null default now()
);
create index delivery_due_idx on private.delivery_outbox(available_at) where state in ('pending','sending');
create index delivery_device_idx on private.delivery_outbox(device_id);
create index delivery_notification_idx on private.delivery_outbox(notification_id);
alter table private.push_devices enable row level security;
alter table private.delivery_outbox enable row level security;
revoke all on private.push_devices,private.delivery_outbox from public,anon,authenticated;

create function private.customer_register_push(p_token text,p_language text) returns void
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid; sid uuid:=(auth.jwt()->>'session_id')::uuid;
begin
 select user_id into uid from public.customer_profiles where customer_id=cid;
 if uid is null or sid is null or not exists(select 1 from auth.sessions where id=sid and user_id=auth.uid()) then
  raise exception 'Sign in to enable phone alerts' using errcode='42501';
 end if;
 if p_token is null or length(p_token) not between 32 and 4096 or p_token ~ '[[:space:]]' or p_language is null or p_language not in ('en','zh','ms') then raise exception 'Invalid device registration'; end if;
 -- Reassignment invalidates any deliveries queued for the previous account/session.
 delete from private.push_devices where token=p_token and (user_id<>uid or session_id<>sid);
 insert into private.push_devices(user_id,session_id,token,language) values(uid,sid,p_token,p_language)
 on conflict(token) do update set language=excluded.language,updated_at=now();
 -- Bound registrations to prevent an authenticated account creating an unbounded fan-out.
 delete from private.push_devices where id in (select id from private.push_devices where user_id=uid order by updated_at desc offset 5);
end $$;
create function public.customer_register_push(p_token text,p_language text default 'en') returns void
language sql security invoker set search_path='' as $$select private.customer_register_push(p_token,p_language)$$;
create function private.customer_unregister_push(p_token text) returns void
language sql security definer set search_path='' as $$delete from private.push_devices where token=p_token and user_id=private.current_user_id()$$;
create function public.customer_unregister_push(p_token text) returns void
language sql security invoker set search_path='' as $$select private.customer_unregister_push(p_token)$$;
revoke all on function private.customer_register_push(text,text),public.customer_register_push(text,text),private.customer_unregister_push(text),public.customer_unregister_push(text) from public,anon;
grant execute on function private.customer_register_push(text,text),public.customer_register_push(text,text),private.customer_unregister_push(text),public.customer_unregister_push(text) to authenticated;

create function private.queue_customer_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare deadline timestamptz:=now()+interval '6 hours';
begin
 if new.booking_id is null or new.title not in ('Your slot was accepted','Booking declined','Booking cancelled','Payment verified','FPX payment verified','Payment received; review required','Service Completed') then return new; end if;
 if not exists(select 1 from public.users where user_id=new.user_id and role='customer' and is_active) then return new; end if;
 if new.title='Your slot was accepted' then
  select least(deadline,reservation_expires_at) into deadline from public.bookings where booking_id=new.booking_id;
 end if;
 if deadline is null or deadline<=now() then return new; end if;
 insert into private.delivery_outbox(kind,dedupe_key,device_id,notification_id,payload,expires_at)
 select 'push',new.notification_id::text||':'||d.id::text,d.id,new.notification_id,
 jsonb_build_object('title',new.title,'language',d.language,'booking_id',new.booking_id),deadline
 from private.push_devices d join auth.sessions s on s.id=d.session_id
 where d.user_id=new.user_id and d.updated_at>now()-interval '60 days'
 and (s.not_after is null or s.not_after>now()) on conflict(dedupe_key) do nothing;
 return new;
end $$;
revoke all on function private.queue_customer_push() from public,anon,authenticated;
create trigger customer_push_delivery after insert on public.notifications for each row execute function private.queue_customer_push();

-- Payment and receipt enqueue commit together. Duplicate Stripe events cannot create another email.
create function private.gateway_record_payment_delivery(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text,p_method text,p_email text,p_receipt_url text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb; pid uuid;
begin
 result:=private.gateway_record_payment_method(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference,p_method);
 if p_outcome='paid' and p_email is not null and length(p_email)<=254 and p_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
 and p_receipt_url ~ '^https://pay\.stripe\.com/receipts/[^[:space:]]+$' and length(p_receipt_url)<4096 then
  select p.payment_id into pid from public.payments p join private.checkout_attempts a on a.booking_id=p.booking_id
  where a.attempt_id=p_attempt_id and a.state='Paid' and p.fpx_transaction_ref=p_reference and p.payment_status='Success';
  if pid is not null then
   insert into private.delivery_outbox(kind,dedupe_key,payload,expires_at)
   values('email','receipt:'||pid::text,jsonb_build_object('email',p_email,'receipt_url',p_receipt_url,'amount_sen',p_amount_sen,'payment_id',pid,'test_mode',true),now()+interval '20 hours')
   on conflict(dedupe_key) do nothing;
  end if;
 end if;
 return result;
end $$;
create function public.gateway_record_payment_delivery(p_event_id text,p_attempt_id uuid,p_session_id text,p_amount_sen bigint,p_currency text,p_outcome text,p_reference text,p_method text,p_email text,p_receipt_url text) returns jsonb
language sql security invoker set search_path='' as $$select private.gateway_record_payment_delivery(p_event_id,p_attempt_id,p_session_id,p_amount_sen,p_currency,p_outcome,p_reference,p_method,p_email,p_receipt_url)$$;

create function private.claim_deliveries(p_kind text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update private.delivery_outbox set state='expired',payload='{}',last_error='expired'
 where state in ('pending','sending') and expires_at<=now();
 -- Erase recipient data after the operational retention period; keep dedupe tombstones.
 update private.delivery_outbox set payload='{}' where state in ('sent','failed') and created_at<now()-interval '7 days' and payload<>'{}'::jsonb;
 delete from private.push_devices where updated_at<now()-interval '60 days';
 with due as (
  select o.id from private.delivery_outbox o
  left join private.push_devices d on d.id=o.device_id
  left join auth.sessions s on s.id=d.session_id
  left join public.users u on u.user_id=d.user_id
  left join public.notifications n on n.notification_id=o.notification_id
  left join public.bookings b on b.booking_id=n.booking_id
  where o.kind=p_kind and o.state in ('pending','sending') and o.available_at<=now() and o.expires_at>now() and o.attempts<8
  and (o.kind='email' or (s.id is not null and (s.not_after is null or s.not_after>now()) and u.is_active and not n.is_read and n.dismissed_at is null
    and (n.title<>'Your slot was accepted' or (b.booking_status='Confirmed' and b.reservation_expires_at>now()
      and not exists(select 1 from public.payments p where p.booking_id=b.booking_id and p.payment_status='Success')))))
  order by o.available_at limit 5 for update of o skip locked
 ), claimed as (
  update private.delivery_outbox o set state='sending',lease_id=gen_random_uuid(),attempts=attempts+1,available_at=now()+interval '5 minutes'
  from due where o.id=due.id returning o.*
 ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('token',d.token)),'[]'::jsonb) into result from claimed c left join private.push_devices d on d.id=c.device_id;
 return result;
end $$;
create function public.claim_deliveries(p_kind text) returns jsonb
language sql security invoker set search_path='' as $$select private.claim_deliveries(p_kind)$$;
create function private.finish_delivery(p_id uuid,p_lease uuid,p_result text) returns void
language plpgsql security definer set search_path='' as $$
declare did uuid;
begin
 if p_result not in ('sent','retry','invalid_token','rejected') or p_result is null then raise exception 'Invalid delivery result'; end if;
 update private.delivery_outbox set state=case when p_result='sent' then 'sent' when p_result<>'retry' or attempts>=8 then 'failed' else 'pending' end,
 sent_at=case when p_result='sent' then now() else null end,last_error=case when p_result='sent' then null else p_result end,
 available_at=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer)),lease_id=null
 where id=p_id and lease_id=p_lease and state='sending' returning device_id into did;
 if p_result='invalid_token' and did is not null then delete from private.push_devices where id=did; end if;
end $$;
create function public.finish_delivery(p_id uuid,p_lease uuid,p_result text) returns void
language sql security invoker set search_path='' as $$select private.finish_delivery(p_id,p_lease,p_result)$$;
revoke all on function private.gateway_record_payment_delivery(text,uuid,text,bigint,text,text,text,text,text,text),public.gateway_record_payment_delivery(text,uuid,text,bigint,text,text,text,text,text,text),private.claim_deliveries(text),public.claim_deliveries(text),private.finish_delivery(uuid,uuid,text),public.finish_delivery(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.gateway_record_payment_delivery(text,uuid,text,bigint,text,text,text,text,text,text),public.gateway_record_payment_delivery(text,uuid,text,bigint,text,text,text,text,text,text),private.claim_deliveries(text),public.claim_deliveries(text),private.finish_delivery(uuid,uuid,text),public.finish_delivery(uuid,uuid,text) to service_role;
-- Credentials are provisioned separately, never embedded in a migration.
create function private.delivery_configuration() returns jsonb
language sql security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(upper(replace(name,'home_serve_','')),decrypted_secret),'{}'::jsonb)
 from vault.decrypted_secrets where name in (
  'home_serve_delivery_worker_secret','home_serve_firebase_service_account',
  'home_serve_delivery_push_enabled','home_serve_delivery_email_enabled',
  'home_serve_resend_api_key','home_serve_receipt_from_email')
$$;
create function public.delivery_configuration() returns jsonb
language sql security invoker set search_path='' as $$select private.delivery_configuration()$$;
revoke all on function private.delivery_configuration(),public.delivery_configuration() from public,anon,authenticated;
grant execute on function private.delivery_configuration(),public.delivery_configuration() to service_role;

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
select cron.schedule('home-serve-delivery','* * * * *',$cron$
 select net.http_post(
  url:=(select decrypted_secret from vault.decrypted_secrets where name='home_serve_project_url')||'/functions/v1/customer-delivery',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||
   (select decrypted_secret from vault.decrypted_secrets where name='home_serve_delivery_worker_secret')),
  body:='{}'::jsonb,timeout_milliseconds:=120000)
 where exists(select 1 from vault.secrets where name='home_serve_delivery_worker_secret');
$cron$);
notify pgrst,'reload schema';
