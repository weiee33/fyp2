-- Customer support uses the existing, MFA-protected administrator inbox.
alter table public.booking_disputes alter column booking_id drop not null;
alter table public.booking_disputes add column request_id uuid;
alter table public.booking_disputes add column attachment_paths text[] not null default '{}'
  check (cardinality(attachment_paths) <= 3);
create unique index booking_disputes_request_owner on public.booking_disputes(opened_by,request_id);

-- An immutable upload reservation binds each object to one submitted payload.
-- Failed uploads can be retried without duplicate requests or overwritten evidence.
create table private.customer_support_drafts (
  request_id uuid primary key,
  owner_id uuid not null references public.users(user_id),
  auth_id uuid not null references auth.users(id),
  booking_id uuid references public.bookings(booking_id),
  subject text not null check (length(btrim(subject)) between 3 and 150),
  description text not null check (length(btrim(description)) between 10 and 4000),
  photo_count integer not null check (photo_count between 0 and 3),
  created_at timestamptz not null default now()
);
alter table private.customer_support_drafts enable row level security;
revoke all on private.customer_support_drafts from public, anon, authenticated;
create index customer_support_drafts_owner_created on private.customer_support_drafts(owner_id,created_at);
create index customer_support_drafts_auth on private.customer_support_drafts(auth_id);
create index customer_support_drafts_booking on private.customer_support_drafts(booking_id);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('support-photos','support-photos',false,5242880,array['image/jpeg','image/png','image/webp']);

create function private.customer_prepare_support(p_request_id uuid,p_booking_id uuid,
 p_subject text,p_description text,p_photo_count integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid:=private.current_user_id(); draft private.customer_support_drafts%rowtype;
begin
 perform 1 from public.users where user_id=uid for update;
 if p_request_id is null or p_subject is null or p_description is null or p_photo_count is null
 or length(btrim(p_subject)) not between 3 and 150 or length(btrim(p_description)) not between 10 and 4000
 or p_photo_count not between 0 and 3 then raise exception 'Check the subject, description and photo count.' using errcode='22023'; end if;
 select * into draft from private.customer_support_drafts where request_id=p_request_id;
 if found then
  if (draft.owner_id,draft.booking_id,draft.subject,draft.description,draft.photo_count)
   is distinct from (uid,p_booking_id,btrim(p_subject),btrim(p_description),p_photo_count)
   then raise exception 'This request cannot be changed after sending starts.' using errcode='22023'; end if;
  return jsonb_build_object('dispute_id',(select dispute_id from public.booking_disputes where opened_by=uid and request_id=p_request_id));
 end if;
 if p_booking_id is not null then
  perform 1 from public.bookings where booking_id=p_booking_id and customer_id=cid for update;
  if not found then raise exception 'Booking not found.' using errcode='42501'; end if;
  if exists(select 1 from public.booking_disputes where booking_id=p_booking_id and status in ('Open','Under Review'))
   then raise exception 'This booking already has an open support request.' using errcode='22023'; end if;
 end if;
 if (select count(*) from private.customer_support_drafts where owner_id=uid and created_at>now()-interval '24 hours')>=10
  then raise exception 'You have reached the daily support request limit. Please try again later.' using errcode='22023'; end if;
 insert into private.customer_support_drafts(request_id,owner_id,auth_id,booking_id,subject,description,photo_count)
 values(p_request_id,uid,auth.uid(),p_booking_id,btrim(p_subject),btrim(p_description),p_photo_count);
 return jsonb_build_object('dispute_id',null);
end $$;

create function private.support_photo_access(p_name text,p_write boolean) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare draft private.customer_support_drafts%rowtype;
begin
 if not p_write and private.is_admin() then
  return exists(select 1 from public.booking_disputes where p_name=any(attachment_paths));
 end if;
 perform private.customer_id();
 select d.* into draft from private.customer_support_drafts d
 where d.auth_id=auth.uid() and d.owner_id=private.current_user_id()
 and p_name in (select d.auth_id::text||'/'||d.request_id::text||'/'||n from generate_series(0,d.photo_count-1) n);
 if not found then return false; end if;
 if not p_write then return true; end if;
 return draft.created_at>now()-interval '24 hours'
 and not exists(select 1 from public.booking_disputes where opened_by=draft.owner_id and request_id=draft.request_id);
exception when insufficient_privilege then return false;
end $$;
revoke all on function private.support_photo_access(text,boolean) from public,anon;
grant execute on function private.support_photo_access(text,boolean) to authenticated;
create policy support_photos_insert on storage.objects for insert to authenticated
 with check(bucket_id='support-photos' and private.support_photo_access(name,true));
create policy support_photos_read on storage.objects for select to authenticated
 using(bucket_id='support-photos' and private.support_photo_access(name,false));
-- No client UPDATE or DELETE: submitted evidence cannot be replaced or removed.

create function private.customer_submit_support(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid:=private.current_user_id(); draft private.customer_support_drafts%rowtype;
 did uuid; paths text[]; actual integer;
begin
 select * into draft from private.customer_support_drafts where request_id=p_request_id and owner_id=uid for update;
 if not found then raise exception 'Support request not found.' using errcode='42501'; end if;
 select dispute_id into did from public.booking_disputes where opened_by=uid and request_id=p_request_id;
 if found then return jsonb_build_object('dispute_id',did); end if;
 if draft.created_at<=now()-interval '24 hours' then raise exception 'This draft has expired. Start a new request.' using errcode='22023'; end if;
 if draft.booking_id is not null then
  perform 1 from public.bookings where booking_id=draft.booking_id and customer_id=cid for update;
  if not found then raise exception 'Booking not found.' using errcode='42501'; end if;
  if exists(select 1 from public.booking_disputes where booking_id=draft.booking_id and status in ('Open','Under Review'))
   then raise exception 'This booking already has an open support request.' using errcode='22023'; end if;
 end if;
 select coalesce(array_agg(draft.auth_id::text||'/'||p_request_id::text||'/'||n order by n),'{}')
 into paths from generate_series(0,draft.photo_count-1) n;
 select count(*) into actual from storage.objects where bucket_id='support-photos' and name=any(paths);
 if actual<>draft.photo_count then raise exception 'Finish uploading every photo before sending.' using errcode='22023'; end if;
 insert into public.booking_disputes(booking_id,opened_by,subject,description,request_id,attachment_paths)
 values(draft.booking_id,uid,draft.subject,draft.description,p_request_id,paths) returning dispute_id into did;
 return jsonb_build_object('dispute_id',did);
end $$;

create function private.customer_support_requests(p_id uuid default null,p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=private.current_user_id();
begin
 perform private.customer_id();
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset<0 then raise exception 'Invalid page.' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r)) from (
  select dispute_id,booking_id,subject,description,status,resolution,created_at,updated_at,attachment_paths
  from public.booking_disputes where opened_by=uid and (p_id is null or dispute_id=p_id)
  order by created_at desc,dispute_id desc limit p_limit offset p_offset) r),'[]');
end $$;

create function public.customer_prepare_support(p_request_id uuid,p_booking_id uuid,p_subject text,p_description text,p_photo_count integer)
returns jsonb language sql security invoker set search_path='' as $$select private.customer_prepare_support(p_request_id,p_booking_id,p_subject,p_description,p_photo_count)$$;
create function public.customer_submit_support(p_request_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.customer_submit_support(p_request_id)$$;
create function public.customer_support_requests(p_id uuid default null,p_limit integer default 30,p_offset integer default 0) returns jsonb
language sql security invoker set search_path='' as $$select private.customer_support_requests(p_id,p_limit,p_offset)$$;
do $$ declare f regprocedure; begin
 for f in select oid::regprocedure from pg_proc where pronamespace in ('private'::regnamespace,'public'::regnamespace)
 and proname in ('customer_prepare_support','customer_submit_support','customer_support_requests') loop
 execute format('revoke all on function %s from public,anon',f);
 execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
