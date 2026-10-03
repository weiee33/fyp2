-- A deleted blocked conversation must still be reachable to unblock it.
create function private.chat_blocked(p_keyword text default '',p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor();
begin
 if length(coalesce(p_keyword,''))>100 or p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000 then raise exception 'Invalid inbox page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x)) from (
 select c.conversation_id,c.last_message_at,m.pinned,m.blocked,coalesce(p.business_name,u.full_name) as peer_name,u.profile_photo_url,
 'Blocked conversation'::text as preview,0::bigint as unread_count
 from public.chat_members m join public.chat_conversations c using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id
 where m.user_id=uid and m.blocked and position(lower(trim(coalesce(p_keyword,''))) in lower(coalesce(p.business_name,u.full_name)))>0
 order by c.last_message_at desc,c.conversation_id limit p_limit offset p_offset) x),'[]');
end $$;
create function public.chat_blocked(p_keyword text default '',p_limit integer default 30,p_offset integer default 0)
returns jsonb language sql stable security invoker set search_path='' as $$select private.chat_blocked(p_keyword,p_limit,p_offset)$$;
revoke all on function private.chat_blocked(text,integer,integer),public.chat_blocked(text,integer,integer) from public,anon;
grant execute on function private.chat_blocked(text,integer,integer),public.chat_blocked(text,integer,integer) to authenticated;
notify pgrst,'reload schema';
