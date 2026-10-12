-- Public service-area centres are explicitly selected by providers, never inferred from home addresses.
alter table public.provider_profiles add column service_latitude double precision, add column service_longitude double precision,
 add constraint provider_service_center_pair check ((service_latitude is null and service_longitude is null) or
 (service_latitude is not null and service_longitude is not null and service_latitude between -1 and 8 and service_longitude between 99 and 120));
grant select(service_latitude,service_longitude),update(service_latitude,service_longitude) on public.provider_profiles to authenticated;

create function private.customer_provider_coverage(p_lat double precision,p_lng double precision,p_range_km double precision default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform private.customer_id();
 if p_lat is null or p_lng is null or p_range_km is null or p_lat not between -1 and 8 or p_lng not between 99 and 120 or p_range_km not between 1 and 100 then raise exception 'Invalid map area'; end if;
 return coalesce((select jsonb_agg(to_jsonb(item)) from (
  select p.provider_id,p.business_name,p.service_latitude,p.service_longitude,p.service_radius_km,p.city,
    d.distance_km, d.distance_km<=p.service_radius_km as covers_selected,
    (select jsonb_agg(s.service_name order by s.service_name) from public.services s join public.service_categories c using(category_id)
      where s.provider_id=p.provider_id and s.is_active and s.availability_status and c.is_active) as services
  from public.provider_profiles p join public.users u using(user_id)
  cross join lateral (select 6371*acos(least(1.0,greatest(-1.0,sin(radians(p_lat))*sin(radians(p.service_latitude))+
    cos(radians(p_lat))*cos(radians(p.service_latitude))*cos(radians(p.service_longitude-p_lng)))))) d(distance_km)
  where p.verification_status='Verified' and u.is_active and p.service_latitude is not null and p.service_longitude is not null
   and p.service_radius_km between 1 and 200 and d.distance_km<=p_range_km+p.service_radius_km
   and exists(select 1 from public.services s join public.service_categories c using(category_id) where s.provider_id=p.provider_id and s.is_active and s.availability_status and c.is_active)
  order by d.distance_km,p.provider_id limit 50
 ) item),'[]'::jsonb);
end $$;
create function public.customer_provider_coverage(p_lat double precision,p_lng double precision,p_range_km double precision default 50)
returns jsonb language sql stable security invoker set search_path='' as $$select private.customer_provider_coverage(p_lat,p_lng,p_range_km)$$;
revoke all on function private.customer_provider_coverage(double precision,double precision,double precision),public.customer_provider_coverage(double precision,double precision,double precision) from public,anon;
grant execute on function private.customer_provider_coverage(double precision,double precision,double precision),public.customer_provider_coverage(double precision,double precision,double precision) to authenticated;

create function private.customer_review_queue(p_limit integer default 20,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.customer_id();
begin
 if p_limit is null or p_limit not between 1 and 50 or p_offset is null or p_offset not between 0 and 10000 then raise exception 'Invalid review page'; end if;
 return coalesce((select jsonb_agg(to_jsonb(item)) from (
  select b.booking_id,b.provider_id,b.service_name_snapshot,b.provider_name_snapshot,b.completed_at
  from public.bookings b where b.customer_id=cid and b.booking_status='Completed'
  and exists(select 1 from public.payments pay where pay.booking_id=b.booking_id and pay.payment_status='Success')
  and not exists(select 1 from public.reviews r where r.booking_id=b.booking_id)
  order by b.completed_at desc nulls last,b.booking_id limit p_limit offset p_offset
 ) item),'[]'::jsonb);
end $$;
create function public.customer_review_queue(p_limit integer default 20,p_offset integer default 0) returns jsonb
language sql stable security invoker set search_path='' as $$select private.customer_review_queue(p_limit,p_offset)$$;
revoke all on function private.customer_review_queue(integer,integer),public.customer_review_queue(integer,integer) from public,anon;
grant execute on function private.customer_review_queue(integer,integer),public.customer_review_queue(integer,integer) to authenticated;
notify pgrst,'reload schema';
