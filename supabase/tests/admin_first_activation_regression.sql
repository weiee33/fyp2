-- Run ALONE in a fresh connection: BEGIN; <this file>; ROLLBACK;
-- The first admin_identity call must not be wrapped in another function, and
-- no admin RPC may run before it. Warming the functions in the larger suite
-- concealed the original first-activation failure. All fixtures roll back.
insert into private.admin_invitations(email,role_level)
values('__first_activation_regression@example.invalid','super_admin');
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(gen_random_uuid(),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 '__first_activation_regression@example.invalid','',now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated','aal','aal1')::text,true),
 set_config('request.jwt.claim.sub',id::text,true)
from auth.users where email='__first_activation_regression@example.invalid';
set local role authenticated;

-- This exact top-level first call failed with SQLSTATE 42501 before the fix.
select public.admin_identity() as first_invitation_activation;
do $$ declare identity jsonb; begin
 identity := public.admin_identity();
 if identity->>'role_level' is distinct from 'super_admin'
 or identity->>'email' is distinct from '__first_activation_regression@example.invalid'
 or (identity->>'mfa_verified')::boolean is distinct from false then
  raise exception 'First activation or repeated activation returned the wrong identity';
 end if;
 begin
  perform public.admin_list('users');
  raise exception 'First activation bypassed MFA';
 exception when insufficient_privilege then
  if position('authenticator' in sqlerrm)=0 then raise; end if;
 end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.users u join public.admin_profiles a using(user_id)
 join auth.users identity on identity.id=u.auth_user_id
 join private.admin_invitations i on i.accepted_by=identity.id
 where identity.email='__first_activation_regression@example.invalid'
 and u.email_verified and u.is_active and u.role='admin'
 and a.admin_role_level='super_admin' and a.two_factor_enabled and i.accepted_at is not null) <> 1 then
  raise exception 'Activation did not create exactly one linked, verified administrator';
 end if;
 if exists(select 1 from public.users u join public.customer_profiles c using(user_id)
 where u.auth_user_id=auth.uid()) or exists(select 1 from public.users u join public.provider_profiles p using(user_id)
 where u.auth_user_id=auth.uid()) then
  raise exception 'Administrator activation created a mobile profile';
 end if;
end $$;
select jsonb_build_object('passed',5,'first_call','activated','repeat_call','idempotent',
 'aal1_data_access','denied','profile_linkage','valid','mobile_profiles','absent') as first_activation_result;
