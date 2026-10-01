-- Additive upgrade of the existing 28-table FYP database. No application rows are deleted.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter table public.users add column auth_user_id uuid unique references auth.users(id) on delete restrict;
update public.users u set auth_user_id = a.id from auth.users a where u.user_id = a.id;
alter table public.users alter column password_hash drop not null;
comment on column public.users.password_hash is 'Legacy field. Authentication uses Supabase Auth; never expose or populate from application code.';
alter table public.reviews add column moderation_status text not null default 'visible'
  check (moderation_status in ('visible','hidden'));
alter table public.reviews add column moderation_reason text;

create table private.admin_invitations (
 email text primary key check (email=lower(email)),
 role_level public.admin_role_level not null default 'staff',
 accepted_by uuid references auth.users(id),
 created_at timestamptz not null default now(), accepted_at timestamptz
);
insert into private.admin_invitations(email,role_level) values ('weiee0303@gmail.com','super_admin');
alter table private.admin_invitations enable row level security;

create table public.booking_disputes (
 dispute_id uuid primary key default gen_random_uuid(),
 booking_id uuid not null references public.bookings(booking_id),
 opened_by uuid not null references public.users(user_id),
 subject text not null check (length(trim(subject)) between 3 and 150),
 description text not null check (length(trim(description)) between 10 and 4000),
 status text not null default 'Open' check(status in ('Open','Under Review','Resolved','Dismissed')),
 resolution text, resolved_by uuid references public.admin_profiles(admin_id),
 resolved_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(status not in ('Resolved','Dismissed') or (resolution is not null and length(trim(resolution)) >= 10 and resolved_at is not null and resolved_by is not null))
);
create unique index one_open_dispute_per_booking on public.booking_disputes(booking_id) where status in ('Open','Under Review');
create table public.refund_requests (
 refund_id uuid primary key default gen_random_uuid(),
 payment_id uuid not null references public.payments(payment_id),
 dispute_id uuid references public.booking_disputes(dispute_id),
 amount numeric(12,2) not null check(amount>0), reason text not null check(length(trim(reason))>=10),
 status text not null default 'Requested' check(status in ('Requested','Processing','Succeeded','Failed','Cancelled')),
 requested_by uuid not null references public.admin_profiles(admin_id),
 gateway_reference text unique, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index one_pending_refund_per_payment on public.refund_requests(payment_id) where status in ('Requested','Processing');
create table private.notification_outbox (
 outbox_id uuid primary key default gen_random_uuid(), notification_id uuid not null unique references public.notifications(notification_id),
 recipient_user_id uuid not null references public.users(user_id),
 channel text not null default 'email' check(channel='email'), status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
 attempts integer not null default 0, available_at timestamptz not null default now(), last_error text, created_at timestamptz not null default now()
);
alter table public.booking_disputes enable row level security;
alter table public.refund_requests enable row level security;
alter table private.notification_outbox enable row level security;
create index booking_disputes_opened_by_idx on public.booking_disputes(opened_by);
create index booking_disputes_resolved_by_idx on public.booking_disputes(resolved_by);
create index refund_requests_payment_idx on public.refund_requests(payment_id);
create index refund_requests_dispute_idx on public.refund_requests(dispute_id);
create index refund_requests_admin_idx on public.refund_requests(requested_by);

create or replace function private.current_user_id() returns uuid language sql stable security definer set search_path = '' as $$
 select user_id from public.users where auth_user_id=(select auth.uid()) and is_active is true
$$;
create or replace function private.admin_actor(require_mfa boolean default true) returns uuid language plpgsql stable security definer set search_path = '' as $$
declare actor uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select u.user_id into actor from public.users u join public.admin_profiles a using(user_id)
 where u.auth_user_id=auth.uid() and u.role='admin' and u.is_active is true;
 if actor is null then raise exception 'An active administrator account is required' using errcode='42501'; end if;
 if require_mfa and coalesce(auth.jwt()->>'aal','') <> 'aal2' then raise exception 'Complete authenticator verification first' using errcode='42501'; end if;
 return actor;
end $$;
create or replace function private.is_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select coalesce(auth.jwt()->>'aal','')='aal2' and exists(
 select 1 from public.users u join public.admin_profiles a using(user_id)
 where u.auth_user_id=auth.uid() and u.role='admin' and u.is_active is true)
$$;
create function private.provider_is_visible(provider uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.provider_profiles p join public.users u using(user_id) where p.provider_id=provider and p.verification_status='Verified' and u.is_active is true)
$$;
create function private.service_is_visible(provider uuid,category uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.provider_is_visible(provider) and exists(select 1 from public.service_categories where category_id=category and is_active is true)
$$;

create function private.accept_admin_invitation() returns jsonb language plpgsql security definer set search_path = '' as $$
declare identity auth.users%rowtype; invitation private.admin_invitations%rowtype; uid uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into identity from auth.users where id=auth.uid();
 if identity.email_confirmed_at is null then raise exception 'Verify your email before continuing' using errcode='42501'; end if;
 select * into invitation from private.admin_invitations where email=lower(identity.email) for update;
 if not found then perform private.admin_actor(false);
 else
  if invitation.accepted_by is not null and invitation.accepted_by<>identity.id then raise exception 'Invitation already used' using errcode='42501'; end if;
 select user_id into uid from public.users where auth_user_id=identity.id;
  if uid is null then
   if exists(select 1 from public.users where lower(email)=lower(identity.email)) then
    raise exception 'An existing profile requires an administrator to link its Auth identity';
   end if;
   insert into public.users(auth_user_id,email,full_name,role,email_verified) values(identity.id,identity.email,split_part(identity.email,'@',1),'admin',true) returning user_id into uid;
   insert into public.admin_profiles(user_id,admin_role_level) values(uid,invitation.role_level);
  elsif not exists(select 1 from public.admin_profiles where user_id=uid) then
   -- Only the verified, explicitly invited identity can be promoted from a signup profile.
   update public.users set role='admin',email_verified=true where user_id=uid and is_active is true;
   insert into public.admin_profiles(user_id,admin_role_level) values(uid,invitation.role_level);
  end if;
  perform private.admin_actor(false);
  update private.admin_invitations set accepted_by=identity.id,accepted_at=coalesce(accepted_at,now()) where email=invitation.email;
 end if;
 return (select jsonb_build_object('user_id',u.user_id,'email',u.email,'full_name',u.full_name,'role_level',a.admin_role_level,'mfa_verified',coalesce(auth.jwt()->>'aal','')='aal2') from public.users u join public.admin_profiles a using(user_id) where u.user_id=private.admin_actor(false));
end $$;
create function public.admin_identity() returns jsonb language sql security invoker set search_path = '' as $$ select private.accept_admin_invitation() $$;

create function private.handle_new_auth_user() returns trigger language plpgsql security definer set search_path='' as $$
declare assigned_role public.user_role; name text; uid uuid;
begin
 -- Customer/provider is a self-service account choice. Administrative roles never come from metadata.
 assigned_role=case when new.raw_user_meta_data->>'role'='provider' then 'provider'::public.user_role else 'customer'::public.user_role end;
 name=left(coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'),''),split_part(new.email,'@',1),'Account'),150);
 insert into public.users(user_id,auth_user_id,email,full_name,role,is_active,email_verified)
 values(new.id,new.id,new.email,name,assigned_role,true,new.email_confirmed_at is not null) returning user_id into uid;
 if assigned_role='provider' then
  insert into public.provider_profiles(user_id,business_name,verification_status) values(uid,name,'Pending');
 else insert into public.customer_profiles(user_id,service_preferences) values(uid,'{}'); end if;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.handle_new_auth_user();
-- Remove access to the obsolete metadata-driven trigger function if it exists.
do $$ begin
 if to_regprocedure('public.handle_new_user()') is not null then
  execute 'drop function public.handle_new_user()';
 end if;
end $$;

-- Remove unsafe table-wide mutation privileges. RLS never protects TRUNCATE.
revoke all on all tables in schema public from anon, authenticated;
-- Remove duplicate permissive policies found at preflight. Permissive policies OR together,
-- so a second USING(true) defeats the more restrictive ownership/verification policies.
do $$ declare p record; begin
 for p in select tablename,policyname from pg_policies where schemaname='public' and policyname<>all(array[
 'users_self_select','users_self_update','customer_profile_owner','saved_addresses_owner','provider_public_read','provider_self',
 'provider_cert_owner','provider_hours_owner','services_provider_write','services_public_read','bookings_party_read','payments_customer',
 'earnings_provider','reviews_customer_write','reviews_public_read','notifications_own','chatbot_sessions_own','chatbot_messages_own',
 'ai_rec_own','ai_matches_provider','ai_schedules_provider','audit_admin_only']) loop
 execute format('drop policy %I on public.%I',p.policyname,p.tablename);
 end loop;
end $$;
grant select(user_id,auth_user_id,email,phone,full_name,role,profile_photo_url,is_active,email_verified,phone_verified,last_login_at,created_at,updated_at) on public.users to authenticated;
grant update(full_name,phone,profile_photo_url) on public.users to authenticated;
drop policy users_self_select on public.users;
drop policy users_self_update on public.users;
create policy users_self_select on public.users for select to authenticated using(auth_user_id=(select auth.uid()));
create policy users_self_update on public.users for update to authenticated using(user_id=(select private.current_user_id())) with check(user_id=(select private.current_user_id()));
grant select on public.customer_profiles,public.saved_addresses,public.provider_working_hours,public.provider_portfolio,public.provider_certifications,public.services,public.bookings,public.payments,public.provider_earnings,public.reviews,public.notifications,public.ai_job_matches,public.ai_schedules,public.ai_recommendations,public.chatbot_sessions,public.chatbot_messages to authenticated;
grant select(provider_id,user_id,business_name,bio,years_experience,verification_status,overall_rating,total_reviews,service_radius_km,region,city,created_at,updated_at) on public.provider_profiles to anon,authenticated;
drop policy provider_public_read on public.provider_profiles;
create policy provider_public_read on public.provider_profiles for select to anon,authenticated using((select private.provider_is_visible(provider_id)));
drop policy services_public_read on public.services;
create policy services_public_read on public.services for select to anon,authenticated using(is_active is true and availability_status is true and (select private.service_is_visible(provider_id,category_id)));
grant select on public.services to anon;
grant update(business_name,business_license,bio,years_experience,service_radius_km,region,city) on public.provider_profiles to authenticated;
grant update(is_read) on public.notifications to authenticated;
grant select on public.service_categories to anon,authenticated;
create policy categories_active_read on public.service_categories for select to anon,authenticated using(is_active is true);
create policy portfolio_owner_read on public.provider_portfolio for select to authenticated using(provider_id in(select provider_id from public.provider_profiles where user_id=(select private.current_user_id())));
-- Profiles have independent primary keys; ownership follows the explicit Auth mapping.
do $$ declare p record; predicate text; check_predicate text; begin
 for p in select * from pg_policies where schemaname='public' and tablename<>'users' and (coalesce(qual,'') like '%auth.uid()%' or coalesce(with_check,'') like '%auth.uid()%') loop
  predicate=replace(p.qual,'auth.uid()','(select private.current_user_id())');
  check_predicate=replace(p.with_check,'auth.uid()','(select private.current_user_id())');
  execute format('alter policy %I on public.%I to authenticated%s%s',p.policyname,p.tablename,
    case when predicate is null then '' else ' using ('||predicate||')' end,
    case when check_predicate is null then '' else ' with check ('||check_predicate||')' end);
 end loop;
end $$;
-- Every authenticated client access also requires an active application account.
do $$ declare t record; begin for t in select tablename from pg_tables where schemaname='public' loop
 execute format('create policy active_account_required on public.%I as restrictive for all to authenticated using ((select private.current_user_id()) is not null) with check ((select private.current_user_id()) is not null)',t.tablename);
end loop; end $$;
-- Storage writes must belong to the authenticated uploader and their own folder.
drop policy "Profiles 1ige2ga_1" on storage.objects;
drop policy "Profiles 1ige2ga_2" on storage.objects;
drop policy "Profiles 1ige2ga_3" on storage.objects;
create policy profile_insert_own on storage.objects for insert to authenticated with check(bucket_id='profiles' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.current_user_id()) is not null);
create policy profile_update_own on storage.objects for update to authenticated using(bucket_id='profiles' and owner_id=(select auth.uid())::text and (select private.current_user_id()) is not null) with check(bucket_id='profiles' and owner_id=(select auth.uid())::text and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy profile_delete_own on storage.objects for delete to authenticated using(bucket_id='profiles' and owner_id=(select auth.uid())::text and (select private.current_user_id()) is not null);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('provider-documents','provider-documents',false,10485760,array['application/pdf','image/jpeg','image/png']);
create policy credential_admin_read on storage.objects for select to authenticated using(bucket_id='provider-documents' and (select private.is_admin()));
create policy credential_owner_read on storage.objects for select to authenticated using(bucket_id='provider-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.current_user_id()) is not null);
create policy credential_owner_insert on storage.objects for insert to authenticated with check(bucket_id='provider-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and (select private.current_user_id()) is not null);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('category-icons','category-icons',true,1048576,array['image/jpeg','image/png','image/webp']);
create policy category_icon_public_read on storage.objects for select to anon,authenticated using(bucket_id='category-icons');
create policy category_icon_admin_insert on storage.objects for insert to authenticated with check(bucket_id='category-icons' and (select private.is_admin()));
create policy category_icon_admin_delete on storage.objects for delete to authenticated using(bucket_id='category-icons' and (select private.is_admin()));

create or replace function public.set_updated_at() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
create or replace function public.refresh_provider_rating() returns trigger language plpgsql security definer set search_path='' as $$
declare ids uuid[];
begin
 if TG_OP='DELETE' then ids=array[old.provider_id]; elsif TG_OP='UPDATE' then ids=array[old.provider_id,new.provider_id]; else ids=array[new.provider_id]; end if;
 update public.provider_profiles p set overall_rating=coalesce((select round(avg(r.rating_score),2) from public.reviews r where r.provider_id=p.provider_id and not r.is_flagged and r.moderation_status='visible'),0),
 total_reviews=(select count(*) from public.reviews r where r.provider_id=p.provider_id and not r.is_flagged and r.moderation_status='visible') where p.provider_id=any(ids);
 if TG_OP='DELETE' then return old; end if; return new;
end $$;
create or replace function public.log_booking_status_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.booking_status is distinct from new.booking_status then
 insert into public.booking_status_history(booking_id,previous_status,new_status,changed_by,notes) values(new.booking_id,old.booking_status,new.booking_status,private.current_user_id(),nullif(current_setting('app.action_reason',true),''));
 end if; return new;
end $$;
revoke execute on function public.set_updated_at(),public.refresh_provider_rating(),public.log_booking_status_change() from public,anon,authenticated;
drop policy reviews_public_read on public.reviews;
create policy reviews_public_read on public.reviews for select to authenticated using(is_flagged=false and moderation_status='visible');

-- Index every uncovered foreign key using the leading key columns, not arbitrary index membership.
do $$ declare r record; begin
 for r in select c.conrelid::regclass as tbl,c.conname,string_agg(quote_ident(a.attname),',' order by k.ord) as cols
 from pg_constraint c cross join lateral unnest(c.conkey) with ordinality k(attnum,ord)
 join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
 where c.contype='f' and c.connamespace='public'::regnamespace and not exists(
 select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid and i.indpred is null and array(select k from unnest(i.indkey) with ordinality x(k,ord) where ord<=cardinality(c.conkey) order by ord)=c.conkey)
 group by c.oid,c.conrelid,c.conname loop
 execute format('create index if not exists %I on %s (%s)',left(r.conname,55)||'_idx',r.tbl,r.cols);
 end loop;
end $$;

create function private.admin_list(resource text,search text,status_filter text,page_number integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare source text; result jsonb;
begin
 perform private.admin_actor();
 if page_number is null or page_number<1 or page_number>100000 then raise exception 'Invalid page'; end if;
 if length(search)>100 then raise exception 'Search must be at most 100 characters'; end if;
 case resource
 when 'users' then source=$q$select (to_jsonb(u)-'password_hash')||jsonb_build_object('version',md5(to_jsonb(u)::text),'status',case when u.is_active then 'Active' else 'Suspended' end) as item,u.created_at from public.users u$q$;
 when 'providers' then source=$q$select to_jsonb(p)||jsonb_build_object('version',md5(to_jsonb(p)::text),'full_name',u.full_name,'email',u.email,'is_active',u.is_active,'status',p.verification_status) as item,p.created_at from public.provider_profiles p join public.users u using(user_id)$q$;
 when 'categories' then source=$q$select to_jsonb(c)||jsonb_build_object('version',md5(to_jsonb(c)::text),'parent_name',p.category_name,'status',case when c.is_active then 'Active' else 'Inactive' end,'service_count',(select count(*) from public.services s where s.category_id=c.category_id)) as item,c.created_at from public.service_categories c left join public.service_categories p on p.category_id=c.parent_category_id$q$;
 when 'bookings' then source=$q$select to_jsonb(b)||jsonb_build_object('version',md5(to_jsonb(b)::text),'customer_name',u.full_name,'provider_name',p.business_name,'service_name',s.service_name,'status',b.booking_status,'payment_status',pay.payment_status) as item,b.created_at from public.bookings b join public.customer_profiles c using(customer_id) join public.users u on u.user_id=c.user_id join public.provider_profiles p using(provider_id) join public.services s using(service_id) left join public.payments pay using(booking_id)$q$;
 when 'reviews' then source=$q$select to_jsonb(r)||jsonb_build_object('version',md5(to_jsonb(r)::text),'customer_name',u.full_name,'provider_name',p.business_name,'status',case when r.moderation_status='hidden' then 'Hidden' when r.is_flagged then 'Flagged' else 'Visible' end) as item,r.created_at from public.reviews r join public.customer_profiles c using(customer_id) join public.users u on u.user_id=c.user_id join public.provider_profiles p using(provider_id)$q$;
 when 'disputes' then source=$q$select to_jsonb(d)||jsonb_build_object('version',md5(to_jsonb(d)::text),'opened_by_name',u.full_name) as item,d.created_at from public.booking_disputes d join public.users u on u.user_id=d.opened_by$q$;
 when 'refunds' then source=$q$select to_jsonb(r)||jsonb_build_object('booking_id',p.booking_id) as item,r.created_at from public.refund_requests r join public.payments p using(payment_id)$q$;
 when 'audit' then
 if not exists(select 1 from public.admin_profiles where user_id=private.admin_actor() and admin_role_level='super_admin') then raise exception 'Super Admin required' using errcode='42501'; end if;
 source=$q$select to_jsonb(l)||jsonb_build_object('actor_name',u.full_name,'status',l.action) as item,l.created_at from public.audit_logs l left join public.users u on u.user_id=l.actor_id$q$;
 else raise exception 'Unknown resource'; end case;
 execute 'with entries as ('||source||'), filtered as (select * from entries where ($1='''' or position(lower($1) in lower(item::text))>0) and ($2='''' or item->>''status''=$2)) select jsonb_build_object(''total'',(select count(*) from filtered),''page'',$3,''page_size'',20,''items'',coalesce((select jsonb_agg(item) from (select item from filtered order by created_at desc,item::text limit 20 offset (($3-1)*20)) paged),''[]''::jsonb))' into result using coalesce(search,''),coalesce(status_filter,''),page_number;
 return result;
end $$;
create function public.admin_list(resource text,search text default '',status_filter text default '',page_number integer default 1) returns jsonb language sql security invoker set search_path='' as $$select private.admin_list(resource,search,status_filter,page_number)$$;

create function private.admin_detail(resource text,record_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform private.admin_actor();
 case resource
 when 'users' then select (to_jsonb(u)-'password_hash')||jsonb_build_object('version',md5(to_jsonb(u)::text),'actions',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.user_account_actions a where a.user_id=u.user_id),'[]')) into result from public.users u where user_id=record_id;
 when 'providers' then select to_jsonb(p)||jsonb_build_object('version',md5(to_jsonb(p)::text),'full_name',u.full_name,'email',u.email,'is_active',u.is_active,'certifications',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('version',md5(to_jsonb(c)::text))) from public.provider_certifications c where c.provider_id=p.provider_id),'[]'),'portfolio',coalesce((select jsonb_agg(to_jsonb(f)) from public.provider_portfolio f where f.provider_id=p.provider_id),'[]'),'hours',coalesce((select jsonb_agg(to_jsonb(h) order by h.day_of_week) from public.provider_working_hours h where h.provider_id=p.provider_id),'[]')) into result from public.provider_profiles p join public.users u using(user_id) where provider_id=record_id;
 when 'categories' then select to_jsonb(c)||jsonb_build_object('version',md5(to_jsonb(c)::text)) into result from public.service_categories c where category_id=record_id;
 when 'bookings' then select to_jsonb(b)||jsonb_build_object('version',md5(to_jsonb(b)::text),'customer_name',u.full_name,'provider_name',p.business_name,'service_name',s.service_name,'history',coalesce((select jsonb_agg(to_jsonb(h) order by created_at) from public.booking_status_history h where h.booking_id=b.booking_id),'[]'),'payment',(select to_jsonb(pay)||jsonb_build_object('version',md5(to_jsonb(pay)::text)) from public.payments pay where pay.booking_id=b.booking_id),'disputes',coalesce((select jsonb_agg(to_jsonb(d)) from public.booking_disputes d where d.booking_id=b.booking_id),'[]')) into result from public.bookings b join public.customer_profiles c using(customer_id) join public.users u on u.user_id=c.user_id join public.provider_profiles p using(provider_id) join public.services s using(service_id) where b.booking_id=record_id;
 when 'reviews' then select to_jsonb(r)||jsonb_build_object('version',md5(to_jsonb(r)::text)) into result from public.reviews r where review_id=record_id;
 when 'disputes' then select to_jsonb(d)||jsonb_build_object('version',md5(to_jsonb(d)::text)) into result from public.booking_disputes d where dispute_id=record_id;
 else raise exception 'Unknown resource'; end case;
 if result is null then raise exception 'Record not found' using errcode='P0002'; end if; return result;
end $$;
create function public.admin_detail(resource text,record_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.admin_detail(resource,record_id)$$;

create function private.admin_document(record_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare document_path text;
begin
 perform private.admin_actor();
 select file_url into document_path from public.provider_certifications where certification_id=record_id;
 if document_path is null then raise exception 'Credential document not found'; end if;
 if document_path not like 'provider-documents/%' or document_path like '%..%' then raise exception 'This credential must be stored in the private provider-documents bucket'; end if;
 return jsonb_build_object('path',substr(document_path,length('provider-documents/')+1));
end $$;
create function public.admin_document(record_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select private.admin_document(record_id) $$;

create function private.admin_notify(recipient uuid,title text,message text,booking uuid default null) returns void language plpgsql security definer set search_path='' as $$
declare nid uuid;
begin
 perform private.admin_actor();
 insert into public.notifications(user_id,booking_id,notification_type,title,message) values(recipient,booking,'System',title,left(message,500)) returning notification_id into nid;
 insert into private.notification_outbox(notification_id,recipient_user_id) values(nid,recipient);
end $$;

create function private.admin_mutate(action_name text,record_id uuid,expected_version text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; aid uuid; is_super boolean; before_row jsonb; after_row jsonb; target text; pk text; note text; desired text; parent uuid; bid uuid; recipient uuid; status_now text; total numeric; refund_total numeric;
begin
 actor=private.admin_actor(); select admin_id,admin_role_level='super_admin' into aid,is_super from public.admin_profiles where user_id=actor;
 if payload is null or jsonb_typeof(payload)<>'object' then raise exception 'Invalid form data'; end if;
 note=trim(coalesce(payload->>'reason',''));
 case action_name
 when 'user_status' then target='users';pk='user_id';
 when 'provider_verify' then target='provider_profiles';pk='provider_id';
 when 'certificate_verify' then target='provider_certifications';pk='certification_id';
 when 'category_save','category_delete' then target='service_categories';pk='category_id';
 when 'booking_status','dispute_open' then target='bookings';pk='booking_id';
 when 'review_moderate' then target='reviews';pk='review_id';
 when 'dispute_resolve' then target='booking_disputes';pk='dispute_id';
 when 'refund_request' then target='payments';pk='payment_id';
 else raise exception 'Unsupported action'; end case;
 if record_id is not null then
 execute format('select to_jsonb(t) from public.%I t where %I=$1 for update',target,pk) into before_row using record_id;
 if before_row is null then raise exception 'Record not found'; end if;
 if expected_version is null or expected_version<>md5(before_row::text) then raise exception 'This record changed. Reload it before trying again.' using errcode='40001'; end if;
 elsif action_name<>'category_save' then raise exception 'Record ID required'; end if;
 if action_name not in ('category_save','category_delete') and (length(note)<10 or length(note)>1000) then raise exception 'Provide a reason between 10 and 1000 characters'; end if;
 case action_name
 when 'user_status' then
 if before_row->>'role'='admin' then raise exception 'Administrator accounts cannot be suspended from this screen'; end if;
 if coalesce(payload->>'active','') not in ('true','false') then raise exception 'Invalid account status'; end if;
 update public.users set is_active=(payload->>'active')::boolean where user_id=record_id;
 insert into public.user_account_actions(user_id,admin_id,action_type,reason) values(record_id,aid,case when (payload->>'active')::boolean then 'Reactivate' else 'Suspend' end,note);
 perform private.admin_notify(record_id,'Account status updated',note);
 when 'certificate_verify' then
 if coalesce(payload->>'verified','') not in ('true','false') then raise exception 'Invalid verification choice'; end if;
 if (payload->>'verified')::boolean and ((before_row->>'expiry_date')::date < (now() at time zone 'Asia/Kuala_Lumpur')::date or nullif(before_row->>'file_url','') is null) then raise exception 'A current credential document is required'; end if;
 update public.provider_certifications set is_verified=(payload->>'verified')::boolean where certification_id=record_id;
 when 'provider_verify' then
 desired=payload->>'status';
 if coalesce(desired,'') not in ('Verified','Rejected','Pending') then raise exception 'Invalid verification status'; end if;
 if desired='Verified' and nullif(trim(before_row->>'business_license'),'') is null and not exists(select 1 from public.provider_certifications where provider_id=record_id and is_verified and file_url is not null and (expiry_date is null or expiry_date>=(now() at time zone 'Asia/Kuala_Lumpur')::date)) then raise exception 'Review a business licence or verify a current credential before approval'; end if;
 update public.provider_profiles set verification_status=desired::public.provider_verification_status,verified_by_admin=aid,verified_at=case when desired='Verified' then now() else null end,rejection_reason=case when desired='Rejected' then note else null end where provider_id=record_id;
 perform private.admin_notify((before_row->>'user_id')::uuid,'Provider verification: '||desired,note);
 when 'category_save' then
 -- Serialize hierarchy edits so concurrent moves cannot create a cycle.
 perform pg_advisory_xact_lock(76129001);
 if length(trim(coalesce(payload->>'name',''))) not between 2 and 100 then raise exception 'Category name must contain 2–100 characters'; end if;
 if length(coalesce(payload->>'description',''))>500 then raise exception 'Description must be at most 500 characters'; end if;
 if coalesce(payload->>'color','#f97316') !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Invalid colour'; end if;
 if payload ? 'icon_url' and payload->>'icon_url' not like 'https://znxhiymvmluxmdaxzxkt.supabase.co/storage/v1/object/public/category-icons/%' then raise exception 'Category icons must use the category-icons bucket'; end if;
 if coalesce(payload->>'active','') not in ('true','false') then raise exception 'Invalid category status'; end if;
 parent=nullif(payload->>'parent_id','')::uuid;
 if parent is not null then
 if parent=record_id or exists(with recursive descendants as(select category_id from public.service_categories where parent_category_id=record_id union all select c.category_id from public.service_categories c join descendants d on c.parent_category_id=d.category_id) select 1 from descendants where category_id=parent) then raise exception 'A category cannot be its own ancestor'; end if;
 if not exists(select 1 from public.service_categories where category_id=parent and (is_active or (payload->>'active')::boolean=false)) then raise exception 'Select an existing active parent'; end if;
 end if;
 if (payload->>'active')::boolean=false and exists(select 1 from public.service_categories where parent_category_id=record_id and is_active) then raise exception 'Deactivate active subcategories first'; end if;
 if exists(select 1 from public.service_categories where lower(category_name)=lower(trim(payload->>'name')) and parent_category_id is not distinct from parent and category_id is distinct from record_id) then raise exception 'A category with this name already exists under that parent'; end if;
 if coalesce((payload->>'display_order')::integer,0) not between 0 and 9999 then raise exception 'Invalid display order'; end if;
 if record_id is null then
 insert into public.service_categories(category_name,parent_category_id,description,color_code,display_order,is_active,icon_url) values(trim(payload->>'name'),parent,payload->>'description',coalesce(payload->>'color','#f97316'),coalesce((payload->>'display_order')::integer,0),(payload->>'active')::boolean,payload->>'icon_url') returning category_id into record_id;
 else update public.service_categories set category_name=trim(payload->>'name'),parent_category_id=parent,description=payload->>'description',color_code=coalesce(payload->>'color','#f97316'),display_order=coalesce((payload->>'display_order')::integer,0),is_active=(payload->>'active')::boolean,icon_url=coalesce(payload->>'icon_url',icon_url) where category_id=record_id; end if;
 when 'category_delete' then
 perform pg_advisory_xact_lock(76129001);
 if exists(select 1 from public.services where category_id=record_id) or exists(select 1 from public.service_categories where parent_category_id=record_id) then raise exception 'This category is in use. Deactivate it instead of deleting history.'; end if;
 delete from public.service_categories where category_id=record_id;
 when 'booking_status' then
 desired=payload->>'status'; status_now=before_row->>'booking_status';
 if not coalesce(((status_now='Pending' and desired in ('Confirmed','Cancelled')) or (status_now='Confirmed' and desired in ('In-Progress','Cancelled')) or (status_now='In-Progress' and desired in ('Completed','Cancelled'))),false) then raise exception 'This booking transition is not allowed'; end if;
 if desired='Confirmed' and not exists(select 1 from public.payments where booking_id=record_id and payment_status='Success') then raise exception 'A successful payment is required before administrative confirmation'; end if;
 perform set_config('app.action_reason',note,true);
 update public.bookings set booking_status=desired::public.booking_status,accepted_at=case when desired='Confirmed' then now() else accepted_at end,started_at=case when desired='In-Progress' then now() else started_at end,completed_at=case when desired='Completed' then now() else completed_at end,cancelled_at=case when desired='Cancelled' then now() else cancelled_at end,cancellation_reason=case when desired='Cancelled' then note else cancellation_reason end where booking_id=record_id;
 select user_id into recipient from public.customer_profiles where customer_id=(before_row->>'customer_id')::uuid;
 perform private.admin_notify(recipient,'Booking '||desired,note,record_id);
 select user_id into recipient from public.provider_profiles where provider_id=(before_row->>'provider_id')::uuid;
 perform private.admin_notify(recipient,'Booking '||desired,note,record_id);
 when 'review_moderate' then
 if coalesce(payload->>'decision','') not in ('hide','dismiss') then raise exception 'Invalid moderation decision'; end if;
 update public.reviews set moderation_status=case when payload->>'decision'='hide' then 'hidden' else 'visible' end,is_flagged=false,moderation_reason=note,moderated_by_admin=aid,moderated_at=now() where review_id=record_id;
 when 'dispute_open' then
 insert into public.booking_disputes(booking_id,opened_by,subject,description) values(record_id,actor,trim(payload->>'subject'),note) returning dispute_id into bid;
 when 'dispute_resolve' then
 desired=payload->>'status';
 if before_row->>'status' not in ('Open','Under Review') or coalesce(desired,'') not in ('Under Review','Resolved','Dismissed') or desired=before_row->>'status' then raise exception 'Invalid dispute transition'; end if;
 update public.booking_disputes set status=desired,resolution=note,resolved_by=case when desired in ('Resolved','Dismissed') then aid else null end,resolved_at=case when desired in ('Resolved','Dismissed') then now() else null end,updated_at=now() where dispute_id=record_id;
 when 'refund_request' then
 if not is_super then raise exception 'Only a Super Admin can request a refund' using errcode='42501'; end if;
 if before_row->>'payment_status'<>'Success' then raise exception 'Only successful payments can be refunded'; end if;
 total=(payload->>'amount')::numeric;
 if total is null or total<=0 or total<>round(total,2) then raise exception 'Enter a positive amount with at most two decimal places'; end if;
 select coalesce(sum(amount),0) into refund_total from public.refund_requests where payment_id=record_id and status in ('Requested','Processing','Succeeded');
 if total+refund_total>(before_row->>'payment_amount')::numeric then raise exception 'Refund exceeds the remaining paid amount'; end if;
 insert into public.refund_requests(payment_id,amount,reason,requested_by) values(record_id,total,note,aid) returning refund_id into bid;
 end case;
 execute format('select to_jsonb(t) from public.%I t where %I=$1',target,pk) into after_row using record_id;
 if target='users' then before_row=before_row-'password_hash';after_row=after_row-'password_hash'; end if;
 insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values) values(actor,'admin',action_name,target,record_id,before_row,coalesce(after_row,'{}')||jsonb_build_object('reason',note,'created_record_id',bid));
 return jsonb_build_object('id',coalesce(bid,record_id),'message',case when action_name='refund_request' then 'Refund request recorded. Funds have not been refunded; gateway processing is still required.' else 'Changes saved.' end);
end $$;
create function public.admin_mutate(action_name text,record_id uuid default null,expected_version text default null,payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.admin_mutate(action_name,record_id,expected_version,payload)$$;

create function private.admin_analytics(date_from date,date_to date) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; start_at timestamptz; end_at timestamptz;
begin
 perform private.admin_actor();
 if date_from is null or date_to is null or date_to<date_from or date_to-date_from>366 then raise exception 'Choose a date range of at most 367 days'; end if;
 start_at=date_from::timestamp at time zone 'Asia/Kuala_Lumpur';end_at=(date_to+1)::timestamp at time zone 'Asia/Kuala_Lumpur';
 select jsonb_build_object(
 'from',date_from,'to',date_to,'timezone','Asia/Kuala_Lumpur',
 'users',(select count(*) from public.users),'new_users',(select count(*) from public.users where created_at>=start_at and created_at<end_at),
 'bookings',(select count(*) from public.bookings where created_at>=start_at and created_at<end_at),
 'active_bookings',(select count(*) from public.bookings where booking_status in ('Pending','Confirmed','In-Progress')),
 'pending_providers',(select count(*) from public.provider_profiles where verification_status='Pending'),
 'open_disputes',(select count(*) from public.booking_disputes where status in ('Open','Under Review')),
 'flagged_reviews',(select count(*) from public.reviews where is_flagged),
 'gross_collected',(select coalesce(sum(payment_amount),0) from public.payments where payment_status in ('Success','Refunded') and coalesce(payment_timestamp,created_at)>=start_at and coalesce(payment_timestamp,created_at)<end_at),
 'platform_fees',(select coalesce(sum(platform_fee),0) from public.provider_earnings where created_at>=start_at and created_at<end_at),
 'refunds_requested',(select coalesce(sum(amount),0) from public.refund_requests where created_at>=start_at and created_at<end_at and status in ('Requested','Processing')),
 'avg_rating',(select coalesce(round(avg(rating_score),2),0) from public.reviews where moderation_status='visible' and not is_flagged and created_at>=start_at and created_at<end_at),
 'daily',coalesce((select jsonb_agg(jsonb_build_object('date',d.day::date,'bookings',(select count(*) from public.bookings b where (b.created_at at time zone 'Asia/Kuala_Lumpur')::date=d.day::date),'users',(select count(*) from public.users u where (u.created_at at time zone 'Asia/Kuala_Lumpur')::date=d.day::date))) from generate_series(date_from::timestamp,date_to::timestamp,interval '1 day') d(day)),'[]'),
 'providers',coalesce((select jsonb_agg(to_jsonb(x)) from(select p.business_name,count(b.booking_id) as bookings,count(b.booking_id) filter(where b.booking_status='Completed') as completed,p.overall_rating from public.provider_profiles p left join public.bookings b on b.provider_id=p.provider_id and b.created_at>=start_at and b.created_at<end_at group by p.provider_id,p.business_name,p.overall_rating order by completed desc,p.business_name limit 20)x),'[]')
 ) into result;return result;
end $$;
create function public.admin_analytics(date_from date,date_to date) returns jsonb language sql security invoker set search_path='' as $$ select private.admin_analytics(date_from,date_to) $$;

revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.current_user_id(),private.is_admin(),private.accept_admin_invitation(),private.admin_list(text,text,text,integer),private.admin_detail(text,uuid),private.admin_document(uuid),private.admin_mutate(text,uuid,text,jsonb),private.admin_analytics(date,date) to authenticated;
grant usage on schema private to anon;
grant execute on function private.provider_is_visible(uuid),private.service_is_visible(uuid,uuid) to anon,authenticated;
revoke all on function public.admin_identity(),public.admin_list(text,text,text,integer),public.admin_detail(text,uuid),public.admin_document(uuid),public.admin_mutate(text,uuid,text,jsonb),public.admin_analytics(date,date) from public,anon;
grant execute on function public.admin_identity(),public.admin_list(text,text,text,integer),public.admin_detail(text,uuid),public.admin_document(uuid),public.admin_mutate(text,uuid,text,jsonb),public.admin_analytics(date,date) to authenticated;
revoke all on public.booking_disputes,public.refund_requests from anon,authenticated;
notify pgrst,'reload schema';
