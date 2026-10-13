-- Rename only an active conversation owned by the verified customer.
create function private.customer_ai_rename_conversation(p_conversation_id uuid,p_title text) returns void
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); new_title text:=trim(p_title);
begin
 if new_title is null or length(new_title) not between 1 and 70 or new_title ~ '[[:cntrl:]]' then raise exception 'Enter a chat name between 1 and 70 characters'; end if;
 update private.ai_conversations set title=new_title where id=p_conversation_id and customer_id=cid and deleted_at is null;
 if not found then raise exception 'Conversation not found' using errcode='42501'; end if;
end $$;
create function public.customer_ai_rename_conversation(p_conversation_id uuid,p_title text) returns void
language sql security invoker set search_path='' as $$select private.customer_ai_rename_conversation(p_conversation_id,p_title)$$;
revoke all on function private.customer_ai_rename_conversation(uuid,text),public.customer_ai_rename_conversation(uuid,text) from public,anon;
grant execute on function private.customer_ai_rename_conversation(uuid,text),public.customer_ai_rename_conversation(uuid,text) to authenticated;
notify pgrst,'reload schema';
