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
   -- Switching defaults touches two rows. Only the selected row announces the switch.
   if new.is_default and old.is_default is distinct from true then
    changes:=array_append(changes,'Your default service address was updated.');
   end if;
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

-- Keep the selected row default on a repeated selection.
create or replace function private.customer_set_default_address(selected_address uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; result public.saved_addresses%rowtype;
begin
 select c.customer_id into cid from public.customer_profiles c join public.users u using(user_id)
 where u.user_id=private.current_user_id() and u.role='customer' for update of c;
 if cid is null then raise exception 'An active customer account is required' using errcode='42501'; end if;
 select * into result from public.saved_addresses where address_id=selected_address and customer_id=cid;
 if not found then raise exception 'Address not found' using errcode='42501'; end if;
 update public.saved_addresses set is_default=false where customer_id=cid and is_default and address_id<>selected_address;
 update public.saved_addresses set is_default=true where address_id=result.address_id returning * into result;
 update public.customer_profiles set default_address=concat_ws(', ',result.address_line,result.city,result.state,result.postcode),location_coordinates=result.coordinates where customer_id=cid;
 return to_jsonb(result);
end $$;
