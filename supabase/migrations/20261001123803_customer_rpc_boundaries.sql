-- Keep privileged implementations outside the exposed API schema.
alter function public.account_identity() set schema private;
alter function public.customer_save_address(text,text,text,text,text,double precision,double precision,boolean) set schema private;
alter function public.customer_set_default_address(uuid) set schema private;
alter function public.customer_provider_directory() set schema private;

create function public.account_identity() returns jsonb language sql stable security invoker set search_path=''
as $$select private.account_identity()$$;
create function public.customer_save_address(address_label text,address_text text,address_city text,address_state text,address_postcode text,
 latitude double precision,longitude double precision,make_default boolean default false) returns jsonb language sql security invoker set search_path=''
as $$select private.customer_save_address(address_label,address_text,address_city,address_state,address_postcode,latitude,longitude,make_default)$$;
create function public.customer_set_default_address(selected_address uuid) returns jsonb language sql security invoker set search_path=''
as $$select private.customer_set_default_address(selected_address)$$;
create function public.customer_provider_directory() returns jsonb language sql stable security invoker set search_path=''
as $$select private.customer_provider_directory()$$;
revoke all on function public.account_identity(),public.customer_save_address(text,text,text,text,text,double precision,double precision,boolean),
 public.customer_set_default_address(uuid),public.customer_provider_directory() from public,anon;
grant execute on function public.account_identity(),public.customer_save_address(text,text,text,text,text,double precision,double precision,boolean),
 public.customer_set_default_address(uuid),public.customer_provider_directory() to authenticated;

create index booking_service_provider_idx on public.bookings(service_id,provider_id);
create index payment_booking_customer_idx on public.payments(booking_id,customer_id);
create index earnings_booking_provider_idx on public.provider_earnings(booking_id,provider_id);
create index review_booking_parties_idx on public.reviews(booking_id,customer_id,provider_id);
notify pgrst,'reload schema';
