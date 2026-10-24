-- Read/support identity is deliberately separate from current_user_id/customer_id.
-- Those active-only helpers continue to protect every existing mutation and AI call.
create function private.customer_viewer_user_id() returns uuid
language sql stable security definer set search_path='' as $$
 select u.user_id from public.users u join auth.users a on a.id=u.auth_user_id
 join public.customer_profiles c using(user_id)
 where a.id=auth.uid() and u.role='customer' and a.email_confirmed_at is not null
$$;
revoke all on function private.customer_viewer_user_id() from public,anon;
grant execute on function private.customer_viewer_user_id() to authenticated;

create function private.customer_viewer_id() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;
begin
 select customer_id into cid from public.customer_profiles where user_id=private.customer_viewer_user_id();
 if cid is null then raise exception 'A verified customer account is required' using errcode='42501'; end if;
 return cid;
end $$;
revoke all on function private.customer_viewer_id() from public,anon,authenticated;

create or replace function private.account_identity() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 select jsonb_build_object('user_id',u.user_id,'role',u.role,'full_name',u.full_name,
 'customer_id',c.customer_id,'provider_id',p.provider_id,'is_active',u.is_active)
 into result from public.users u left join public.customer_profiles c using(user_id)
 left join public.provider_profiles p using(user_id)
 where u.user_id=private.current_user_id() or u.user_id=private.customer_viewer_user_id();
 if result is null then raise exception 'An active application account is required' using errcode='42501'; end if;
 return result;
end $$;

-- Split only the tables needed to display the customer's existing pages.
-- INSERT/UPDATE/DELETE retain the exact active-account requirement.
do $$ declare t text; begin
 foreach t in array array['customer_profiles','service_categories','notifications'] loop
  execute format('drop policy active_account_required on public.%I',t);
  execute format('create policy account_read_required on public.%I as restrictive for select to authenticated using ((select private.current_user_id()) is not null or (select private.customer_viewer_user_id()) is not null)',t);
  execute format('create policy active_insert_required on public.%I as restrictive for insert to authenticated with check ((select private.current_user_id()) is not null)',t);
  execute format('create policy active_update_required on public.%I as restrictive for update to authenticated using ((select private.current_user_id()) is not null) with check ((select private.current_user_id()) is not null)',t);
  execute format('create policy active_delete_required on public.%I as restrictive for delete to authenticated using ((select private.current_user_id()) is not null)',t);
 end loop;
end $$;
create policy customer_profile_viewer on public.customer_profiles for select to authenticated
 using(user_id=(select private.customer_viewer_user_id()));
create policy customer_notification_viewer on public.notifications for select to authenticated
 using(user_id=(select private.customer_viewer_user_id()));

-- Explicitly reviewed read-only and support-only functions; ownership and limits stay intact.
CREATE OR REPLACE FUNCTION private.customer_booking_detail(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin return private.customer_booking_json(p_booking_id,private.customer_viewer_id()); end $function$;

CREATE OR REPLACE FUNCTION private.customer_bookings(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.customer_viewer_id();
begin
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000 then raise exception 'Invalid booking page'; end if;
 return coalesce((select jsonb_agg(private.customer_booking_json(b.booking_id,cid)) from
 (select booking_id from public.bookings where customer_id=cid order by created_at desc,booking_id limit p_limit offset p_offset) b),'[]');
end $function$;

CREATE OR REPLACE FUNCTION private.customer_prepare_support(p_request_id uuid, p_booking_id uuid, p_subject text, p_description text, p_photo_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.customer_viewer_id(); uid uuid:=private.customer_viewer_user_id(); draft private.customer_support_drafts%rowtype;
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
end $function$;

CREATE OR REPLACE FUNCTION private.customer_provider_directory()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not exists(select 1 from public.users where user_id=private.customer_viewer_user_id() and role='customer') then
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
end $function$;

CREATE OR REPLACE FUNCTION private.customer_submit_support(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.customer_viewer_id(); uid uuid:=private.customer_viewer_user_id(); draft private.customer_support_drafts%rowtype;
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
end $function$;

CREATE OR REPLACE FUNCTION private.customer_support_requests(p_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid:=private.customer_viewer_user_id();
begin
 perform private.customer_viewer_id();
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset<0 then raise exception 'Invalid page.' using errcode='22023'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r)) from (
  select dispute_id,booking_id,subject,description,status,resolution,created_at,updated_at,attachment_paths
  from public.booking_disputes where opened_by=uid and (p_id is null or dispute_id=p_id)
  order by created_at desc,dispute_id desc limit p_limit offset p_offset) r),'[]');
end $function$;

CREATE OR REPLACE FUNCTION private.customer_unread_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid:=private.customer_viewer_id(); uid uuid; notices bigint; bookings bigint; chats bigint;
begin
 select user_id into uid from public.customer_profiles where customer_id=cid;
 select count(*),count(*) filter(where booking_id is not null) into notices,bookings from public.notifications
 where user_id=uid and not is_read and dismissed_at is null;
 select count(*) into chats from public.chat_members m join public.chat_messages x using(conversation_id)
 where m.user_id=uid and not m.hidden and not m.blocked and x.sender_id<>uid and x.message_id>greatest(m.read_through,m.cleared_through);
 return jsonb_build_object('notifications',notices,'bookings',bookings,'chats',chats);
end $function$;

CREATE OR REPLACE FUNCTION private.support_photo_access(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare draft private.customer_support_drafts%rowtype;
begin
 if not p_write and private.is_admin() then
  return exists(select 1 from public.booking_disputes where p_name=any(attachment_paths));
 end if;
 perform private.customer_viewer_id();
 select d.* into draft from private.customer_support_drafts d
 where d.auth_id=auth.uid() and d.owner_id=private.customer_viewer_user_id()
 and p_name in (select d.auth_id::text||'/'||d.request_id::text||'/'||n from generate_series(0,d.photo_count-1) n);
 if not found then return false; end if;
 if not p_write then return true; end if;
 return draft.created_at>now()-interval '24 hours'
 and not exists(select 1 from public.booking_disputes where opened_by=draft.owner_id and request_id=draft.request_id);
exception when insufficient_privilege then return false;
end $function$;
