-- Retire blocking for both chat participants. Keep the inert column for older
-- app projections; deletion boundaries, ownership and messages are unchanged.
update public.chat_members set blocked=false where blocked;
alter table public.chat_members add constraint chat_blocking_retired check (not blocked);
drop function public.chat_blocked(text,integer,integer);
drop function private.chat_blocked(text,integer,integer);

create or replace function private.chat_send(p_conversation_id uuid,p_body text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if not exists(select 1 from public.users where user_id=recipient and is_active) then raise exception 'Messages cannot be sent to this conversation'; end if;
 if (select count(*) from public.chat_messages where sender_id=uid and created_at>now()-interval '1 minute')>=30 then raise exception 'Please wait a moment before sending more messages'; end if;
 insert into public.chat_messages(conversation_id,sender_id,request_id,body) values(p_conversation_id,uid,p_request_id,trim(p_body)) returning * into msg;
 update public.chat_conversations set last_message_at=msg.created_at where conversation_id=p_conversation_id;
 update public.chat_members set hidden=false,read_through=case when user_id=uid then msg.message_id else read_through end where conversation_id=p_conversation_id;
 -- Chat events are delivered in-app without copying private message text to email queues.
 insert into public.notifications(user_id,notification_type,title,message,deep_link)
 values(recipient,'Message','New chat message','You have a new message. Open your chat to read it.','chat/'||p_conversation_id::text);
 return jsonb_build_object('message_id',msg.message_id,'request_id',msg.request_id,'body',msg.body,'created_at',msg.created_at,'is_mine',true);
end $$;

create or replace function private.chat_manage(p_conversation_id uuid,p_action text,p_read_through bigint default null) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); last_id bigint;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 perform 1 from public.chat_conversations where conversation_id=p_conversation_id for update;
 select coalesce(max(message_id),0) into last_id from public.chat_messages where conversation_id=p_conversation_id;
 case p_action
 when 'pin','unpin' then update public.chat_members set pinned=p_action='pin' where conversation_id=p_conversation_id and user_id=uid;
 when 'delete' then update public.chat_members set hidden=true,pinned=false,cleared_through=last_id,read_through=last_id where conversation_id=p_conversation_id and user_id=uid;
 when 'read' then update public.chat_members set read_through=greatest(read_through,least(coalesce(p_read_through,0),last_id)) where conversation_id=p_conversation_id and user_id=uid;
 else raise exception 'Unknown chat action'; end case;
end $$;

-- Return the per-member deletion boundary so other devices also clear cached messages.
create or replace function private.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); result jsonb;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid message page'; end if;
 select jsonb_build_object('conversation_id',c.conversation_id,'peer_name',coalesce(p.business_name,u.full_name),'peer_active',u.is_active,
 'cleared_through',m.cleared_through,'blocked',false,'can_send',u.is_active,
 'messages',coalesce((select jsonb_agg(to_jsonb(item) order by item.message_id desc) from(
 select msg.message_id,msg.request_id,msg.body,msg.created_at,msg.sender_id=uid as is_mine from public.chat_messages msg
 where msg.conversation_id=c.conversation_id and msg.message_id>m.cleared_through and (p_before is null or msg.message_id<p_before)
 order by msg.message_id desc limit p_limit) item),'[]')) into result
 from public.chat_conversations c join public.chat_members m using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id where c.conversation_id=p_conversation_id and m.user_id=uid;
 return result;
end $$;


notify pgrst,'reload schema';
