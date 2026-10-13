-- Gemini has no database credentials. Customer RPCs retain the caller's identity.
create table private.ai_conversations (
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customer_profiles(customer_id),
 auth_id uuid not null, request_id uuid not null, title text not null default 'New conversation',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), deleted_at timestamptz,
 unique(customer_id,request_id)
);
create index ai_conversation_customer_idx on private.ai_conversations(customer_id,updated_at desc);
create table private.ai_turns (
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references private.ai_conversations(id),
 request_id uuid not null, lease uuid not null default gen_random_uuid(), status text not null check(status in ('working','failed','done')),
 message text not null, image_path text, mode text not null check(mode in ('chat','assist')),
 tries integer not null default 1, started_at timestamptz not null default now(), created_at timestamptz not null default now(),
 unique(conversation_id,request_id)
);
create index ai_turn_conversation_idx on private.ai_turns(conversation_id,created_at);
create index ai_turn_created_idx on private.ai_turns(created_at);
create table private.ai_messages (
 id bigint generated always as identity primary key, conversation_id uuid not null references private.ai_conversations(id),
 turn_id uuid not null references private.ai_turns(id), role text not null check(role in ('user','assistant')),
 content text not null, image_path text, actions jsonb not null default '[]', created_at timestamptz not null default now(),
 unique(turn_id,role)
);
create index ai_message_conversation_idx on private.ai_messages(conversation_id,id desc);
create table private.ai_actions (
 id uuid primary key default gen_random_uuid(), conversation_id uuid not null references private.ai_conversations(id),
 kind text not null check(kind in ('booking','cancel_booking','default_address')), title text not null, summary text not null,
 payload jsonb not null, status text not null default 'pending' check(status in ('pending','done')),
 result jsonb, expires_at timestamptz not null default now()+interval '15 minutes', created_at timestamptz not null default now()
);
create index ai_action_conversation_idx on private.ai_actions(conversation_id);
alter table private.ai_conversations enable row level security;
alter table private.ai_turns enable row level security;
alter table private.ai_messages enable row level security;
alter table private.ai_actions enable row level security;
revoke all on private.ai_conversations,private.ai_turns,private.ai_messages,private.ai_actions from public,anon,authenticated;

create function private.ai_owned(p_id uuid) returns private.ai_conversations
language plpgsql stable security definer set search_path='' as $$
declare c private.ai_conversations;
begin
 select * into c from private.ai_conversations where id=p_id and customer_id=private.customer_id() and deleted_at is null;
 if not found then raise exception 'Conversation not found' using errcode='42501'; end if;
 return c;
end $$;
revoke all on function private.ai_owned(uuid) from public,anon,authenticated;

create function private.customer_ai_create_conversation(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); c private.ai_conversations;
begin
 if p_request_id is null then raise exception 'Request ID is required'; end if;
 perform 1 from public.customer_profiles where customer_id=cid for update;
 select * into c from private.ai_conversations where customer_id=cid and request_id=p_request_id and deleted_at is null;
 if found then return to_jsonb(c)-'auth_id'-'customer_id'-'request_id'; end if;
 if (select count(*) from private.ai_conversations where customer_id=cid and deleted_at is null)>=100 then raise exception 'Delete an older chat before creating another'; end if;
 insert into private.ai_conversations(customer_id,auth_id,request_id) values(cid,auth.uid(),p_request_id) returning * into c;
 return to_jsonb(c)-'auth_id'-'customer_id'-'request_id';
end $$;
create function private.customer_ai_conversations(p_limit integer default 30,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 100 then raise exception 'Invalid page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(c)) from(select id,title,updated_at from private.ai_conversations where customer_id=cid and deleted_at is null order by updated_at desc,id limit p_limit offset p_offset)c),'[]');
end $$;
create function private.customer_ai_messages(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.ai_owned(p_conversation_id);
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.id) from(select id,role,content,image_path,actions,created_at from private.ai_messages where conversation_id=p_conversation_id and (p_before is null or id<p_before) order by id desc limit p_limit)m),'[]');
end $$;
create function private.customer_ai_delete_conversation(p_conversation_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c private.ai_conversations; paths jsonb;
begin
 select * into c from private.ai_conversations where id=p_conversation_id and customer_id=private.customer_id() for update;
 if not found then raise exception 'Conversation not found' using errcode='42501'; end if;
 select coalesce(jsonb_agg(name),'[]') into paths from storage.objects where bucket_id='customer-ai-images' and name like c.auth_id::text||'/'||c.id::text||'/%';
 update private.ai_conversations set deleted_at=now(),title='Deleted conversation' where id=c.id;
 delete from private.ai_actions where conversation_id=c.id;
 delete from private.ai_messages where conversation_id=c.id;
 -- Keep non-content rate accounting after deletion; late workers cannot restore a chat.
 update private.ai_turns set message='',image_path=null,status='failed',lease=gen_random_uuid() where conversation_id=c.id;
 return paths;
end $$;

create function private.customer_ai_begin_turn(p_conversation_id uuid,p_request_id uuid,p_message text,p_image_path text default null,p_mode text default 'chat') returns jsonb
language plpgsql security definer set search_path='' as $$
declare c private.ai_conversations; t private.ai_turns; total integer;
begin
 c:=private.ai_owned(p_conversation_id);
 perform 1 from public.customer_profiles where customer_id=c.customer_id for update;
 perform 1 from private.ai_conversations where id=c.id and deleted_at is null for update;
 if not found then raise exception 'Conversation deleted'; end if;
 if p_request_id is null or p_message is null or length(p_message)>4000 or (length(trim(p_message))=0 and p_image_path is null) or p_mode is null or p_mode not in ('chat','assist') then raise exception 'Enter a message up to 4000 characters'; end if;
 if p_image_path is not null and (p_image_path!~('^'||c.auth_id::text||'/'||c.id::text||'/[0-9a-f-]{36}\.(jpg|png)$') or not exists(select 1 from storage.objects where bucket_id='customer-ai-images' and name=p_image_path)) then raise exception 'Photo not found' using errcode='42501'; end if;
 select * into t from private.ai_turns where conversation_id=c.id and request_id=p_request_id for update;
 if found then
  if t.message<>p_message or t.image_path is distinct from p_image_path or t.mode<>p_mode then raise exception 'Retry must use the original message'; end if;
  if t.status='done' then return jsonb_build_object('replay',true,'message',(select to_jsonb(m) from private.ai_messages m where turn_id=t.id and role='assistant')); end if;
  if t.status='working' and t.started_at>now()-interval '2 minutes' then raise exception 'AI request already in progress' using errcode='55P03'; end if;
  if t.tries>=3 then raise exception 'This message could not be processed. Send a new message.'; end if;
 end if;
 if exists(select 1 from private.ai_turns where conversation_id=c.id and status='working' and started_at>now()-interval '2 minutes' and id is distinct from t.id) then raise exception 'Wait for the current reply' using errcode='55P03'; end if;
 select coalesce(sum(tries),0) into total from private.ai_turns x join private.ai_conversations y on y.id=x.conversation_id where y.customer_id=c.customer_id and x.created_at>now()-interval '24 hours';
 if total>=60 or (select count(*) from private.ai_turns x join private.ai_conversations y on y.id=x.conversation_id where y.customer_id=c.customer_id and x.started_at>now()-interval '1 minute')>=6 then raise exception 'AI message limit reached. Please try later.' using errcode='P0001'; end if;
 if (select coalesce(sum(tries),0) from private.ai_turns where created_at>now()-interval '24 hours')>=2000 then raise exception 'AI capacity reached. Please try later.'; end if;
 if t.id is null then
  if (select count(*) from private.ai_messages where conversation_id=c.id)>=400 then raise exception 'Start a new chat to continue'; end if;
  insert into private.ai_turns(conversation_id,request_id,status,message,image_path,mode) values(c.id,p_request_id,'working',p_message,p_image_path,p_mode) returning * into t;
  insert into private.ai_messages(conversation_id,turn_id,role,content,image_path) values(c.id,t.id,'user',p_message,p_image_path);
 else
  update private.ai_turns set status='working',lease=gen_random_uuid(),tries=tries+1,started_at=now() where id=t.id returning * into t;
 end if;
 update private.ai_conversations set updated_at=now(),title=case when title='New conversation' then left(coalesce(nullif(trim(p_message),''),'Photo conversation'),70) else title end where id=c.id;
 return jsonb_build_object('turn_id',t.id,'lease',t.lease,'history',private.customer_ai_messages(c.id,null,20));
end $$;

create function private.ai_finish_turn(p_turn_id uuid,p_lease uuid,p_auth_id uuid,p_content text,p_actions jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t private.ai_turns; m private.ai_messages;
begin
 perform 1 from private.ai_conversations c join private.ai_turns x on x.conversation_id=c.id where x.id=p_turn_id and c.auth_id=p_auth_id and c.deleted_at is null for update of c;
 if not found then raise exception 'Conversation no longer active' using errcode='42501'; end if;
 select x.* into t from private.ai_turns x join private.ai_conversations c on c.id=x.conversation_id
 join public.customer_profiles cp on cp.customer_id=c.customer_id join public.users u on u.user_id=cp.user_id
 where x.id=p_turn_id and c.auth_id=p_auth_id and c.deleted_at is null and u.is_active and x.lease=p_lease for update of x;
 if not found then raise exception 'Request no longer active' using errcode='42501'; end if;
 if t.status='done' then select * into m from private.ai_messages where turn_id=t.id and role='assistant'; return to_jsonb(m); end if;
 if t.status<>'working' or p_content is null or length(p_content)>16000 or jsonb_typeof(p_actions)<>'array' or jsonb_array_length(p_actions)>8 or octet_length(p_actions::text)>40000 then raise exception 'Invalid AI reply'; end if;
 insert into private.ai_messages(conversation_id,turn_id,role,content,actions) values(t.conversation_id,t.id,'assistant',p_content,p_actions) returning * into m;
 update private.ai_turns set status='done' where id=t.id;
 update private.ai_conversations set updated_at=now() where id=t.conversation_id;
 return to_jsonb(m);
end $$;
create function private.ai_fail_turn(p_turn_id uuid,p_lease uuid,p_auth_id uuid) returns void
language sql security definer set search_path='' as $$
 update private.ai_turns t set status='failed' from private.ai_conversations c where t.id=p_turn_id and t.lease=p_lease and t.status='working' and c.id=t.conversation_id and c.auth_id=p_auth_id;
$$;

create function private.customer_ai_stage_action(p_conversation_id uuid,p_kind text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare c private.ai_conversations; a private.ai_actions; address public.saved_addresses; svc public.services;
 b jsonb; quote numeric; provider text; payload jsonb; summary text; title text;
begin
 c:=private.ai_owned(p_conversation_id);
 perform 1 from private.ai_conversations where id=c.id and deleted_at is null for update;
 if not found then raise exception 'Conversation deleted' using errcode='42501'; end if;
 if p_kind is null or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>5000 then raise exception 'Invalid action'; end if;
 if (select count(*) from private.ai_actions where conversation_id=c.id and created_at>now()-interval '1 hour')>=30 then raise exception 'Too many action drafts'; end if;
 if p_kind='booking' then
  if p_payload - array['service_id','address_id','date','time','instructions'] <> '{}'::jsonb then raise exception 'Unexpected booking fields'; end if;
  select * into address from public.saved_addresses where address_id=(p_payload->>'address_id')::uuid and customer_id=c.customer_id;
  if not found then raise exception 'Choose your saved address' using errcode='42501'; end if;
  if not exists(select 1 from jsonb_array_elements(private.customer_booking_slots((p_payload->>'service_id')::uuid,(p_payload->>'date')::date)) s where (s->>'scheduled_time')::time=(p_payload->>'time')::time) then raise exception 'Choose an available time'; end if;
  select * into svc from public.services where service_id=(p_payload->>'service_id')::uuid;
  select business_name into provider from public.provider_profiles where provider_id=svc.provider_id;
  quote:=round(case when svc.pricing_type='Hourly' then svc.base_price*svc.estimated_duration/60 else svc.base_price end,2);
  if quote<=0 or length(coalesce(p_payload->>'instructions',''))>1000 then raise exception 'Invalid booking'; end if;
  payload:=p_payload||jsonb_build_object('quote',quote,'address_snapshot',to_jsonb(address)-'created_at','duration_minutes',svc.estimated_duration);
  title:='Request booking'; summary:=svc.service_name||' · '||provider||E'\nRM '||quote::text||E'\n'||(p_payload->>'date')||' '||(p_payload->>'time')||E' (Malaysia time)\n'||concat_ws(', ',address.address_line,address.city,address.state,address.postcode)||case when nullif(p_payload->>'instructions','') is null then '' else E'\nInstructions: '||(p_payload->>'instructions') end||E'\nProvider acceptance is required. Payment is handled by you.';
 elsif p_kind='cancel_booking' then
  if p_payload-array['booking_id','reason']<>'{}'::jsonb or length(coalesce(p_payload->>'reason','')) not between 3 and 500 then raise exception 'Add a cancellation reason'; end if;
  b:=private.customer_booking_detail((p_payload->>'booking_id')::uuid);
  payload:=p_payload; title:='Cancel booking'; summary:='Cancel '||coalesce(b->>'service_name_snapshot','this booking')||E'?\nReason: '||(p_payload->>'reason')||E'\nPaid bookings follow the existing support/refund process; cancellation is not a refund confirmation.';
 elsif p_kind='default_address' then
  if p_payload-array['address_id']<>'{}'::jsonb then raise exception 'Unexpected address fields'; end if;
  select * into address from public.saved_addresses where address_id=(p_payload->>'address_id')::uuid and customer_id=c.customer_id;
  if not found then raise exception 'Address not found' using errcode='42501'; end if;
  payload:=p_payload||jsonb_build_object('address_snapshot',to_jsonb(address)-'created_at'); title:='Change default address'; summary:=concat_ws(', ',address.address_line,address.city,address.state,address.postcode);
 else raise exception 'Unsupported assistant action'; end if;
 select * into a from private.ai_actions where conversation_id=c.id and kind=p_kind and ai_actions.payload=payload and status='pending' and expires_at>now() order by created_at desc limit 1;
 if not found then insert into private.ai_actions(conversation_id,kind,title,summary,payload) values(c.id,p_kind,title,summary,payload) returning * into a; end if;
 return to_jsonb(a)-'conversation_id';
end $$;
create function private.customer_ai_confirm_action(p_action_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare cid uuid:=private.customer_id(); a private.ai_actions; result jsonb; price numeric; duration integer; address public.saved_addresses;
begin
 -- Same customer lock order as authoritative booking creation.
 perform 1 from public.customer_profiles where customer_id=cid for update;
 perform 1 from private.ai_conversations c join private.ai_actions x on x.conversation_id=c.id where x.id=p_action_id and c.customer_id=cid and c.deleted_at is null for update of c;
 select x.* into a from private.ai_actions x join private.ai_conversations c on c.id=x.conversation_id where x.id=p_action_id and c.customer_id=cid and c.deleted_at is null for update of x;
 if not found then raise exception 'Action not found' using errcode='42501'; end if;
 if a.status='done' then return a.result; end if;
 if a.expires_at<=now() then raise exception 'This action expired. Ask the assistant to prepare it again.'; end if;
 if a.kind in ('booking','default_address') then
  select * into address from public.saved_addresses where address_id=(a.payload->>'address_id')::uuid and customer_id=cid for share;
  if not found or (to_jsonb(address)-'created_at') is distinct from a.payload->'address_snapshot' then raise exception 'The address changed. Ask for a fresh summary.'; end if;
 end if;
 if a.kind='booking' then
  select round(case when pricing_type='Hourly' then base_price*estimated_duration/60 else base_price end,2),estimated_duration into price,duration from public.services where service_id=(a.payload->>'service_id')::uuid for share;
  if price is distinct from (a.payload->>'quote')::numeric or duration is distinct from (a.payload->>'duration_minutes')::integer then raise exception 'The service changed. Ask for a fresh booking summary.'; end if;
  result:=private.customer_create_booking((a.payload->>'service_id')::uuid,(a.payload->>'address_id')::uuid,(a.payload->>'date')::date,(a.payload->>'time')::time,a.payload->>'instructions','Medium',a.id);
 elsif a.kind='cancel_booking' then result:=private.customer_cancel_booking((a.payload->>'booking_id')::uuid,a.payload->>'reason');
 else perform public.customer_set_default_address((a.payload->>'address_id')::uuid); result:=jsonb_build_object('status','done','address_id',a.payload->>'address_id'); end if;
 update private.ai_actions set status='done',result=result where id=a.id;
 return result;
end $$;

-- Explicitly grant only approved customer endpoints; writer endpoints remain service-only.
do $$ declare r record; args text; begin
 for r in select p.oid,p.proname,pg_get_function_identity_arguments(p.oid) identity_args,pg_get_function_arguments(p.oid) full_args,pg_get_function_result(p.oid) result_type,proargnames from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('customer_ai_create_conversation','customer_ai_conversations','customer_ai_messages','customer_ai_delete_conversation','customer_ai_begin_turn','customer_ai_stage_action','customer_ai_confirm_action','ai_finish_turn','ai_fail_turn') loop
  select string_agg(quote_ident(x),',') into args from unnest(r.proargnames) x;
  execute format('create function public.%I(%s) returns %s language sql security invoker set search_path='''' as $f$ select private.%I(%s) $f$',r.proname,r.full_args,r.result_type,r.proname,args);
  execute format('revoke all on function private.%I(%s),public.%I(%s) from public,anon,authenticated',r.proname,r.identity_args,r.proname,r.identity_args);
  execute format('grant execute on function private.%I(%s),public.%I(%s) to %I',r.proname,r.identity_args,r.proname,r.identity_args,case when r.proname like 'customer_%' then 'authenticated' else 'service_role' end);
 end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('customer-ai-images','customer-ai-images',false,4194304,array['image/jpeg','image/png']);
create function private.ai_photo_owned(p_name text,p_deleted boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 if p_name !~ ('^'||auth.uid()::text||'/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png)$') then return false; end if;
 return exists(select 1 from private.ai_conversations where id::text=split_part(p_name,'/',2) and customer_id=cid and (p_deleted or deleted_at is null));
exception when insufficient_privilege then return false;
end $$;
revoke all on function private.ai_photo_owned(text,boolean) from public,anon;
grant execute on function private.ai_photo_owned(text,boolean) to authenticated;
create function private.ai_photo_upload_allowed(p_name text) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.ai_photo_owned(p_name) then return false; end if;
 return (select count(*)<200 from storage.objects where bucket_id='customer-ai-images' and name like auth.uid()::text||'/%');
end $$;
revoke all on function private.ai_photo_upload_allowed(text) from public,anon;
grant execute on function private.ai_photo_upload_allowed(text) to authenticated;
create policy ai_photo_insert on storage.objects for insert to authenticated with check(bucket_id='customer-ai-images' and private.ai_photo_upload_allowed(name));
create policy ai_photo_read on storage.objects for select to authenticated using(bucket_id='customer-ai-images' and private.ai_photo_owned(name));
create policy ai_photo_delete on storage.objects for delete to authenticated using(bucket_id='customer-ai-images' and private.ai_photo_owned(name,true));
notify pgrst,'reload schema';

-- Account deletion already serializes on the customer row. Erase AI content in
-- that same transaction; the existing Storage cleanup removes owned photos.
create function private.ai_account_deleted() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from private.ai_conversations where auth_id=new.auth_user_id order by id for update;
 delete from private.ai_actions where conversation_id in (select id from private.ai_conversations where auth_id=new.auth_user_id);
 delete from private.ai_messages where conversation_id in (select id from private.ai_conversations where auth_id=new.auth_user_id);
 update private.ai_turns set message='',image_path=null,status='failed',lease=gen_random_uuid()
 where conversation_id in (select id from private.ai_conversations where auth_id=new.auth_user_id);
 update private.ai_conversations set deleted_at=now(),title='Deleted conversation' where auth_id=new.auth_user_id;
 return new;
end $$;
revoke all on function private.ai_account_deleted() from public,anon,authenticated;
create trigger erase_customer_ai after insert on private.customer_deletions for each row execute function private.ai_account_deleted();
