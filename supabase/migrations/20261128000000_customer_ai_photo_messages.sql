alter table private.ai_messages add column image_paths text[]
  check (cardinality(image_paths) between 2 and 5);

create or replace function private.customer_ai_messages(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.ai_owned(p_conversation_id);
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.id) from(
  select id,role,content,image_path,image_paths,
   coalesce((select jsonb_agg(case when a.id is null then item else item || jsonb_build_object('status',case when a.status='done' then 'done' when a.expires_at<=now() then 'expired' else 'pending' end) end order by ord)
    from jsonb_array_elements(msg.actions) with ordinality as cards(item,ord)
    left join private.ai_actions a on a.id::text=item->>'id' and a.conversation_id=msg.conversation_id),'[]') as actions,
   created_at,origin,agent_event_kind from private.ai_messages msg where conversation_id=p_conversation_id and (p_before is null or id<p_before) order by id desc limit p_limit
 )m),'[]');
end $$;

create function private.customer_ai_begin_photo_turn(
  p_conversation_id uuid, p_request_id uuid, p_message text, p_image_paths text[], p_mode text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  conversation private.ai_conversations;
  result jsonb;
  turn private.ai_turns;
  saved text[];
begin
  conversation := private.ai_owned(p_conversation_id);
  if p_image_paths is null or cardinality(p_image_paths) not between 2 and 5
     or array_ndims(p_image_paths) <> 1 or array_lower(p_image_paths, 1) <> 1
     or cardinality(p_image_paths) <> (select count(distinct path) from unnest(p_image_paths) path)
  then raise exception 'Choose two to five distinct photos'; end if;

  if exists (
    select from unnest(p_image_paths) path
    where path !~ ('^'||conversation.auth_id::text||'/'||conversation.id::text||'/[0-9a-f-]{36}\.(jpg|png)$')
       or not exists (select from storage.objects where bucket_id='customer-ai-images' and name=path)
  ) then raise exception 'Photo not found' using errcode='42501'; end if;

  result := private.customer_ai_begin_turn(p_conversation_id,p_request_id,p_message,p_image_paths[1],p_mode);
  select * into strict turn from private.ai_turns where conversation_id=p_conversation_id and request_id=p_request_id;
  select image_paths into strict saved from private.ai_messages where turn_id=turn.id and role='user';
  if (turn.tries > 1 or result ? 'replay') and saved is distinct from p_image_paths then
    raise exception 'Retry must use the original photos';
  end if;
  if result ? 'replay' then return result; end if;
  update private.ai_messages set image_paths=p_image_paths where turn_id=turn.id and role='user';
  return result || jsonb_build_object('history',private.customer_ai_messages(p_conversation_id,null,20));
end $$;

create function public.customer_ai_begin_photo_turn(
  p_conversation_id uuid, p_request_id uuid, p_message text, p_image_paths text[], p_mode text
) returns jsonb language sql security invoker set search_path='' as $$
  select private.customer_ai_begin_photo_turn($1,$2,$3,$4,$5)
$$;
revoke all on function private.customer_ai_begin_photo_turn(uuid,uuid,text,text[],text),
  public.customer_ai_begin_photo_turn(uuid,uuid,text,text[],text) from public, anon;
grant execute on function private.customer_ai_begin_photo_turn(uuid,uuid,text,text[],text),
  public.customer_ai_begin_photo_turn(uuid,uuid,text,text[],text) to authenticated;
notify pgrst,'reload schema';
