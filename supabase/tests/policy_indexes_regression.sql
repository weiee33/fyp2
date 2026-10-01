-- Run after admin_regression.sql, before analytics_regression.sql; always ROLLBACK.
reset role;
select pg_temp.test_assert('private admin invitation FK has leading accepted-by index',
 exists(select 1 from pg_indexes where schemaname='private' and tablename='admin_invitations'
 and indexname='admin_invitations_accepted_by_idx' and indexdef like '%(accepted_by)%'));
select pg_temp.test_assert('private outbox recipient FK has leading recipient index',
 exists(select 1 from pg_indexes where schemaname='private' and tablename='notification_outbox'
 and indexname='notification_outbox_recipient_user_id_idx' and indexdef like '%(recipient_user_id)%'));
select pg_temp.test_assert('provider and service reads have one permissive policy per API role',
 (select bool_and(policy_count=1) from(
  select (select count(*) from pg_policies p where p.schemaname='public' and p.tablename=t.table_name
   and p.permissive='PERMISSIVE' and p.cmd in ('SELECT','ALL')
   and (r.role_name=any(p.roles) or 'public'=any(p.roles))) as policy_count
  from(values('provider_profiles'),('services'))t(table_name)
  cross join(values('anon'::name),('authenticated'::name))r(role_name)
 )checks));
select pg_temp.test_assert('provider and service reads retain restrictive active-account guards',
 (select count(*)=2 from pg_policies where schemaname='public'
 and tablename in ('provider_profiles','services') and policyname='active_account_required'
 and permissive='RESTRICTIVE' and cmd='ALL' and 'authenticated'=any(roles)
 and qual is not null and with_check is not null));
update public.provider_profiles set verification_status='Pending' where provider_id=pg_temp.fixture_id('provider_profile');
set local role authenticated;
select pg_temp.login_as('provider_auth');
select pg_temp.test_assert('consolidated policy preserves unverified provider own service access',
 (select count(*)=1 from public.services where service_id=pg_temp.fixture_id('service')));
reset role;
update public.users set is_active=false where user_id=pg_temp.fixture_id('provider_user');
set local role authenticated;
select pg_temp.login_as('provider_auth');
select pg_temp.test_assert('consolidated policy denies suspended provider own service access',
 (select count(*)=0 from public.services where service_id=pg_temp.fixture_id('service')));
reset role;
update public.users set is_active=true where user_id=pg_temp.fixture_id('provider_user');
update public.provider_profiles set verification_status='Verified' where provider_id=pg_temp.fixture_id('provider_profile');
