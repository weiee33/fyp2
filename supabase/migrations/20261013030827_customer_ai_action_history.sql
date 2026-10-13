-- Resolve current action state when reopening history instead of replaying a
-- stale pending label from the original model response.
create or replace function private.customer_ai_messages(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform private.ai_owned(p_conversation_id);
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'Invalid page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(m) order by m.id) from(
  select id,role,content,image_path,
   coalesce((select jsonb_agg(case when a.id is null then item else item || jsonb_build_object('status',case when a.status='done' then 'done' when a.expires_at<=now() then 'expired' else 'pending' end) end order by ord)
    from jsonb_array_elements(msg.actions) with ordinality as cards(item,ord)
    left join private.ai_actions a on a.id::text=item->>'id' and a.conversation_id=msg.conversation_id),'[]') as actions,
   created_at from private.ai_messages msg where conversation_id=p_conversation_id and (p_before is null or id<p_before) order by id desc limit p_limit
 )m),'[]');
end $$;
notify pgrst,'reload schema';
