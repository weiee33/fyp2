alter table public.chat_messages add column photo_caption text check (length(photo_caption) <= 2000);

create function private.chat_send_photos(p_conversation_id uuid, p_paths text[], p_caption text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  path text;
  request_id uuid;
  result jsonb;
  messages jsonb := '[]';
  caption text := nullif(btrim(p_caption),'');
  expected_caption text;
  stored_caption text;
  already_sent boolean;
begin
  if p_paths is null or cardinality(p_paths) not between 1 and 5 or array_ndims(p_paths) <> 1
     or array_lower(p_paths,1) <> 1 or length(caption) > 2000
     or cardinality(p_paths) <> (select count(distinct name) from unnest(p_paths) name)
  then raise exception 'Invalid photo message'; end if;
  perform pg_advisory_xact_lock(hashtextextended('chat:'||private.chat_actor()::text,0));
  foreach path in array p_paths loop
    request_id := split_part(split_part(path,'/',3),'.',1)::uuid;
    expected_caption := case when path = p_paths[cardinality(p_paths)] then caption end;
    select photo_caption into stored_caption from public.chat_messages where attachment_path=path;
    already_sent := found;
    -- The existing sender locks the conversation, checks ownership and deduplicates retries.
    result := private.chat_send_photo(p_conversation_id,path,request_id);
    if already_sent and stored_caption is distinct from expected_caption then
      raise exception 'Retry must use the original caption';
    end if;
    if expected_caption is not null then
      if not already_sent then
        update public.chat_messages set photo_caption=expected_caption where message_id=(result->>'message_id')::bigint;
      end if;
      result := result || jsonb_build_object('photo_caption',expected_caption);
    end if;
    messages := messages || jsonb_build_array(result);
  end loop;
  return messages;
end $$;

create function public.chat_send_photos(p_conversation_id uuid,p_paths text[],p_caption text)
returns jsonb language sql security invoker set search_path='' as $$
  select private.chat_send_photos($1,$2,$3)
$$;
revoke all on function private.chat_send_photos(uuid,text[],text),public.chat_send_photos(uuid,text[],text) from public,anon;
grant execute on function private.chat_send_photos(uuid,text[],text),public.chat_send_photos(uuid,text[],text) to authenticated;

create or replace function private.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); result jsonb;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid message page'; end if;
 select jsonb_build_object('conversation_id',c.conversation_id,'peer_name',coalesce(p.business_name,u.full_name),'peer_active',u.is_active,
 'cleared_through',m.cleared_through,'blocked',false,'can_send',u.is_active,
 'messages',coalesce((select jsonb_agg(to_jsonb(item) order by item.message_id desc) from(
 select msg.message_id,msg.request_id,msg.body,msg.photo_caption,msg.attachment_path,msg.created_at,msg.sender_id=uid as is_mine from public.chat_messages msg
 where msg.conversation_id=c.conversation_id and msg.message_id>m.cleared_through and (p_before is null or msg.message_id<p_before)
 order by msg.message_id desc limit p_limit) item),'[]')) into result
 from public.chat_conversations c join public.chat_members m using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id where c.conversation_id=p_conversation_id and m.user_id=uid;
 return result;
end $$;



notify pgrst,'reload schema';
