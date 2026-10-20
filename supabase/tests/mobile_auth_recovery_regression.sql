-- Run as owner inside BEGIN/ROLLBACK; synthetic fixtures, no emails are sent.
create temporary table mobile_auth_results (test text primary key) on commit drop;
create function pg_temp.check_mobile(test text, ok boolean) returns void
language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'FAIL: %', test; end if;
  insert into mobile_auth_results values(test);
end $$;
do $$
declare
  cid uuid:=gen_random_uuid(); pid uuid:=gen_random_uuid();
  cemail text:='__mobile_'||cid||'@example.invalid';
  pemail text:='__mobile_'||pid||'@example.invalid';
  ip text:=repeat('d',64); result jsonb;
begin
  -- Random IDs ensure fixtures never collide with a real account.
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,
    email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (cid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
      cemail,'',now(),'{"provider":"email"}','{"role":"customer","full_name":"Mobile test customer"}',now(),now()),
    (pid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
      pemail,'',now(),'{"provider":"email"}','{"role":"provider","full_name":"Mobile test provider"}',now(),now());
  perform pg_temp.check_mobile('signup creates customer profile',
    exists(select 1 from public.users u join public.customer_profiles c using(user_id)
      where u.auth_user_id=cid and u.role='customer'));
  perform pg_temp.check_mobile('signup creates provider profile',
    exists(select 1 from public.users u join public.provider_profiles p using(user_id)
      where u.auth_user_id=pid and u.role='provider'));
  perform pg_temp.check_mobile('customer recovery eligible',
    (public.customer_recovery_check(cemail,ip)->>'registered')::boolean);
  perform pg_temp.check_mobile('provider recovery eligible, case insensitive',
    (public.customer_recovery_check(upper(pemail),ip)->>'registered')::boolean);

  update auth.users set raw_user_meta_data='{"role":"customer"}' where id=pid;
  perform set_config('request.jwt.claim.sub',pid::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pid,'role','authenticated','aal','aal1')::text,true);
  perform pg_temp.check_mobile('edited metadata cannot change canonical provider',
    public.account_identity()->>'role'='provider');

  update auth.users set email_confirmed_at=null where id=pid;
  perform pg_temp.check_mobile('unverified provider denied',
    not (public.customer_recovery_check(pemail,ip)->>'registered')::boolean);
  update auth.users set email_confirmed_at=now(), banned_until=now()+interval '1 hour' where id=pid;
  perform pg_temp.check_mobile('banned provider denied',
    not (public.customer_recovery_check(pemail,ip)->>'registered')::boolean);
  update auth.users set banned_until=null where id=pid;
  update public.users set is_active=false where auth_user_id=pid;
  perform pg_temp.check_mobile('inactive provider denied',
    not (public.customer_recovery_check(pemail,ip)->>'registered')::boolean);
  update public.users set is_active=true where auth_user_id=pid;
  delete from public.provider_profiles where user_id=(select user_id from public.users where auth_user_id=pid);
  perform pg_temp.check_mobile('missing provider profile denied',
    not (public.customer_recovery_check(pemail,ip)->>'registered')::boolean);
  perform pg_temp.check_mobile('email rate limit still enforced',
    not (public.customer_recovery_check(pemail,ip)->>'allowed')::boolean);

  update public.users set role='admin' where auth_user_id=cid;
  perform pg_temp.check_mobile('admin recovery denied despite customer profile',
    not (public.customer_recovery_check(cemail,ip)->>'registered')::boolean);
  perform pg_temp.check_mobile('anonymous role cannot query recovery identity',
    not has_function_privilege('anon','public.customer_recovery_check(text,text)','EXECUTE'));
  perform pg_temp.check_mobile('authenticated role cannot query recovery identity',
    not has_function_privilege('authenticated','public.customer_recovery_check(text,text)','EXECUTE'));
  perform pg_temp.check_mobile('service role can query recovery identity',
    has_function_privilege('service_role','public.customer_recovery_check(text,text)','EXECUTE'));
end $$;
select test from mobile_auth_results order by test;
