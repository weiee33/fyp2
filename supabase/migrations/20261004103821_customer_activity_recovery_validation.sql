-- Activity is recorded in the same transaction as the change, never by the client.
create function private.customer_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid; cid uuid; heading text; details text;
begin
 if tg_table_name='saved_addresses' then
  cid:=case when tg_op='DELETE' then old.customer_id else new.customer_id end;
  select user_id into uid from public.customer_profiles where customer_id=cid;
  if tg_op='INSERT' then heading:='Address added'; details:='A new service address was saved.';
  elsif tg_op='DELETE' then heading:='Address deleted'; details:='A saved service address was removed.';
  elsif new.is_default and not old.is_default then heading:='Default address changed'; details:='Your default service address was updated.';
  elsif (new.label,new.address_line,new.city,new.state,new.postcode,new.coordinates) is distinct from (old.label,old.address_line,old.city,old.state,old.postcode,old.coordinates) then heading:='Address updated'; details:='Your saved service address details were updated.';
  else return null; end if;
 elsif tg_table_schema='auth' then
  if new.encrypted_password is not distinct from old.encrypted_password then return null; end if;
  select user_id into uid from public.users where auth_user_id=new.id and role='customer' and is_active;
  heading:='Password changed'; details:='Your account password was changed. If this was not you, reset your password immediately.';
 elsif tg_table_name='users' then
  uid:=new.user_id;
  if (new.full_name,new.phone,new.profile_photo_url,new.email) is not distinct from (old.full_name,old.phone,old.profile_photo_url,old.email) then return null; end if;
  heading:='Personal information updated'; details:='Your name, contact information or profile photo was updated.';
 else
  uid:=new.user_id;
  if (new.bio,new.gender,new.birthday,new.service_preferences) is not distinct from (old.bio,old.gender,old.birthday,old.service_preferences) then return null; end if;
  heading:='Profile preferences updated'; details:='Your profile details or service preferences were updated.';
 end if;
 -- Deleted/inactive accounts and other roles never receive customer activity.
 if exists(select 1 from public.users where user_id=uid and role='customer' and is_active and auth_user_id is not null) then
  insert into public.notifications(user_id,notification_type,title,message) values(uid,'System',heading,details);
 end if;
 return null;
end $$;
revoke all on function private.customer_activity() from public,anon,authenticated;
create trigger customer_address_activity after insert or update or delete on public.saved_addresses for each row execute function private.customer_activity();
create trigger customer_identity_activity after update on public.users for each row execute function private.customer_activity();
create trigger customer_profile_activity after update on public.customer_profiles for each row execute function private.customer_activity();
create trigger customer_password_activity after update of encrypted_password on auth.users for each row execute function private.customer_activity();

create function private.customer_unread_counts() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid; notices bigint; bookings bigint; chats bigint;
begin
 select user_id into uid from public.customer_profiles where customer_id=cid;
 select count(*),count(*) filter(where booking_id is not null) into notices,bookings from public.notifications
 where user_id=uid and not is_read and dismissed_at is null;
 select count(*) into chats from public.chat_members m join public.chat_messages x using(conversation_id)
 where m.user_id=uid and not m.hidden and not m.blocked and x.sender_id<>uid and x.message_id>greatest(m.read_through,m.cleared_through);
 return jsonb_build_object('notifications',notices,'bookings',bookings,'chats',chats);
end $$;
create function public.customer_unread_counts() returns jsonb language sql stable security invoker set search_path='' as $$ select private.customer_unread_counts() $$;
revoke all on function public.customer_unread_counts(),private.customer_unread_counts() from public,anon;
grant execute on function public.customer_unread_counts(),private.customer_unread_counts() to authenticated;
create index notifications_unread_customer_idx on public.notifications(user_id,booking_id) where not is_read and dismissed_at is null;

-- The anonymous recovery endpoint uses a server-only, bounded lookup, never a public users table query.
create table private.customer_recovery_limits(bucket text primary key, window_start timestamptz not null, attempts integer not null);
alter table private.customer_recovery_limits enable row level security;
revoke all on private.customer_recovery_limits from public,anon,authenticated;
create function private.customer_recovery_check(p_email text,p_ip_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text; n integer; allowed boolean:=true; eligible boolean;
begin
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or p_ip_hash !~ '^[a-f0-9]{64}$' or p_ip_hash is null then raise exception 'Invalid recovery request'; end if;
 -- Fixed one-hour windows; email and IP buckets are locked in consistent order.
 foreach k in array array['email:'||md5(lower(trim(p_email))),'ip:'||p_ip_hash] loop
  insert into private.customer_recovery_limits as r values(k,now(),1)
  on conflict(bucket) do update set window_start=case when r.window_start<now()-interval '1 hour' then now() else r.window_start end,
   attempts=case when r.window_start<now()-interval '1 hour' then 1 else least(r.attempts+1,1000) end returning attempts into n;
  if n>(case when k like 'email:%' then 5 else 30 end) then allowed:=false; end if;
 end loop;
 delete from private.customer_recovery_limits where bucket in(select bucket from private.customer_recovery_limits where window_start<now()-interval '1 day' limit 100);
 if not allowed then return jsonb_build_object('allowed',false); end if;
 select exists(select 1 from auth.users a join public.users u on u.auth_user_id=a.id join public.customer_profiles c using(user_id)
 where lower(a.email)=lower(trim(p_email)) and u.role='customer' and u.is_active and a.email_confirmed_at is not null) into eligible;
 return jsonb_build_object('allowed',true,'registered',eligible);
end $$;
create function public.customer_recovery_check(p_email text,p_ip_hash text) returns jsonb language sql security invoker set search_path='' as $$select private.customer_recovery_check(p_email,p_ip_hash)$$;
revoke all on function public.customer_recovery_check(text,text),private.customer_recovery_check(text,text) from public,anon,authenticated;
grant execute on function public.customer_recovery_check(text,text),private.customer_recovery_check(text,text) to service_role;
notify pgrst,'reload schema';
