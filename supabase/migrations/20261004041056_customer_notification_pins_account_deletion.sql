-- Customer-owned notification state; preserve the existing RLS ownership boundary.
alter table public.notifications add column is_pinned boolean not null default false;
grant select(is_pinned) on public.notifications to authenticated;
create index notifications_customer_pinned_idx on public.notifications(user_id,is_pinned desc,created_at desc,notification_id) where dismissed_at is null;
create function private.customer_notification_pin(p_notification_id uuid,p_pinned boolean)
returns void language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 if p_pinned is null then raise exception 'Choose pin or unpin'; end if;
 update public.notifications set is_pinned=p_pinned where notification_id=p_notification_id and dismissed_at is null
 and user_id=(select user_id from public.customer_profiles where customer_id=cid);
 if not found then raise exception 'Notification not found' using errcode='42501'; end if;
end $$;
create function public.customer_notification_pin(p_notification_id uuid,p_pinned boolean)
returns void language sql security invoker set search_path='' as $$select private.customer_notification_pin(p_notification_id,p_pinned)$$;
revoke all on function private.customer_notification_pin(uuid,boolean),public.customer_notification_pin(uuid,boolean) from public,anon;
grant execute on function private.customer_notification_pin(uuid,boolean),public.customer_notification_pin(uuid,boolean) to authenticated;

-- A durable retry record: only the trusted Edge function may access deletion work.
-- No password, token or email is stored in this record.
create table private.customer_deletions(auth_user_id uuid primary key, user_id uuid not null unique,
 requested_at timestamptz not null default now(), completed_at timestamptz);
alter table private.customer_deletions enable row level security;
revoke all on private.customer_deletions from public,anon,authenticated;

create function private.customer_delete_prepare(p_auth_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid; cid uuid; prior private.customer_deletions%rowtype;
begin
 if p_auth_id is null then raise exception 'Sign in again' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_auth_id::text,719));
 select * into prior from private.customer_deletions where auth_user_id=p_auth_id;
 if found then return jsonb_build_object('prepared',true,'completed',prior.completed_at is not null); end if;
 select u.user_id,c.customer_id into uid,cid from public.users u join public.customer_profiles c using(user_id)
 join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_auth_id and u.role='customer' and u.is_active is true and a.email_confirmed_at is not null;
 if uid is null then raise exception 'An active verified customer account is required' using errcode='42501'; end if;
 -- Same customer lock used by booking creation; then lock bookings before examining payment state.
 perform 1 from public.customer_profiles where customer_id=cid for update;
 perform 1 from public.bookings where customer_id=cid order by booking_id for update;
 perform 1 from public.users where user_id=uid for update;
 if exists(select 1 from public.bookings where customer_id=cid and booking_status in ('Pending','Confirmed','In-Progress'))
 or exists(select 1 from public.booking_disputes d join public.bookings b using(booking_id) where b.customer_id=cid and d.status in ('Open','Under Review'))
 or exists(select 1 from private.checkout_attempts a join public.bookings b using(booking_id) where b.customer_id=cid and a.state in ('Creating','Open')) then
  raise exception 'Finish or cancel your active bookings and resolve pending payments or disputes before deleting your account';
 end if;
 insert into private.customer_deletions(auth_user_id,user_id) values(p_auth_id,uid);
 -- Detach before Auth deletion. Old JWTs immediately lose the application's active identity.
 update public.users set auth_user_id=null,email='deleted-'||uid::text||'@deleted.invalid',phone=null,password_hash=null,
 full_name='Deleted customer',profile_photo_url=null,is_active=false,email_verified=false,phone_verified=false,last_login_at=null where user_id=uid;
 update public.customer_profiles set default_address=null,location_coordinates=null,service_preferences='{}',bio=null,gender=null,birthday=null where customer_id=cid;
 delete from public.saved_addresses where customer_id=cid;
 delete from private.notification_outbox where recipient_user_id=uid;
 delete from public.notifications where user_id=uid;
 delete from public.otp_verifications where user_id=uid;
 update public.bookings set customer_address='Deleted customer',customer_coordinates=null,special_instructions=null where customer_id=cid;
 update public.reviews set review_comment=null,review_image_url=null where customer_id=cid;
 update public.chat_messages set body='[Message removed: account deleted]' where sender_id=uid;
 update public.chat_members set hidden=true,blocked=true where user_id=uid;
 return jsonb_build_object('prepared',true,'completed',false);
end $$;
create function public.customer_delete_prepare(p_auth_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.customer_delete_prepare(p_auth_id)$$;

create function private.customer_delete_objects(p_auth_id uuid) returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'name',name)),'[]') from
 (select o.bucket_id,o.name from storage.objects o where exists(select 1 from private.customer_deletions d where d.auth_user_id=p_auth_id)
 and (o.owner_id=p_auth_id::text or (o.bucket_id in ('profiles','review-images','reviews_bucket') and split_part(o.name,'/',1)=p_auth_id::text))
 order by o.bucket_id,o.name limit 100) s
$$;
create function public.customer_delete_objects(p_auth_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.customer_delete_objects(p_auth_id)$$;
create function private.customer_delete_finish(p_auth_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from auth.users where id=p_auth_id) then raise exception 'Authentication deletion has not completed'; end if;
 update private.customer_deletions set completed_at=coalesce(completed_at,now()) where auth_user_id=p_auth_id;
end $$;
create function public.customer_delete_finish(p_auth_id uuid) returns void language sql security invoker set search_path='' as $$select private.customer_delete_finish(p_auth_id)$$;
revoke all on function private.customer_delete_prepare(uuid),public.customer_delete_prepare(uuid),private.customer_delete_objects(uuid),public.customer_delete_objects(uuid),private.customer_delete_finish(uuid),public.customer_delete_finish(uuid) from public,anon,authenticated;
grant execute on function private.customer_delete_prepare(uuid),public.customer_delete_prepare(uuid),private.customer_delete_objects(uuid),public.customer_delete_objects(uuid),private.customer_delete_finish(uuid),public.customer_delete_finish(uuid) to service_role;

-- Block in-flight customer writes that started before account deletion obtained its locks.
create function private.customer_booking_active_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.customer_profiles c join public.users u using(user_id)
 where c.customer_id=new.customer_id and u.is_active is true and u.auth_user_id is not null) then
 raise exception 'This customer account is no longer active' using errcode='42501'; end if;
 return new;
end $$;
revoke all on function private.customer_booking_active_guard() from public,anon,authenticated;
create trigger customer_booking_active_guard before insert on public.bookings for each row execute function private.customer_booking_active_guard();

-- Shared cache/rate gate for address lookups, across all app devices.
create table private.customer_geocode_cache(cache_key text primary key, result jsonb not null, expires_at timestamptz not null);
create table private.customer_geocode_gate(singleton boolean primary key default true check(singleton), next_at timestamptz not null);
insert into private.customer_geocode_gate values(true,now());
alter table private.customer_geocode_cache enable row level security;
alter table private.customer_geocode_gate enable row level security;
revoke all on private.customer_geocode_cache,private.customer_geocode_gate from public,anon,authenticated;
create function private.customer_geocode_claim(p_key text) returns jsonb language plpgsql security definer set search_path='' as $$
declare cached jsonb;
begin
 if length(p_key)>250 then raise exception 'Invalid address query'; end if;
 select result into cached from private.customer_geocode_cache where cache_key=p_key and expires_at>now();
 if found then return jsonb_build_object('cached',cached); end if;
 update private.customer_geocode_gate set next_at=clock_timestamp()+interval '2 seconds' where singleton and next_at<=clock_timestamp();
 return jsonb_build_object('allowed',found);
end $$;
create function private.customer_geocode_store(p_key text,p_result jsonb) returns void language plpgsql security definer set search_path='' as $$
begin
 delete from private.customer_geocode_cache where expires_at<now();
 insert into private.customer_geocode_cache values(p_key,p_result,now()+interval '1 day')
 on conflict(cache_key) do update set result=excluded.result,expires_at=excluded.expires_at;
end $$;
create function public.customer_geocode_claim(p_key text) returns jsonb language sql security invoker set search_path='' as $$select private.customer_geocode_claim(p_key)$$;
create function public.customer_geocode_store(p_key text,p_result jsonb) returns void language sql security invoker set search_path='' as $$select private.customer_geocode_store(p_key,p_result)$$;
revoke all on function private.customer_geocode_claim(text),public.customer_geocode_claim(text),private.customer_geocode_store(text,jsonb),public.customer_geocode_store(text,jsonb) from public,anon,authenticated;
grant execute on function private.customer_geocode_claim(text),public.customer_geocode_claim(text),private.customer_geocode_store(text,jsonb),public.customer_geocode_store(text,jsonb) to service_role;

-- Expired/deleted identities cannot continue writes through legacy permissive storage policies.
drop policy if exists storage_active_account_required on storage.objects;
create policy storage_active_account_required on storage.objects as restrictive for all to authenticated
 using ((select private.current_user_id()) is not null) with check ((select private.current_user_id()) is not null);
