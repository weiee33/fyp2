-- Restore the documented column grants after live broad table grants drifted.
-- Auth provisioning and role/verification changes remain trusted server actions.
revoke all on public.users,public.provider_profiles from public,anon,authenticated;
do $$ declare t text; columns text; begin
 foreach t in array array['users','provider_profiles'] loop
  select string_agg(quote_ident(a.attname),',') into columns from pg_attribute a
  where a.attrelid=('public.'||t)::regclass and a.attnum>0 and not a.attisdropped;
  execute format('revoke select(%s),insert(%s),update(%s),references(%s) on public.%I from public,anon,authenticated',columns,columns,columns,columns,t);
 end loop;
end $$;
grant select(user_id,auth_user_id,email,phone,full_name,role,profile_photo_url,is_active,email_verified,phone_verified,last_login_at,created_at,updated_at) on public.users to authenticated;
grant update(full_name,phone,profile_photo_url) on public.users to authenticated;
grant select(provider_id,user_id,business_name,bio,years_experience,verification_status,overall_rating,total_reviews,service_radius_km,region,city,created_at,updated_at) on public.provider_profiles to anon,authenticated;
grant update(business_name,business_license,bio,years_experience,service_radius_km,region,city) on public.provider_profiles to authenticated;

-- Release only checkout creations that Stripe definitively rejected. Unknown
-- network outcomes retain their idempotency identity to avoid duplicate charges.
create function private.gateway_reject_checkout(p_attempt_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 update private.checkout_attempts set state='Failed'
 where attempt_id=p_attempt_id and state='Creating' and gateway_session_id is null;
end $$;
create function public.gateway_reject_checkout(p_attempt_id uuid) returns void
language sql security invoker set search_path='' as $$ select private.gateway_reject_checkout(p_attempt_id) $$;
revoke all on function private.gateway_reject_checkout(uuid),public.gateway_reject_checkout(uuid) from public,anon,authenticated;
grant execute on function private.gateway_reject_checkout(uuid),public.gateway_reject_checkout(uuid) to service_role;

-- The provider screen uses the same timing rule enforced by the progress RPC.
do $$ declare body text; begin
 body:=pg_get_functiondef('private.provider_booking_list(text,uuid)'::regprocedure);
 body:=replace(body,'b.booking_status=''Confirmed'' and pay.payment_status=''Success'' as can_start',
 'b.booking_status=''Confirmed'' and pay.payment_status=''Success'' and b.scheduled_datetime<=now()+interval ''1 hour'' as can_start');
 execute body;
end $$;
