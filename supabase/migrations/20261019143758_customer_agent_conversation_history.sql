-- Agent transcripts share the existing owned conversation and message paging.
-- Agent events cannot create executable action cards or trusted model turns.
alter table private.ai_messages alter column turn_id drop not null;
alter table private.ai_messages add column origin text not null default 'chat',
 add column agent_event_id uuid, add column agent_event_kind text;
alter table private.ai_messages add constraint ai_message_origin_check check (
 (origin='chat' and turn_id is not null and agent_event_id is null and agent_event_kind is null)
 or (origin='agent' and turn_id is null and agent_event_id is not null
     and agent_event_kind in ('goal','question','reply','progress','result')
     and image_path is null and actions='[]'::jsonb));
create unique index ai_message_agent_event_idx on private.ai_messages(conversation_id,agent_event_id)
 where agent_event_id is not null;

create function private.customer_ai_agent_event(p_conversation_id uuid,p_event_id uuid,p_kind text,p_content text)
returns void language plpgsql security definer set search_path='' as $$
declare c private.ai_conversations; existing private.ai_messages; clean text:=trim(p_content);
begin
 c:=private.ai_owned(p_conversation_id);
 -- Match the chat writer lock order to avoid cross-mode deadlocks.
 perform 1 from public.customer_profiles where customer_id=c.customer_id for update;
 perform 1 from private.ai_conversations where id=c.id and deleted_at is null for update;
 if not found then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_event_id is null or p_kind is null or p_kind not in ('goal','question','reply','progress','result')
 or clean is null or length(clean) not between 1 and 4000 or clean ~ '[\x00-\x08\x0b-\x1f]' then
  raise exception 'Invalid agent event' using errcode='22023'; end if;
 select * into existing from private.ai_messages where conversation_id=c.id and agent_event_id=p_event_id;
 if found then
  if existing.content<>clean or existing.agent_event_kind<>p_kind then
   raise exception 'Agent event already used' using errcode='22023'; end if;
  return;
 end if;
 if (select count(*) from private.ai_messages where conversation_id=c.id)>=400 then
  raise exception 'Start a new chat to continue' using errcode='P0001'; end if;
 if (select count(*) from private.ai_messages m join private.ai_conversations x on x.id=m.conversation_id
     where x.customer_id=c.customer_id and m.origin='agent' and m.created_at>now()-interval '24 hours')>=800 then
  raise exception 'Agent history limit reached' using errcode='P0001'; end if;
 insert into private.ai_messages(conversation_id,role,content,origin,agent_event_id,agent_event_kind)
 values(c.id,case when p_kind in ('goal','reply') then 'user' else 'assistant' end,clean,'agent',p_event_id,p_kind);
 update private.ai_conversations set updated_at=now(),
 title=case when title='New conversation' and p_kind='goal' then left(clean,70) else title end where id=c.id;
end $$;
create function public.customer_ai_agent_event(p_conversation_id uuid,p_event_id uuid,p_kind text,p_content text)
returns void language sql security invoker set search_path='' as $$
 select private.customer_ai_agent_event(p_conversation_id,p_event_id,p_kind,p_content)
$$;
revoke all on function private.customer_ai_agent_event(uuid,uuid,text,text),public.customer_ai_agent_event(uuid,uuid,text,text) from public,anon;
grant execute on function private.customer_ai_agent_event(uuid,uuid,text,text),public.customer_ai_agent_event(uuid,uuid,text,text) to authenticated;

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
   created_at,origin,agent_event_kind from private.ai_messages msg where conversation_id=p_conversation_id and (p_before is null or id<p_before) order by id desc limit p_limit
 )m),'[]');
end $$;
notify pgrst,'reload schema';
