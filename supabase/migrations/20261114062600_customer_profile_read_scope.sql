-- A legacy SELECT USING (true) policy exposed every customer's profile.
-- Use a restrictive policy so it cannot be OR-ed with another permissive rule.
-- The helper avoids recursive policies through bookings -> customer_profiles.
create function private.can_read_customer_profile(p_customer_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.customer_profiles c where c.customer_id=p_customer_id and (
   c.user_id=(select private.current_user_id())
   or c.user_id=(select private.customer_viewer_user_id())
   or exists(select 1 from public.provider_profiles p
     where p.user_id=(select private.current_user_id()) and (
       exists(select 1 from public.bookings b where b.provider_id=p.provider_id and b.customer_id=c.customer_id)
       or exists(select 1 from public.reviews r where r.provider_id=p.provider_id and r.customer_id=c.customer_id)
     ))
  )
 )
$$;
revoke all on function private.can_read_customer_profile(uuid) from public,anon;
grant execute on function private.can_read_customer_profile(uuid) to authenticated;
create policy customer_profile_read_scope on public.customer_profiles
as restrictive for select to authenticated
using (private.can_read_customer_profile(customer_id));

-- Detached/deleted identities must not retain access through legacy user reads.
create policy user_read_identity_required on public.users
as restrictive for select to authenticated
using (auth_user_id=(select auth.uid()) or (select private.current_user_id()) is not null
       or user_id=(select private.customer_viewer_user_id()));
