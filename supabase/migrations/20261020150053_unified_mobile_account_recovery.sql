-- Keep the existing endpoint/RPC compatible with installed clients.
-- Eligibility uses the canonical role and its profile, never editable metadata.
create or replace function private.customer_recovery_check(p_email text,p_ip_hash text) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text; n integer; allowed boolean:=true; eligible boolean;
begin
 if p_email is null or length(p_email)>254 or p_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or p_ip_hash !~ '^[a-f0-9]{64}$' or p_ip_hash is null then raise exception 'Invalid recovery request'; end if;
 -- Fixed one-hour windows; email and IP buckets are locked in consistent order.
 foreach k in array array['email:'||md5(lower(trim(p_email))),'ip:'||p_ip_hash] loop
  insert into private.customer_recovery_limits as r values(k,now(),1)
  on conflict(bucket) do update set window_start=case when r.window_start<now()-interval '1 hour' then now() else r.window_start end,
   attempts=case when r.window_start<now()-interval '1 hour' then 1 else least(r.attempts+1,1000) end returning attempts into n;
  if n>(case when k like 'email:%' then 5 else 30 end) then allowed:=false; end if;
 end loop;
 delete from private.customer_recovery_limits where bucket in(select bucket from private.customer_recovery_limits where window_start<now()-interval '1 day' limit 100);
 if not allowed then return jsonb_build_object('allowed',false); end if;
 select exists(select 1 from auth.users a join public.users u on u.auth_user_id=a.id left join public.customer_profiles c on c.user_id=u.user_id
 left join public.provider_profiles p on p.user_id=u.user_id
 where lower(a.email)=lower(trim(p_email)) and ((u.role='customer' and c.customer_id is not null) or (u.role='provider' and p.provider_id is not null)) and u.is_active and a.email_confirmed_at is not null and (a.banned_until is null or a.banned_until <= now())) into eligible;
 return jsonb_build_object('allowed',true,'registered',eligible);
end $$;
revoke all on function public.customer_recovery_check(text,text),private.customer_recovery_check(text,text) from public,anon,authenticated;
grant execute on function public.customer_recovery_check(text,text),private.customer_recovery_check(text,text) to service_role;
notify pgrst,'reload schema';
