-- An unmanaged permissive policy bypassed the verified-provider discovery boundary.
-- Existing provider_authenticated_read still permits the provider's own profile
-- and verified public profiles; provider_self still permits owner updates.
drop policy if exists "Providers can read provider_profiles" on public.provider_profiles;
