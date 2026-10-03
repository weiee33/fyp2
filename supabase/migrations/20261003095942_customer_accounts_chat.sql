-- Preserve provider service creation while restoring canonical identity and suspension guards.
drop policy if exists active_account_required on public.services;
create policy active_account_required on public.services as restrictive for all to authenticated
 using ((select private.current_user_id()) is not null) with check ((select private.current_user_id()) is not null);
drop policy if exists services_provider_insert on public.services;
create policy services_provider_insert on public.services for insert to authenticated with check
 (provider_id in (select provider_id from public.provider_profiles where user_id=(select private.current_user_id())));
drop policy if exists services_provider_delete on public.services;
create policy services_provider_delete on public.services for delete to authenticated using
 (provider_id in (select provider_id from public.provider_profiles where user_id=(select private.current_user_id())));

-- Restore the documented column grants after live broad table grants drifted.
-- Auth provisioning and role/verification changes remain trusted server actions.
revoke all on public.users,public.provider_profiles from public,anon,authenticated;
do $$ declare t text; columns text; begin
 foreach t in array array['users','provider_profiles'] loop
  select string_agg(quote_ident(a.attname),',') into columns from pg_attribute a
  where a.attrelid=('public.'||t)::regclass and a.attnum>0 and not a.attisdropped;
  execute format('revoke select(%s),insert(%s),update(%s),references(%s) on public.%I from public,anon,authenticated',columns,columns,columns,columns,t);
 end loop;
end $$;
grant select(user_id,auth_user_id,email,phone,full_name,role,profile_photo_url,is_active,email_verified,phone_verified,last_login_at,created_at,updated_at) on public.users to authenticated;
grant update(full_name,phone,profile_photo_url) on public.users to authenticated;
grant select(provider_id,user_id,business_name,bio,years_experience,verification_status,overall_rating,total_reviews,service_radius_km,region,city,created_at,updated_at) on public.provider_profiles to anon,authenticated;
grant update(business_name,business_license,bio,years_experience,service_radius_km,region,city) on public.provider_profiles to authenticated;


-- Optional profile details stay private to the customer and trusted administration.
alter table public.customer_profiles add column bio text check(length(bio)<=300),
 add column gender text check(gender in ('Female','Male','Prefer not to say')),
 add column birthday date;

create function private.customer_account_update(p_full_name text,p_phone text,p_preferences text[],p_photo_url text,p_bio text,p_gender text,p_birthday date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); result jsonb;
begin
 if length(coalesce(p_bio,''))>300 or (p_gender is not null and p_gender not in ('Female','Male','Prefer not to say'))
 or p_birthday>current_date or p_birthday<date '1900-01-01' then raise exception 'Please check your profile details'; end if;
 if p_phone is null or p_phone !~ '^\+601[0-9]{8,9}$' then raise exception 'Enter a Malaysian mobile number with +60 and 9 to 10 following digits'; end if;
 result:=private.customer_profile_update(p_full_name,p_phone,p_preferences,p_photo_url);
 update public.customer_profiles set bio=nullif(trim(p_bio),''),gender=p_gender,birthday=p_birthday where customer_id=cid;
 return result;
end $$;
create function public.customer_account_update(p_full_name text,p_phone text,p_preferences text[],p_photo_url text default null,p_bio text default null,p_gender text default null,p_birthday date default null)
returns jsonb language sql security invoker set search_path='' as $$ select private.customer_account_update(p_full_name,p_phone,p_preferences,p_photo_url,p_bio,p_gender,p_birthday) $$;

create table public.chat_conversations(
 conversation_id uuid primary key default gen_random_uuid(),
 customer_user_id uuid not null references public.users(user_id),
 provider_user_id uuid not null references public.users(user_id),
 created_at timestamptz not null default now(),last_message_at timestamptz not null default now(),
 unique(customer_user_id,provider_user_id),check(customer_user_id<>provider_user_id)
);
create index chat_provider_idx on public.chat_conversations(provider_user_id,last_message_at desc);
create table public.chat_members(
 conversation_id uuid not null references public.chat_conversations(conversation_id),
 user_id uuid not null references public.users(user_id),
 pinned boolean not null default false,hidden boolean not null default false,blocked boolean not null default false,
 read_through bigint not null default 0,cleared_through bigint not null default 0,
 primary key(conversation_id,user_id)
);
create index chat_member_inbox_idx on public.chat_members(user_id,pinned desc,conversation_id);
create table public.chat_messages(
 message_id bigint generated always as identity primary key,
 conversation_id uuid not null references public.chat_conversations(conversation_id),
 sender_id uuid not null references public.users(user_id),
 request_id uuid not null,body text not null check(length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now(),unique(sender_id,request_id)
);
create index chat_message_page_idx on public.chat_messages(conversation_id,message_id desc);
create index chat_sender_rate_idx on public.chat_messages(sender_id,created_at desc);
alter table public.chat_conversations enable row level security;
alter table public.chat_members enable row level security;
alter table public.chat_messages enable row level security;
revoke all on public.chat_conversations,public.chat_members,public.chat_messages from public,anon,authenticated;
grant select on public.chat_conversations,public.chat_members,public.chat_messages to authenticated;

create function private.chat_actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare uid uuid;
begin
 select u.user_id into uid from public.users u join auth.users a on a.id=u.auth_user_id
 where a.id=auth.uid() and u.is_active and u.role in ('customer','provider') and a.email_confirmed_at is not null;
 if uid is null then raise exception 'An active verified customer or provider account is required' using errcode='42501'; end if;
 return uid;
end $$;
create function private.chat_member(p_conversation_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_members where conversation_id=p_conversation_id and user_id=private.current_user_id()) $$;
create function private.chat_visible_message(p_conversation_id uuid,p_message_id bigint) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_members where conversation_id=p_conversation_id and user_id=private.current_user_id() and p_message_id>cleared_through) $$;
create policy chat_conversation_member_read on public.chat_conversations for select to authenticated using(private.chat_member(conversation_id));
create policy chat_member_self_read on public.chat_members for select to authenticated using(user_id=(select private.current_user_id()));
create policy chat_message_member_read on public.chat_messages for select to authenticated using(private.chat_visible_message(conversation_id,message_id));

create function private.chat_provider_search(p_keyword text default '',p_limit integer default 20) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.customer_id();
 if length(coalesce(p_keyword,''))>100 or p_limit is null or p_limit not between 1 and 30 then raise exception 'Invalid provider search'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (select p.provider_id,p.business_name,u.profile_photo_url,p.city
 from public.provider_profiles p join public.users u using(user_id) where u.is_active and p.verification_status='Verified'
 and position(lower(trim(coalesce(p_keyword,''))) in lower(p.business_name))>0 order by p.business_name,p.provider_id limit p_limit) x),'[]');
end $$;
create function public.chat_provider_search(p_keyword text default '',p_limit integer default 20) returns jsonb language sql stable security invoker set search_path='' as $$ select private.chat_provider_search(p_keyword,p_limit) $$;

create function private.chat_open(p_provider_id uuid default null,p_booking_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); customer_uid uuid; provider_uid uuid; cid uuid;
begin
 if (p_provider_id is null)=(p_booking_id is null) then raise exception 'Choose a provider or a booking'; end if;
 if p_booking_id is not null then
  select c.user_id,p.user_id into customer_uid,provider_uid from public.bookings b
  join public.customer_profiles c using(customer_id) join public.provider_profiles p using(provider_id)
  where b.booking_id=p_booking_id and uid in (c.user_id,p.user_id);
 else
  perform private.customer_id(); customer_uid:=uid;
  select p.user_id into provider_uid from public.provider_profiles p join public.users u using(user_id)
  where p.provider_id=p_provider_id and p.verification_status='Verified' and u.is_active;
 end if;
 if customer_uid is null or provider_uid is null then raise exception 'This conversation is not available' using errcode='42501'; end if;
 insert into public.chat_conversations(customer_user_id,provider_user_id) values(customer_uid,provider_uid)
 on conflict(customer_user_id,provider_user_id) do update set customer_user_id=excluded.customer_user_id returning conversation_id into cid;
 insert into public.chat_members(conversation_id,user_id) values(cid,customer_uid),(cid,provider_uid) on conflict do nothing;
 update public.chat_members set hidden=false where conversation_id=cid and user_id=uid;
 return cid;
end $$;
create function public.chat_open(p_provider_id uuid default null,p_booking_id uuid default null) returns uuid language sql security invoker set search_path='' as $$ select private.chat_open(p_provider_id,p_booking_id) $$;

create function private.chat_inbox(p_keyword text default '',p_limit integer default 30,p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor();
begin
 if length(coalesce(p_keyword,''))>100 or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000 then raise exception 'Invalid inbox page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select c.conversation_id,c.last_message_at,m.pinned,m.blocked,coalesce(p.business_name,u.full_name) as peer_name,u.profile_photo_url,
 (select body from public.chat_messages where conversation_id=c.conversation_id and message_id>m.cleared_through order by message_id desc limit 1) as preview,
 (select count(*) from public.chat_messages where conversation_id=c.conversation_id and sender_id<>uid and message_id>greatest(m.read_through,m.cleared_through)) as unread_count
 from public.chat_members m join public.chat_conversations c using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id
 where m.user_id=uid and not m.hidden and position(lower(trim(coalesce(p_keyword,''))) in lower(coalesce(p.business_name,u.full_name)))>0
 order by m.pinned desc,c.last_message_at desc,c.conversation_id limit p_limit offset p_offset) x),'[]');
end $$;
create function public.chat_inbox(p_keyword text default '',p_limit integer default 30,p_offset integer default 0) returns jsonb language sql stable security invoker set search_path='' as $$ select private.chat_inbox(p_keyword,p_limit,p_offset) $$;

create function private.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); result jsonb;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid message page'; end if;
 select jsonb_build_object('conversation_id',c.conversation_id,'peer_name',coalesce(p.business_name,u.full_name),'peer_active',u.is_active,
 'blocked',m.blocked,'can_send',u.is_active and not exists(select 1 from public.chat_members where conversation_id=c.conversation_id and blocked),
 'messages',coalesce((select jsonb_agg(to_jsonb(item) order by item.message_id desc) from(
 select msg.message_id,msg.request_id,msg.body,msg.created_at,msg.sender_id=uid as is_mine from public.chat_messages msg
 where msg.conversation_id=c.conversation_id and msg.message_id>m.cleared_through and (p_before is null or msg.message_id<p_before)
 order by msg.message_id desc limit p_limit) item),'[]')) into result
 from public.chat_conversations c join public.chat_members m using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id where c.conversation_id=p_conversation_id and m.user_id=uid;
 return result;
end $$;
create function public.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language sql stable security invoker set search_path='' as $$ select private.chat_history(p_conversation_id,p_before,p_limit) $$;

create function private.chat_send(p_conversation_id uuid,p_body text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); recipient uuid; existing public.chat_messages%rowtype; msg public.chat_messages%rowtype;
begin
 if p_body is null or length(trim(p_body)) not between 1 and 2000 or p_request_id is null then raise exception 'Enter a message of 1 to 2000 characters'; end if;
 -- Serialize per sender for rate limit and idempotency, then per conversation.
 perform pg_advisory_xact_lock(hashtextextended('chat:'||uid::text,0));
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 select * into existing from public.chat_messages where sender_id=uid and request_id=p_request_id;
 if found then
  if existing.conversation_id<>p_conversation_id or existing.body<>trim(p_body) then raise exception 'This retry belongs to another message'; end if;
  return jsonb_build_object('message_id',existing.message_id,'request_id',existing.request_id,'body',existing.body,'created_at',existing.created_at,'is_mine',true);
 end if;
 perform 1 from public.chat_conversations where conversation_id=p_conversation_id for update;
 select user_id into recipient from public.chat_members where conversation_id=p_conversation_id and user_id<>uid;
 if exists(select 1 from public.chat_members where conversation_id=p_conversation_id and blocked)
 or not exists(select 1 from public.users where user_id=recipient and is_active) then raise exception 'Messages cannot be sent to this conversation'; end if;
 if (select count(*) from public.chat_messages where sender_id=uid and created_at>now()-interval '1 minute')>=30 then raise exception 'Please wait a moment before sending more messages'; end if;
 insert into public.chat_messages(conversation_id,sender_id,request_id,body) values(p_conversation_id,uid,p_request_id,trim(p_body)) returning * into msg;
 update public.chat_conversations set last_message_at=msg.created_at where conversation_id=p_conversation_id;
 update public.chat_members set hidden=false,read_through=case when user_id=uid then msg.message_id else read_through end where conversation_id=p_conversation_id;
 -- Chat events are delivered in-app without copying private message text to email queues.
 insert into public.notifications(user_id,notification_type,title,message,deep_link)
 values(recipient,'Message','New chat message','You have a new message. Open your chat to read it.','chat/'||p_conversation_id::text);
 return jsonb_build_object('message_id',msg.message_id,'request_id',msg.request_id,'body',msg.body,'created_at',msg.created_at,'is_mine',true);
end $$;
create function public.chat_send(p_conversation_id uuid,p_body text,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.chat_send(p_conversation_id,p_body,p_request_id) $$;

create function private.chat_manage(p_conversation_id uuid,p_action text,p_read_through bigint default null) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); last_id bigint;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 perform 1 from public.chat_conversations where conversation_id=p_conversation_id for update;
 select coalesce(max(message_id),0) into last_id from public.chat_messages where conversation_id=p_conversation_id;
 case p_action
 when 'pin','unpin' then update public.chat_members set pinned=p_action='pin' where conversation_id=p_conversation_id and user_id=uid;
 when 'delete' then update public.chat_members set hidden=true,pinned=false,cleared_through=last_id,read_through=last_id where conversation_id=p_conversation_id and user_id=uid;
 when 'read' then update public.chat_members set read_through=greatest(read_through,least(coalesce(p_read_through,0),last_id)) where conversation_id=p_conversation_id and user_id=uid;
 when 'block','unblock' then update public.chat_members set blocked=p_action='block' where conversation_id=p_conversation_id and user_id=uid;
 else raise exception 'Unknown chat action'; end case;
end $$;
create function public.chat_manage(p_conversation_id uuid,p_action text,p_read_through bigint default null) returns void language sql security invoker set search_path='' as $$ select private.chat_manage(p_conversation_id,p_action,p_read_through) $$;

revoke all on function private.chat_actor() from public,anon,authenticated;
revoke all on function private.chat_member(uuid),private.chat_visible_message(uuid,bigint) from public,anon;
grant execute on function private.chat_member(uuid),private.chat_visible_message(uuid,bigint) to authenticated;
do $$ declare f record; begin
 for f in select n.nspname,p.oid::regprocedure::text as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private') and p.proname in ('customer_account_update','chat_provider_search','chat_open','chat_inbox','chat_history','chat_send','chat_manage') loop
  execute 'revoke all on function '||f.signature||' from public,anon';
  execute 'grant execute on function '||f.signature||' to authenticated';
 end loop;
end $$;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.chat_messages,public.chat_members;
 end if;
end $$;
notify pgrst,'reload schema';
