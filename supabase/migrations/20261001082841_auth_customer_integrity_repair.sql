-- Repair SQL Editor drift without deleting accounts or application records.
alter table private.admin_invitations add column revoked_at timestamptz;
update private.admin_invitations set revoked_at=now()
where email='weiee0303@gmail.com' and accepted_by is null;
insert into private.admin_invitations(email,role_level)
values ('angethan765@gmail.com','super_admin') on conflict(email) do nothing;

create or replace function private.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path='' as $$
declare assigned_role public.user_role; display_name text;
begin
 -- Reserved administrators receive their profile only after verified invitation acceptance.
 if exists(select 1 from private.admin_invitations where email=lower(new.email) and revoked_at is null) then return new; end if;
 assigned_role=case when new.raw_user_meta_data->>'role'='provider' then 'provider'::public.user_role else 'customer'::public.user_role end;
 display_name=left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1),'Account'),150);
 insert into public.users(user_id,auth_user_id,email,full_name,phone,role,is_active,email_verified)
 values(new.id,new.id,new.email,display_name,nullif(trim(new.raw_user_meta_data->>'phone'),''),assigned_role,true,new.email_confirmed_at is not null);
 if assigned_role='provider' then
  insert into public.provider_profiles(user_id,business_name,verification_status) values(new.id,display_name,'Pending');
 else insert into public.customer_profiles(user_id,service_preferences) values(new.id,'{}'); end if;
 return new;
end $$;
drop trigger on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.handle_new_auth_user();
drop function if exists public.handle_new_user();

-- UUID identity is evidence of linkage; never link arbitrary profiles merely by email.
update public.users u set auth_user_id=a.id,email_verified=a.email_confirmed_at is not null
from auth.users a where u.user_id=a.id and u.auth_user_id is null
and not exists(select 1 from public.users linked where linked.auth_user_id=a.id);
-- Recover missing ordinary signup profiles; reserved admins stay pending verification.
insert into public.users(user_id,auth_user_id,email,full_name,role,is_active,email_verified)
select a.id,a.id,a.email,left(coalesce(nullif(trim(a.raw_user_meta_data->>'full_name'),''),split_part(a.email,'@',1)),150),
case when a.raw_user_meta_data->>'role'='provider' then 'provider'::public.user_role else 'customer'::public.user_role end,
true,a.email_confirmed_at is not null
from auth.users a where a.email is not null
and not exists(select 1 from public.users u where u.auth_user_id=a.id or u.user_id=a.id or lower(u.email)=lower(a.email))
and not exists(select 1 from private.admin_invitations i where i.email=lower(a.email) and i.revoked_at is null);
insert into public.customer_profiles(user_id) select user_id from public.users where role='customer' and auth_user_id is not null on conflict(user_id) do nothing;
insert into public.provider_profiles(user_id,business_name) select user_id,full_name from public.users where role='provider' and auth_user_id is not null on conflict(user_id) do nothing;

create function private.sync_auth_email() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.users set email=new.email,email_verified=new.email_confirmed_at is not null where auth_user_id=new.id;
 return new;
end $$;
revoke all on function private.sync_auth_email() from public,anon,authenticated;
create trigger on_auth_email_updated after update of email,email_confirmed_at on auth.users
for each row execute function private.sync_auth_email();

create or replace function private.accept_admin_invitation() returns jsonb
language plpgsql security definer set search_path='' as $$
declare identity auth.users%rowtype; invitation private.admin_invitations%rowtype; uid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into identity from auth.users where id=auth.uid();
 if identity.email_confirmed_at is null then raise exception 'Verify your email before continuing' using errcode='42501'; end if;
 select user_id into uid from public.users where auth_user_id=identity.id;
 if uid is not null then
  -- An invitation never converts an established mobile account or revives a suspension.
  perform private.admin_actor(false);
 else
  select * into invitation from private.admin_invitations where email=lower(identity.email) and revoked_at is null for update;
  if not found or invitation.accepted_by is not null then raise exception 'An unused administrator invitation is required' using errcode='42501'; end if;
  if exists(select 1 from public.users where lower(email)=lower(identity.email)) then
   raise exception 'An existing profile requires an administrator to link its Auth identity';
  end if;
  insert into public.users(user_id,auth_user_id,email,full_name,role,email_verified)
  values(identity.id,identity.id,identity.email,split_part(identity.email,'@',1),'admin',true) returning user_id into uid;
  insert into public.admin_profiles(user_id,admin_role_level,two_factor_enabled) values(uid,invitation.role_level,true);
  update private.admin_invitations set accepted_by=identity.id,accepted_at=now() where email=invitation.email;
 end if;
 return (select jsonb_build_object('user_id',u.user_id,'email',u.email,'full_name',u.full_name,'role_level',a.admin_role_level,
 'mfa_verified',coalesce(auth.jwt()->>'aal','')='aal2') from public.users u join public.admin_profiles a using(user_id) where u.user_id=private.admin_actor(false));
end $$;

-- Minimal preflight for the PHP activation form. It discloses no account/profile data.
create function public.admin_registration_check(invited_email text) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from private.admin_invitations i where i.email=lower(trim(invited_email)) and i.revoked_at is null and i.accepted_by is null)
 or exists(select 1 from public.users u where lower(u.email)=lower(trim(invited_email))) then
  raise exception 'Use an unused invited admin email. Existing accounts should sign in.' using errcode='42501';
 end if;
 return jsonb_build_object('eligible',true);
end $$;
revoke all on function public.admin_registration_check(text) from public;
grant execute on function public.admin_registration_check(text) to anon,authenticated;

create function public.account_identity() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 select jsonb_build_object('user_id',u.user_id,'role',u.role,'full_name',u.full_name,'customer_id',c.customer_id,'provider_id',p.provider_id)
 into result from public.users u left join public.customer_profiles c using(user_id) left join public.provider_profiles p using(user_id)
 where u.user_id=private.current_user_id();
 if result is null then raise exception 'An active application account is required' using errcode='42501'; end if;
 return result;
end $$;
revoke all on function public.account_identity() from public,anon;
grant execute on function public.account_identity() to authenticated;

drop trigger if exists trg_review_rating_sync on public.reviews;
drop function if exists public.update_provider_rating();

-- Remove only the manually added duplicate/unsafe policies, preserving canonical ones.
do $$declare row record; begin
 for row in select * from pg_policies where schemaname='public' and policyname=any(array[
 'Customers can cancel own pending bookings','Customers can create bookings','Customers can read own bookings',
 'Customers can view own payments','Anyone can view approved reviews','Customers can create verified reviews',
 'Users update own notification read state','Users view own notifications','Customers view own AI recommendations',
 'Customers manage own chatbot sessions','Customers manage own chatbot messages','Users can read own record',
 'Users can update own record','Customers can read own profile','Customers can update own profile','Customers manage own addresses'])
 loop execute format('drop policy %I on %I.%I',row.policyname,row.schemaname,row.tablename); end loop;
end $$;

-- Composite FKs supplement existing FKs, enforcing the relationship as a whole.
alter table public.services add constraint services_id_provider_key unique(service_id,provider_id),
 add constraint service_positive_duration check(estimated_duration>0);
alter table public.bookings add constraint booking_service_provider_fk foreign key(service_id,provider_id) references public.services(service_id,provider_id),
 add constraint bookings_parties_key unique(booking_id,customer_id,provider_id),
 add constraint bookings_customer_key unique(booking_id,customer_id),
 add constraint bookings_provider_key unique(booking_id,provider_id);
alter table public.payments add constraint payment_booking_customer_fk foreign key(booking_id,customer_id) references public.bookings(booking_id,customer_id);
alter table public.reviews add constraint review_booking_parties_fk foreign key(booking_id,customer_id,provider_id) references public.bookings(booking_id,customer_id,provider_id);
alter table public.provider_earnings add constraint earnings_booking_provider_fk foreign key(booking_id,provider_id) references public.bookings(booking_id,provider_id),
 add constraint earnings_booking_key unique(booking_id), add constraint earnings_fee_bound check(platform_fee<=gross_amount);
alter table public.provider_working_hours add constraint hours_ordered check(end_time>start_time);
alter table public.provider_profiles add constraint provider_nonnegative_metrics check(years_experience>=0 and total_reviews>=0 and service_radius_km>0);
create unique index saved_addresses_one_default on public.saved_addresses(customer_id) where is_default is true;

create function public.customer_save_address(address_label text,address_text text,address_city text,address_state text,address_postcode text,
 latitude double precision,longitude double precision,make_default boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; result public.saved_addresses%rowtype; use_default boolean;
begin
 select c.customer_id into cid from public.customer_profiles c join public.users u using(user_id)
 where u.user_id=private.current_user_id() and u.role='customer' for update of c;
 if cid is null then raise exception 'An active customer account is required' using errcode='42501'; end if;
 if address_label is null or length(trim(address_label)) not between 1 and 50 or address_text is null or length(trim(address_text)) not between 3 and 1000
 or address_city is null or length(trim(address_city)) not between 1 and 100 or address_state is null or length(trim(address_state)) not between 1 and 100
 or address_postcode is null or address_postcode !~ '^[0-9]{5}$'
 or latitude is null or not(latitude between -90 and 90) or longitude is null or not(longitude between -180 and 180) then
 raise exception 'Enter a valid address, Malaysian postcode and coordinates'; end if;
 use_default=coalesce(make_default,false) or not exists(select 1 from public.saved_addresses where customer_id=cid);
 if use_default then update public.saved_addresses set is_default=false where customer_id=cid and is_default; end if;
 insert into public.saved_addresses(customer_id,label,address_line,city,state,postcode,coordinates,is_default)
 values(cid,trim(address_label),trim(address_text),trim(address_city),trim(address_state),address_postcode,latitude::text||','||longitude::text,use_default) returning * into result;
 if use_default then update public.customer_profiles set default_address=concat_ws(', ',result.address_line,result.city,result.state,result.postcode),location_coordinates=result.coordinates where customer_id=cid; end if;
 return to_jsonb(result);
end $$;
create function public.customer_set_default_address(selected_address uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid; result public.saved_addresses%rowtype;
begin
 select c.customer_id into cid from public.customer_profiles c join public.users u using(user_id)
 where u.user_id=private.current_user_id() and u.role='customer' for update of c;
 if cid is null then raise exception 'An active customer account is required' using errcode='42501'; end if;
 select * into result from public.saved_addresses where address_id=selected_address and customer_id=cid;
 if not found then raise exception 'Address not found' using errcode='42501'; end if;
 update public.saved_addresses set is_default=false where customer_id=cid and is_default;
 update public.saved_addresses set is_default=true where address_id=result.address_id returning * into result;
 update public.customer_profiles set default_address=concat_ws(', ',result.address_line,result.city,result.state,result.postcode),location_coordinates=result.coordinates where customer_id=cid;
 return to_jsonb(result);
end $$;
revoke all on function public.customer_save_address(text,text,text,text,text,double precision,double precision,boolean),public.customer_set_default_address(uuid) from public,anon;
grant execute on function public.customer_save_address(text,text,text,text,text,double precision,double precision,boolean),public.customer_set_default_address(uuid) to authenticated;

create function public.customer_provider_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.users where user_id=private.current_user_id() and role='customer') then
 raise exception 'An active customer account is required' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(entry)) from (
 select p.provider_id,p.business_name,p.overall_rating,p.total_reviews,u.profile_photo_url as image_url,true as is_verified,
 s.service_name,s.base_price,'Verified provider'::text as match_tag,
 (select count(*) from public.bookings b where b.provider_id=p.provider_id and b.booking_status='Completed') as total_jobs
 from public.provider_profiles p join public.users u using(user_id)
 join lateral(select sv.service_name,sv.base_price from public.services sv join public.service_categories sc using(category_id)
 where sv.provider_id=p.provider_id and sv.is_active is true and sv.availability_status is true and sc.is_active is true order by sv.base_price,sv.service_id limit 1) s on true
 where p.verification_status='Verified' and u.is_active is true
 order by p.overall_rating desc nulls last,p.total_reviews desc nulls last,p.provider_id limit 5
 ) entry),'[]'::jsonb);
end $$;
revoke all on function public.customer_provider_directory() from public,anon;
grant execute on function public.customer_provider_directory() to authenticated;
notify pgrst,'reload schema';
