-- Older installations already have the provider app's ticket table.
create table if not exists public.provider_support_tickets (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references auth.users(id),
  subject text not null,
  description text not null,
  status text not null default 'Pending',
  admin_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.provider_support_tickets
  add column if not exists booking_id uuid references public.bookings(booking_id);
create index if not exists provider_support_provider_created_idx
  on public.provider_support_tickets(provider_id, created_at desc);
create index if not exists provider_support_booking_idx
  on public.provider_support_tickets(booking_id) where booking_id is not null;

alter table public.provider_support_tickets enable row level security;
revoke all on public.provider_support_tickets from public, anon, authenticated;
grant select, insert(provider_id, booking_id, subject, description, status)
  on public.provider_support_tickets to authenticated;
drop policy if exists "Providers can view own tickets" on public.provider_support_tickets;
drop policy if exists "Providers can insert own tickets" on public.provider_support_tickets;
create policy provider_read_ticket on public.provider_support_tickets for select to authenticated
  using (provider_id = (select auth.uid()));

create function private.can_open_provider_ticket(booking uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.provider_profiles p join public.users u using(user_id)
    where u.auth_user_id=auth.uid() and u.role='provider' and u.is_active
      and (booking is null or exists (select 1 from public.bookings b
           where b.booking_id=booking and b.provider_id=p.provider_id))
  )
$$;
revoke all on function private.can_open_provider_ticket(uuid) from public, anon;
grant execute on function private.can_open_provider_ticket(uuid) to authenticated;
create policy provider_open_ticket on public.provider_support_tickets for insert to authenticated
  with check (provider_id=(select auth.uid()) and status='Pending'
    and private.can_open_provider_ticket(booking_id));

create function private.provider_support_photo_access(path text, writing boolean)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (select 1 from public.provider_support_tickets t
     where t.id::text=split_part(path,'/',2) and t.provider_id::text=split_part(path,'/',1)
       and path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-2]$'
       and ((t.provider_id=auth.uid() and (not writing or (t.status='Pending'
          and private.can_open_provider_ticket(t.booking_id)))) or (not writing and private.is_admin())))
$$;
revoke all on function private.provider_support_photo_access(text,boolean) from public,anon;
grant execute on function private.provider_support_photo_access(text,boolean) to authenticated;
create policy provider_ticket_photo_insert on storage.objects for insert to authenticated
  with check (bucket_id='support-photos' and private.provider_support_photo_access(name,true));
create policy provider_ticket_photo_read on storage.objects for select to authenticated
  using (bucket_id='support-photos' and private.provider_support_photo_access(name,false));

create function private.admin_booking_status(raw_status text, payment text, deadline timestamptz, scheduled timestamptz)
returns text language sql stable set search_path='' as $$
  select case when payment='Refunded' then 'Refunded'
              when raw_status in ('Confirmed','Pending') and payment is distinct from 'Success'
                   and (deadline <= now() or scheduled <= now()) then 'Expired'
              else raw_status end
$$;

create view private.admin_booking_records as
  select b.booking_id, b.created_at, to_jsonb(b) || jsonb_build_object(
    'version',md5(to_jsonb(b)::text),'customer_name',u.full_name,'provider_name',p.business_name,
    'service_name',s.service_name,'payment_status',pay.payment_status,
    'status',private.admin_booking_status(b.booking_status::text,pay.payment_status::text,coalesce(b.reservation_expires_at,b.accepted_at + interval '30 minutes'),b.scheduled_datetime)
  ) as item
  from public.bookings b join public.customer_profiles c using(customer_id)
  join public.users u on u.user_id=c.user_id join public.provider_profiles p using(provider_id)
  join public.services s using(service_id) left join public.payments pay using(booking_id);

create view private.admin_support_records as
  select d.dispute_id, d.created_at, to_jsonb(d) || jsonb_build_object(
    'version',md5(to_jsonb(d)::text),'opened_by_name',u.full_name,
    'role',initcap(u.role::text),'source','dispute') as item
  from public.booking_disputes d join public.users u on u.user_id=d.opened_by
  union all
  select t.id, t.created_at, jsonb_build_object(
    'dispute_id',t.id,'subject',t.subject,'description',t.description,'booking_id',t.booking_id,
    'opened_by_name',coalesce(u.full_name,'Provider'),'role','Provider','source','provider',
    'status',case when t.status='Pending' then 'Open' else t.status end,
    'resolution',t.admin_reply,'created_at',t.created_at,'updated_at',t.updated_at,
    'resolved_at',case when t.status in ('Resolved','Dismissed') then t.updated_at end,
    'version',md5(to_jsonb(t)::text)) as item
  from public.provider_support_tickets t left join public.users u on u.auth_user_id=t.provider_id;

revoke all on private.admin_booking_records, private.admin_support_records from public,anon,authenticated;

alter function private.admin_list(text,text,text,integer) rename to admin_list_before_support;
revoke all on function private.admin_list_before_support(text,text,text,integer) from public,anon,authenticated;
create function private.admin_list(resource text,search text,status_filter text,page_number integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare source regclass; result jsonb;
begin
  if resource not in ('bookings','disputes') then
    return private.admin_list_before_support(resource,search,status_filter,page_number);
  end if;
  perform private.admin_actor();
  if page_number is null or page_number not between 1 and 100000 then raise exception 'Invalid page'; end if;
  if length(search)>100 then raise exception 'Search must be at most 100 characters'; end if;
  source:=case resource when 'bookings' then 'private.admin_booking_records'::regclass
                        else 'private.admin_support_records'::regclass end;
  execute format($query$
    with filtered as (
      select item,created_at from %s
      where ($1='' or position(lower($1) in lower(item::text))>0)
        and ($2='' or item->>'status'=$2)
    ), page as (
      select * from filtered order by created_at desc,item::text limit 20 offset (($3-1)*20)
    )
    select jsonb_build_object('total',(select count(*) from filtered),'page',$3,'page_size',20,
      'items',coalesce((select jsonb_agg(item order by created_at desc,item::text) from page),'[]'))
  $query$,source) into result using coalesce(search,''),coalesce(status_filter,''),page_number;
  return result;
end $$;
revoke all on function private.admin_list(text,text,text,integer) from public,anon;
grant execute on function private.admin_list(text,text,text,integer) to authenticated;

create function private.admin_operations_detail(resource text,record_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.admin_actor();
  if resource='provider_support' then
    select r.item || jsonb_build_object('attachment_paths',array(
      select o.name from storage.objects o where o.bucket_id='support-photos' and
        o.name in (select t.provider_id::text||'/'||t.id::text||'/'||n from generate_series(0,2) n)
      order by o.name)) into result
    from private.admin_support_records r join public.provider_support_tickets t on t.id=r.dispute_id
    where r.dispute_id=record_id and r.item->>'source'='provider';
    if result is null then raise exception 'Support request not found' using errcode='P0002'; end if;
  elsif resource='bookings' then
    select private.admin_detail(resource,record_id) || jsonb_build_object('status',r.item->>'status')
      into result from private.admin_booking_records r where r.booking_id=record_id;
    if result is null then raise exception 'Booking not found' using errcode='P0002'; end if;
  elsif resource='disputes' then
    select private.admin_detail(resource,record_id) || r.item into result
    from private.admin_support_records r where r.dispute_id=record_id and r.item->>'source'='dispute';
    if result is null then raise exception 'Support request not found' using errcode='P0002'; end if;
  else
    raise exception 'Unknown resource';
  end if;
  return result;
end $$;
create function public.admin_operations_detail(resource text,record_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select private.admin_operations_detail(resource,record_id)
$$;

create function private.admin_reply_provider_ticket(record_id uuid,expected_version text,payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.admin_actor(); ticket public.provider_support_tickets%rowtype;
  decision text:=payload->>'status'; note text:=trim(payload->>'reason');
begin
  select * into strict ticket from public.provider_support_tickets where id=record_id for update;
  if expected_version is distinct from md5(to_jsonb(ticket)::text) then
    raise exception 'This record changed. Reload it before trying again.' using errcode='40001';
  end if;
  if decision is null or decision not in ('Under Review','Resolved','Dismissed')
      or ticket.status not in ('Pending','Open','Under Review') or ticket.status=decision then
    raise exception 'Invalid support decision';
  end if;
  if note is null or length(note) not between 10 and 1000 then raise exception 'Provide a response between 10 and 1000 characters'; end if;
  update public.provider_support_tickets set status=decision,admin_reply=note,updated_at=now() where id=record_id;
  insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values)
    values(actor,'admin','provider_support_reply','provider_support_tickets',record_id,
           jsonb_build_object('status',ticket.status,'admin_reply',ticket.admin_reply),
           jsonb_build_object('status',decision,'admin_reply',note));
  return jsonb_build_object('id',record_id,'message','Support response saved.');
end $$;
create function public.admin_reply_provider_ticket(record_id uuid,expected_version text,payload jsonb)
returns jsonb language sql security invoker set search_path='' as $$
  select private.admin_reply_provider_ticket(record_id,expected_version,payload)
$$;
revoke all on function private.admin_operations_detail(text,uuid),public.admin_operations_detail(text,uuid),
  private.admin_reply_provider_ticket(uuid,text,jsonb),public.admin_reply_provider_ticket(uuid,text,jsonb) from public,anon;
grant execute on function private.admin_operations_detail(text,uuid),public.admin_operations_detail(text,uuid),
  private.admin_reply_provider_ticket(uuid,text,jsonb),public.admin_reply_provider_ticket(uuid,text,jsonb) to authenticated;
