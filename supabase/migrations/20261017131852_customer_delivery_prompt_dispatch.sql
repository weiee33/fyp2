-- Read status is an in-app UI state, not proof that Android displayed an alert.
-- Retire old skipped prompts rather than replaying a burst of historical phone alerts.
update private.delivery_outbox set state='expired',payload='{}',last_error='superseded_by_delivery_fix'
where kind='push' and state='pending' and attempts=0;

create or replace function private.queue_customer_push() returns trigger
language plpgsql security definer set search_path='' as $$
declare deadline timestamptz:=now()+interval '6 hours';
begin
 if new.booking_id is null or new.title not in ('Booking requested','Your slot was accepted','Booking declined','Booking cancelled','Payment verified','FPX payment verified','Payment received; review required','Service Completed') then return new; end if;
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

create or replace function private.claim_deliveries(p_kind text) returns jsonb
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
  and (o.kind='email' or (s.id is not null and (s.not_after is null or s.not_after>now()) and u.is_active and n.dismissed_at is null
    and (n.title<>'Your slot was accepted' or (b.booking_status='Confirmed' and b.reservation_expires_at>now()
      and not exists(select 1 from public.payments p where p.booking_id=b.booking_id and p.payment_status='Success')))))
  order by o.available_at limit 5 for update of o skip locked
 ), claimed as (
  update private.delivery_outbox o set state='sending',lease_id=gen_random_uuid(),attempts=attempts+1,available_at=now()+interval '5 minutes'
  from due where o.id=due.id returning o.*
 ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('token',d.token)),'[]'::jsonb) into result from claimed c left join private.push_devices d on d.id=c.device_id;
 return result;
end $$;

create or replace function private.delivery_configuration() returns jsonb
language sql security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(upper(replace(name,'home_serve_','')),decrypted_secret),'{}'::jsonb)
 from vault.decrypted_secrets where name in (
  'home_serve_delivery_worker_secret','home_serve_firebase_service_account',
  'home_serve_delivery_push_enabled','home_serve_delivery_email_enabled',
  'home_serve_resend_api_key','home_serve_receipt_from_email','home_serve_receipt_test_recipient')
$$;

-- pg_net sends only after the booking/payment transaction commits. The existing
-- minute scheduler remains the retry/recovery path if immediate dispatch fails.
create function private.dispatch_customer_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
declare project_url text; worker_secret text;
begin
 if not exists(select 1 from queued) then return null; end if;
 select decrypted_secret into project_url from vault.decrypted_secrets where name='home_serve_project_url';
 select decrypted_secret into worker_secret from vault.decrypted_secrets where name='home_serve_delivery_worker_secret';
 if project_url is null or worker_secret is null then return null; end if;
 perform net.http_post(url:=project_url||'/functions/v1/customer-delivery',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||worker_secret),
  body:='{}'::jsonb,timeout_milliseconds:=120000);
 return null;
exception when others then
 -- The committed durable job will be recovered by the scheduler.
 raise warning 'Immediate customer delivery deferred to scheduler';
 return null;
end $$;
revoke all on function private.dispatch_customer_delivery() from public,anon,authenticated;
create trigger dispatch_customer_delivery after insert on private.delivery_outbox
referencing new table as queued for each statement execute function private.dispatch_customer_delivery();
notify pgrst,'reload schema';
