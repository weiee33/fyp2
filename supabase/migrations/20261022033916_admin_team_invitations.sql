-- Invitations remain private; only an active MFA-verified Super Admin can manage them.
alter table private.admin_invitations
 add column invitation_id uuid not null default gen_random_uuid() unique,
 add column invited_by uuid references public.users(user_id),
 add column expires_at timestamptz;
alter table private.admin_invitations alter column expires_at set default (now()+interval '7 days');
create index admin_invitations_invited_by_idx on private.admin_invitations(invited_by);
revoke all on private.admin_invitations from public,anon,authenticated;

create function private.admin_team_actor() returns uuid
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=private.admin_actor();
begin
 if not exists(select 1 from public.admin_profiles where user_id=actor and admin_role_level='super_admin') then
  raise exception 'Only a Super Admin can manage administrator invitations.' using errcode='42501';
 end if;
 return actor;
end $$;

create function private.admin_team(p_search text default '',p_page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; total bigint; page_no integer:=greatest(1,coalesce(p_page,1));
begin
 perform private.admin_team_actor();
 if length(coalesce(p_search,''))>100 or page_no>10000 then raise exception 'Invalid search or page.' using errcode='22023'; end if;
 select count(*) into total from private.admin_invitations i where strpos(i.email,lower(trim(coalesce(p_search,''))))>0;
 select coalesce(jsonb_agg(row_data order by created_at desc,email),'[]') into result from (
  select i.created_at,i.email,jsonb_build_object(
   'invitation_id',i.invitation_id,'email',i.email,'role_level',i.role_level,
   'created_at',i.created_at,'expires_at',i.expires_at,'accepted_at',i.accepted_at,
   'invited_by_name',u.full_name,'version',md5(to_jsonb(i)::text),
   'status',case when i.accepted_by is not null then 'Accepted' when i.revoked_at is not null then 'Revoked'
    when i.expires_at<=now() then 'Expired' else 'Pending' end) as row_data
  from private.admin_invitations i left join public.users u on u.user_id=i.invited_by
  where strpos(i.email,lower(trim(coalesce(p_search,''))))>0
  order by i.created_at desc,i.email limit 20 offset (page_no-1)*20
 ) rows;
 return jsonb_build_object('items',result,'total',total,'page',page_no,'page_size',20);
end $$;

create function private.admin_invitation_manage(p_action text,p_email text,p_role text default 'staff',p_version text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=private.admin_team_actor(); address text:=lower(trim(p_email));
 invitation private.admin_invitations%rowtype; before_row jsonb; after_row jsonb;
begin
 if p_action is null or p_action not in ('create','renew','revoke') then raise exception 'Invalid invitation action.' using errcode='22023'; end if;
 if address is null or length(address)>254 or address !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9]([a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$' then
  raise exception 'Enter a valid email address.' using errcode='22023';
 end if;
 if p_role is null or p_role not in ('staff','super_admin') then raise exception 'Choose a valid admin role.' using errcode='22023'; end if;
 -- Serialize invitation changes for the same address, including its first insert.
 perform pg_advisory_xact_lock(hashtextextended('admin-invitation:'||address,0));
 select * into invitation from private.admin_invitations where email=address for update;
 if found then
  before_row:=to_jsonb(invitation);
  if invitation.accepted_by is not null then raise exception 'This invitation has already been accepted.' using errcode='22023'; end if;
  if p_action='create' then raise exception 'This email already has an invitation. Use its existing invitation.' using errcode='22023'; end if;
  if p_version is null or p_version<>md5(before_row::text) then raise exception 'This invitation changed. Refresh the page and try again.' using errcode='40001'; end if;
 else
  if p_action<>'create' then raise exception 'Invitation not found.' using errcode='22023'; end if;
 end if;
 if p_action<>'revoke' and exists(select 1 from public.users where lower(email)=address) then
  raise exception 'This email already has an application account. Use a separate admin email.' using errcode='22023';
 end if;
 if p_action='create' then
  insert into private.admin_invitations(email,role_level,invited_by)
  values(address,p_role::public.admin_role_level,actor) returning * into invitation;
 elsif p_action='renew' then
  update private.admin_invitations set revoked_at=null,expires_at=now()+interval '7 days',invited_by=actor,
   created_at=now(),role_level=p_role::public.admin_role_level where email=address returning * into invitation;
 else
  if invitation.revoked_at is not null then raise exception 'This invitation is already revoked.' using errcode='22023'; end if;
  update private.admin_invitations set revoked_at=now() where email=address returning * into invitation;
 end if;
 after_row:=to_jsonb(invitation);
 insert into public.audit_logs(actor_id,actor_role,action,target_table,target_id,old_values,new_values)
 values(actor,'admin','admin_invitation_'||p_action,'admin_invitations',invitation.invitation_id,before_row,after_row);
 return jsonb_build_object('email',address,'message',case p_action when 'revoke' then 'Invitation revoked. It can no longer activate an account.'
  else 'Invitation saved. Share the activation link with this person; no invitation email has been sent.' end);
end $$;

create function public.admin_team(p_search text default '',p_page integer default 1) returns jsonb
language sql security invoker set search_path='' as $$select private.admin_team(p_search,p_page)$$;
create function public.admin_invitation_manage(p_action text,p_email text,p_role text default 'staff',p_version text default null) returns jsonb
language sql security invoker set search_path='' as $$select private.admin_invitation_manage(p_action,p_email,p_role,p_version)$$;
revoke all on function private.admin_team_actor(),private.admin_team(text,integer),private.admin_invitation_manage(text,text,text,text),public.admin_team(text,integer),public.admin_invitation_manage(text,text,text,text) from public,anon;
grant execute on function private.admin_team_actor(),private.admin_team(text,integer),private.admin_invitation_manage(text,text,text,text),public.admin_team(text,integer),public.admin_invitation_manage(text,text,text,text) to authenticated;

-- Preserve existing account isolation and first-activation behavior, adding expiry.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.accept_admin_invitation()'::regprocedure);
 if strpos(body,'and revoked_at is null for update')=0 then raise exception 'Unexpected invitation activation definition'; end if;
 body:=replace(body,'and revoked_at is null for update','and revoked_at is null and (expires_at is null or expires_at>now()) for update');
 execute body;
 body:=pg_get_functiondef('public.admin_registration_check(text)'::regprocedure);
 if strpos(body,'i.accepted_by is null')=0 then raise exception 'Unexpected registration preflight definition'; end if;
 body:=replace(body,'i.accepted_by is null','i.accepted_by is null and (i.expires_at is null or i.expires_at>now())');
 execute body;
end $$;
