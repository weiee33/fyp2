-- Stable event identity, independent of translated titles or current account state.
alter table public.notifications add column event_key text;
comment on column public.notifications.event_key is 'Server-assigned event at creation time; null for legacy notifications.';

-- Activity is recorded in the same transaction as the change, never by the client.
create or replace function private.customer_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid; cid uuid; heading text; details text; changes text[] := '{}';
begin
 if tg_table_name='saved_addresses' then
  cid:=case when tg_op='DELETE' then old.customer_id else new.customer_id end;
  select user_id into uid from public.customer_profiles where customer_id=cid;
  if tg_op='INSERT' then heading:='Address added'; changes:=array['A new service address was saved.'];
  elsif tg_op='DELETE' then heading:='Address deleted'; changes:=array['A saved service address was removed.'];
  else
   heading:='Address updated';
   if new.is_default is distinct from old.is_default then changes:=array_append(changes,case when new.is_default then 'This address is now your default service address.' else 'This address is no longer your default service address.' end); end if;
   if new.label is distinct from old.label then changes:=array_append(changes,'Your address label was updated.'); end if;
   if new.address_line is distinct from old.address_line then changes:=array_append(changes,'Your street address was updated.'); end if;
   if new.city is distinct from old.city then changes:=array_append(changes,'Your address city was updated.'); end if;
   if new.state is distinct from old.state then changes:=array_append(changes,'Your address state was updated.'); end if;
   if new.postcode is distinct from old.postcode then changes:=array_append(changes,'Your address postcode was updated.'); end if;
   if new.coordinates is distinct from old.coordinates then changes:=array_append(changes,'Your address map location was updated.'); end if;
  end if;
 elsif tg_table_schema='auth' then
  if new.encrypted_password is not distinct from old.encrypted_password then return null; end if;
  select user_id into uid from public.users where auth_user_id=new.id and role='customer' and is_active;
  heading:='Password changed'; details:='Your account password was changed. If this was not you, reset your password immediately.';
 elsif tg_table_name='users' then
  uid:=new.user_id;
  heading:='Personal information updated';
  if new.full_name is distinct from old.full_name then changes:=array_append(changes,'Your name was updated.'); end if;
  if new.phone is distinct from old.phone then changes:=array_append(changes,'Your phone number was updated.'); end if;
  if new.profile_photo_url is distinct from old.profile_photo_url then changes:=array_append(changes,'Your profile photo was updated.'); end if;
  if new.email is distinct from old.email then changes:=array_append(changes,'Your email address was updated.'); end if;
 else
  uid:=new.user_id;
  heading:='Profile preferences updated';
  if new.bio is distinct from old.bio then changes:=array_append(changes,'Your bio was updated.'); end if;
  if new.gender is distinct from old.gender then changes:=array_append(changes,'Your gender was updated.'); end if;
  if new.birthday is distinct from old.birthday then changes:=array_append(changes,'Your birthday was updated.'); end if;
  if coalesce(new.service_preferences,'{}') is distinct from coalesce(old.service_preferences,'{}') then
   changes:=array_append(changes,case
    when cardinality(coalesce(new.service_preferences,'{}'))=0 then 'Your service preferences were cleared. Explore now shows every service.'
    when coalesce(new.service_preferences,'{}') @> coalesce(old.service_preferences,'{}')
     and coalesce(new.service_preferences,'{}') <@ coalesce(old.service_preferences,'{}') then 'Your preferred service order was updated.'
    else 'Your service selection was updated. Explore now follows your preferences.' end);
  end if;
 end if;
 if details is null then
  if cardinality(changes)=0 then return null; end if;
  details:=array_to_string(changes,E'\n');
 end if;
 -- Deleted/inactive accounts and other roles never receive customer activity.
 if exists(select 1 from public.users where user_id=uid and role='customer' and is_active and auth_user_id is not null) then
  insert into public.notifications(user_id,notification_type,title,message,event_key) values(uid,'System',heading,details,'customer.activity');
 end if;
 return null;
end $$;
revoke all on function private.customer_activity() from public,anon,authenticated;

-- Identify account status at event time using the existing internal helper.
-- Do not infer the status of legacy messages from the current user row.
create or replace function private.admin_notify(recipient uuid,title text,message text,booking uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare nid uuid; event text; heading text:=title; active boolean; customer boolean;
begin
 perform private.admin_actor();
 if title='Account status updated' then
  select is_active,role='customer' into active,customer from public.users where user_id=recipient;
  if customer then
   event:=case when active then 'account.reactivated' else 'account.suspended' end;
   heading:=case when active then 'Account reactivated' else 'Account suspended' end;
  end if;
 end if;
 insert into public.notifications(user_id,booking_id,notification_type,title,message,event_key)
 values(recipient,booking,'System',heading,left(message,500),event) returning notification_id into nid;
 insert into private.notification_outbox(notification_id,recipient_user_id) values(nid,recipient);
end $$;
revoke all on function private.admin_notify(uuid,text,text,uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
