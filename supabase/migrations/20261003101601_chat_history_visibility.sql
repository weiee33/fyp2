-- Return the per-member deletion boundary so other devices also clear cached messages.
create or replace function private.chat_history(p_conversation_id uuid,p_before bigint default null,p_limit integer default 40) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.chat_actor(); result jsonb;
begin
 if not private.chat_member(p_conversation_id) then raise exception 'Conversation not found' using errcode='42501'; end if;
 if p_limit is null or p_limit not between 1 and 100 then raise exception 'Invalid message page'; end if;
 select jsonb_build_object('conversation_id',c.conversation_id,'peer_name',coalesce(p.business_name,u.full_name),'peer_active',u.is_active,
 'cleared_through',m.cleared_through,'blocked',m.blocked,'can_send',u.is_active and not exists(select 1 from public.chat_members where conversation_id=c.conversation_id and blocked),
 'messages',coalesce((select jsonb_agg(to_jsonb(item) order by item.message_id desc) from(
 select msg.message_id,msg.request_id,msg.body,msg.created_at,msg.sender_id=uid as is_mine from public.chat_messages msg
 where msg.conversation_id=c.conversation_id and msg.message_id>m.cleared_through and (p_before is null or msg.message_id<p_before)
 order by msg.message_id desc limit p_limit) item),'[]')) into result
 from public.chat_conversations c join public.chat_members m using(conversation_id)
 join public.users u on u.user_id=case when uid=c.customer_user_id then c.provider_user_id else c.customer_user_id end
 left join public.provider_profiles p on p.user_id=u.user_id where c.conversation_id=p_conversation_id and m.user_id=uid;
 return result;
end $$;

-- Limit new conversation creation without blocking existing conversations.
create or replace function private.chat_open(p_provider_id uuid default null,p_booking_id uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
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
 perform pg_advisory_xact_lock(hashtextextended('chat-open:'||uid::text,0));
 if not exists(select 1 from public.chat_conversations where customer_user_id=customer_uid and provider_user_id=provider_uid)
 and (select count(*) from public.chat_conversations where customer_user_id=uid and created_at>now()-interval '1 minute')>=10
 then raise exception 'Please wait a minute before starting more conversations'; end if;
 insert into public.chat_conversations(customer_user_id,provider_user_id) values(customer_uid,provider_uid)
 on conflict(customer_user_id,provider_user_id) do update set customer_user_id=excluded.customer_user_id returning conversation_id into cid;
 insert into public.chat_members(conversation_id,user_id) values(cid,customer_uid),(cid,provider_uid) on conflict do nothing;
 update public.chat_members set hidden=false where conversation_id=cid and user_id=uid;
 return cid;
end $$;

notify pgrst,'reload schema';
