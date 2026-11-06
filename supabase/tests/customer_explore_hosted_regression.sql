-- Runs all temporary preference changes in one transaction and rolls them back.
begin;
create temporary table explore_verification(check_name text, passed boolean) on commit drop;
do $$
declare account public.users%rowtype; stored text[]; results jsonb; result jsonb; previous_rank integer:=0; rank integer;
begin
 select u.* into account from public.users u join public.customer_profiles cp using(user_id)
 join auth.users a on a.id=u.auth_user_id
 where u.role='customer' and u.is_active and a.email_confirmed_at is not null
 order by u.user_id limit 1;
 if account.user_id is null then raise exception 'No active customer available for rolled-back validation'; end if;
 perform set_config('request.jwt.claim.sub',account.auth_user_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',account.auth_user_id,'role','authenticated','aal','aal1')::text,true);
 perform public.customer_profile_update(account.full_name,coalesce(account.phone,''),array['Plumbing','Electrical','Plumbing']);
 select service_preferences into stored from public.customer_profiles where user_id=account.user_id;
 if stored<>array['Plumbing','Electrical'] then raise exception 'Preference order not preserved: %',stored; end if;
 insert into explore_verification values('saved order survives database round trip',true);
 results:=public.customer_provider_directory();
 for result in select value from jsonb_array_elements(results) loop
   rank:=array_position(array['plumbing','electrical'],lower(btrim(result->>'category_name')));
   if rank is null or rank<previous_rank then raise exception 'Provider preference mismatch'; end if;
   previous_rank:=rank;
   if not exists(select 1 from public.services s join public.service_categories c using(category_id)
     join public.provider_profiles p using(provider_id) join public.users u on p.user_id=u.user_id
     where p.provider_id=(result->>'provider_id')::uuid and p.verification_status='Verified'
     and u.is_active and s.is_active and s.availability_status and c.is_active
     and s.service_name=result->>'service_name' and c.category_name=result->>'category_name')
     then raise exception 'Unavailable provider/service returned'; end if;
 end loop;
 insert into explore_verification values('provider services match preference order and availability',true);
 if jsonb_array_length(results) > 5 then raise exception 'Directory limit exceeded'; end if;
 insert into explore_verification values('provider limit retained',true);
 perform public.customer_profile_update(account.full_name,coalesce(account.phone,''),'{}');
 results:=public.customer_provider_directory();
 if jsonb_array_length(results) <> least(5,(select count(distinct p.provider_id)::integer
   from public.provider_profiles p join public.users u using(user_id)
   join public.services s using(provider_id) join public.service_categories c using(category_id)
   where p.verification_status='Verified' and u.is_active and s.is_active and s.availability_status and c.is_active))
 then raise exception 'Empty-preference fallback mismatch'; end if;
 insert into explore_verification values('empty preferences show verified directory',true);
 perform public.customer_profile_update(account.full_name,coalesce(account.phone,''),array['__retired_test_category__']);
 if public.customer_provider_directory()<>results then raise exception 'Retired preference fallback mismatch'; end if;
 insert into explore_verification values('retired preferences fall back safely',true);
 if has_function_privilege('anon','public.customer_provider_directory()','execute') then raise exception 'Anonymous access unexpectedly enabled'; end if;
 insert into explore_verification values('anonymous access remains denied',true);
end $$;
select * from explore_verification;
rollback;
