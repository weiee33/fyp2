-- Follow-up to the admin foundation: index private foreign keys and evaluate one
-- permissive SELECT policy per API role. No application data or grants change.
create index if not exists admin_invitations_accepted_by_idx
 on private.admin_invitations(accepted_by);
create index if not exists notification_outbox_recipient_user_id_idx
 on private.notification_outbox(recipient_user_id);

drop policy provider_public_read on public.provider_profiles;
drop policy provider_self on public.provider_profiles;
create policy provider_public_read on public.provider_profiles
 for select to anon
 using((select private.provider_is_visible(provider_id)));
create policy provider_authenticated_read on public.provider_profiles
 for select to authenticated
 using(user_id=(select private.current_user_id())
    or (select private.provider_is_visible(provider_id)));
create policy provider_self on public.provider_profiles
 for update to authenticated
 using(user_id=(select private.current_user_id()))
 with check(user_id=(select private.current_user_id()));

drop policy services_public_read on public.services;
drop policy services_provider_write on public.services;
create policy services_public_read on public.services
 for select to anon
 using(is_active is true and availability_status is true
    and (select private.service_is_visible(provider_id,category_id)));
create policy services_authenticated_read on public.services
 for select to authenticated
 using(provider_id in (
       select p.provider_id from public.provider_profiles p
       where p.user_id=(select private.current_user_id()))
    or (is_active is true and availability_status is true
       and (select private.service_is_visible(provider_id,category_id))));
create policy services_provider_write on public.services
 for update to authenticated
 using(provider_id in (
       select p.provider_id from public.provider_profiles p
       where p.user_id=(select private.current_user_id())))
 with check(provider_id in (
       select p.provider_id from public.provider_profiles p
       where p.user_id=(select private.current_user_id())));

-- The foundation's restrictive active_account_required policies remain in place.
-- INSERT/DELETE/TRUNCATE stay revoked; these UPDATE policies grant no privileges.
