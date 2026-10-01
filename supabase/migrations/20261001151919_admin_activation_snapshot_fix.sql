-- First activation inserts the profile in this command. A STABLE authorizer in
-- the final query can use a snapshot without those rows and roll activation back.
-- Reuse the identity already authorized in the branches below instead.
create or replace function private.accept_admin_invitation() returns jsonb
language plpgsql volatile security definer set search_path='' as $$
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
 -- Do not call the STABLE admin_actor again after writing the first profile.
 return (select jsonb_build_object('user_id',u.user_id,'email',u.email,'full_name',u.full_name,'role_level',a.admin_role_level,
 'mfa_verified',coalesce(auth.jwt()->>'aal','')='aal2') from public.users u join public.admin_profiles a using(user_id)
 where u.user_id=uid and u.auth_user_id=identity.id and u.role='admin' and u.is_active is true);
end $$;
