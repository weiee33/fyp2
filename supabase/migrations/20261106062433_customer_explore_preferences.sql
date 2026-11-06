-- Keep category preference order without changing the existing API contract.
create or replace function private.customer_profile_update(p_full_name text,p_phone text,p_preferences text[],p_photo_url text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.customer_id(); uid uuid; photo_path text;
begin
 select user_id into uid from public.customer_profiles where customer_id=cid for update;
 if p_full_name is null or length(trim(p_full_name)) not between 2 and 150 or p_phone is null
 or nullif(trim(p_phone),'') is not null and trim(p_phone)!~ '^\+?[0-9 ()-]{8,20}$'
 or p_preferences is null or cardinality(p_preferences)>20
 or exists(select 1 from unnest(p_preferences) v where v is null or length(trim(v)) not between 1 and 100) then raise exception 'Enter valid personal details and preferences'; end if;
 if p_photo_url is not null then
  photo_path:=split_part(p_photo_url,'/storage/v1/object/public/profiles/',2);
  if photo_path='' or split_part(photo_path,'/',1)<>auth.uid()::text or split_part(photo_path,'/',2)<>'avatars'
  or not exists(select 1 from storage.objects where bucket_id='profiles' and name=photo_path and owner_id=auth.uid()::text) then
   raise exception 'Choose your own uploaded profile image' using errcode='42501'; end if;
  -- Reconstruct the trusted project origin; do not persist an arbitrary external URL.
  p_photo_url:='https://znxhiymvmluxmdaxzxkt.supabase.co/storage/v1/object/public/profiles/'||photo_path;
 end if;
 update public.users set full_name=trim(p_full_name),phone=nullif(trim(p_phone),''),profile_photo_url=coalesce(p_photo_url,profile_photo_url) where user_id=uid;
 update public.customer_profiles set service_preferences=coalesce((select array_agg(value order by first_position) from (
   select (array_agg(btrim(value) order by position))[1] as value, min(position) as first_position
   from unnest(p_preferences) with ordinality as prefs(value,position)
   group by lower(btrim(value))
 ) ordered_preferences),'{}') where customer_id=cid;
 return jsonb_build_object('customer_id',cid,'user_id',uid);
end $$;

-- Match before limiting, and choose a representative service from the
-- customer's first matching category rather than the provider's cheapest unrelated service.
create or replace function private.customer_provider_directory()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare uid uuid := private.customer_viewer_user_id(); preferences text[];
begin
 if uid is null then
   raise exception 'A verified customer account is required' using errcode='42501';
 end if;
 select coalesce(array_agg(name order by first_position),'{}') into preferences
 from (
   select lower(btrim(pref.name)) as name, min(pref.position) as first_position
   from public.customer_profiles cp,
        unnest(cp.service_preferences) with ordinality as pref(name,position)
   where cp.user_id=uid and exists (
     select 1 from public.service_categories sc
     where sc.is_active is true and lower(btrim(sc.category_name))=lower(btrim(pref.name))
   ) group by lower(btrim(pref.name))
 ) active_preferences;
 return coalesce((select jsonb_agg(to_jsonb(entry) - 'preference_rank' order by
   entry.preference_rank,entry.overall_rating desc nulls last,
   entry.total_reviews desc nulls last,entry.provider_id) from (
   select p.provider_id,p.business_name,p.overall_rating,p.total_reviews,
     u.profile_photo_url as image_url,true as is_verified,
     s.service_name,s.base_price,s.pricing_type,s.category_name,s.preference_rank,
     'Verified provider'::text as match_tag,
     (select count(*) from public.bookings b where b.provider_id=p.provider_id
       and b.booking_status='Completed') as total_jobs
   from public.provider_profiles p join public.users u using(user_id)
   join lateral (
     select sv.service_name,sv.base_price,sv.pricing_type,sc.category_name,
       coalesce(array_position(preferences,lower(btrim(sc.category_name))),1) as preference_rank
     from public.services sv join public.service_categories sc using(category_id)
     where sv.provider_id=p.provider_id and sv.is_active is true
       and sv.availability_status is true and sc.is_active is true
       and (cardinality(preferences)=0 or lower(btrim(sc.category_name))=any(preferences))
     order by preference_rank,sv.base_price,sv.service_id limit 1
   ) s on true
   where p.verification_status='Verified' and u.is_active is true
   order by s.preference_rank,p.overall_rating desc nulls last,
     p.total_reviews desc nulls last,p.provider_id limit 5
 ) entry),'[]'::jsonb);
end $$;
-- Replacing functions preserves the existing invoker wrappers and grants.
notify pgrst,'reload schema';
