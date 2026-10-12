-- Private, immutable photo attachments. Existing text clients continue to see "Photo".
alter table public.chat_messages add column attachment_path text;
create unique index chat_attachment_path_idx on public.chat_messages(attachment_path) where attachment_path is not null;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('chat-photos','chat-photos',false,5242880,array['image/jpeg','image/png','image/webp']);

create function private.chat_photo_access(p_name text,p_upload boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare uid uuid; cid uuid; parts text[];
begin
 uid:=private.chat_actor();
 parts:=string_to_array(p_name,'/');
 if array_length(parts,1)<>3 or parts[1] !~ '^[0-9a-f-]{36}$' or parts[2] !~ '^[0-9a-f-]{36}$'
 or parts[3] !~ '^[0-9a-f-]{36}\.(jpg|png|webp)$' then return false; end if;
 begin cid:=parts[2]::uuid; exception when invalid_text_representation then return false; end;
 if not private.chat_member(cid) then return false; end if;
 if p_upload then
  return parts[1]=auth.uid()::text
   and exists(select 1 from public.chat_members m join public.users u using(user_id) where m.conversation_id=cid and m.user_id<>uid and u.is_active)
   and not exists(select 1 from public.chat_messages where attachment_path=p_name)
   and (select count(*) from storage.objects where bucket_id='chat-photos' and owner_id=auth.uid()::text and created_at>now()-interval '1 minute')<30;
 end if;
 return exists(select 1 from public.chat_messages msg join public.chat_members m using(conversation_id)
   where msg.attachment_path=p_name and m.user_id=uid and msg.message_id>m.cleared_through)
  or (parts[1]=auth.uid()::text and not exists(select 1 from public.chat_messages where attachment_path=p_name));
exception when insufficient_privilege then return false;
end $$;
revoke all on function private.chat_photo_access(text,boolean) from public,anon;
grant execute on function private.chat_photo_access(text,boolean) to authenticated;
create policy chat_photo_upload on storage.objects for insert to authenticated
 with check(bucket_id='chat-photos' and private.chat_photo_access(name,true));
create policy chat_photo_read on storage.objects for select to authenticated
 using(bucket_id='chat-photos' and private.chat_photo_access(name,false));
-- No overwrite or deletion policy: messages always retain their original attachment.

create function private.chat_send_photo(p_conversation_id uuid,p_path text,p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); existing public.chat_messages%rowtype; result jsonb; obj storage.objects%rowtype;
begin
 if p_path is null or p_request_id is null or p_path !~ ('^'||auth.uid()::text||'/'||p_conversation_id::text||'/'||p_request_id::text||'\.(jpg|png|webp)$') then
  raise exception 'Invalid photo attachment'; end if;
 perform pg_advisory_xact_lock(hashtextextended('chat:'||uid::text,0));
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 select * into existing from public.chat_messages where sender_id=uid and request_id=p_request_id;
 if found then
  if existing.conversation_id<>p_conversation_id or existing.attachment_path is distinct from p_path then raise exception 'This retry belongs to another message'; end if;
  return jsonb_build_object('message_id',existing.message_id,'body',existing.body,'request_id',existing.request_id,'created_at',existing.created_at,'is_mine',true,'attachment_path',existing.attachment_path);
 end if;
 select * into obj from storage.objects where bucket_id='chat-photos' and name=p_path;
 if not found or obj.owner_id is distinct from auth.uid()::text or coalesce((obj.metadata->>'size')::bigint,0) not between 1 and 5242880
 or coalesce(obj.metadata->>'mimetype','') not in ('image/jpeg','image/png','image/webp') then raise exception 'Upload a JPEG, PNG or WebP photo up to 5 MB first'; end if;
 -- Reuse active recipient, rate limit, notification and per-conversation locking.
 result:=private.chat_send(p_conversation_id,'Photo',p_request_id);
 update public.chat_messages set attachment_path=p_path where message_id=(result->>'message_id')::bigint;
 return result||jsonb_build_object('attachment_path',p_path);
end $$;
create function public.chat_send_photo(p_conversation_id uuid,p_path text,p_request_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select private.chat_send_photo(p_conversation_id,p_path,p_request_id) $$;
revoke all on function private.chat_send_photo(uuid,text,uuid),public.chat_send_photo(uuid,text,uuid) from public,anon;
grant execute on function private.chat_send_photo(uuid,text,uuid),public.chat_send_photo(uuid,text,uuid) to authenticated;

create or replace function private.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); result jsonb;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid message page'; end if;
 select jsonb_build_object('conversation_id',c.conversation_id,'peer_name',coalesce(p.business_name,u.full_name),'peer_active',u.is_active,
 'cleared_through',m.cleared_through,'blocked',false,'can_send',u.is_active,
 'messages',coalesce((select jsonb_agg(to_jsonb(item) order by item.message_id desc) from(
 select msg.message_id,msg.request_id,msg.body,msg.attachment_path,msg.created_at,msg.sender_id=uid as is_mine from public.chat_messages msg
 where msg.conversation_id=c.conversation_id and msg.message_id>m.cleared_through and (p_before is null or msg.message_id<p_before)
 order by msg.message_id desc limit p_limit) item),'[]')) into result
 from public.chat_conversations c join public.chat_members m using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id where c.conversation_id=p_conversation_id and m.user_id=uid;
 return result;
end $$;



notify pgrst,'reload schema';
