-- Run against a configured project with an available verified provider service.
-- All fixtures, notifications and Auth changes roll back. Never targets a real customer.
begin;
create temporary table deletion_integration_results(result text) on commit drop;
do $$
declare
 aid uuid:=gen_random_uuid(); uid uuid; cid uuid; sid uuid; address_id uuid;
 bid uuid; mail text; day date; slots jsonb; payload jsonb; service record;
begin
 mail:='deletion-integration-'||aid::text||'@example.invalid';
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
 values(aid,mail,now(),'{"role":"customer","full_name":"Deletion integration fixture"}');
 select u.user_id,c.customer_id into uid,cid from public.users u
 join public.customer_profiles c using(user_id) where u.auth_user_id=aid;
 if cid is null then raise exception 'Fixture customer was not created'; end if;
 perform set_config('request.jwt.claim.sub',aid::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',aid,'role','authenticated','aal','aal1')::text,true);
 for service in
  select s.service_id from public.services s join public.service_categories c using(category_id)
  join public.provider_profiles p using(provider_id) join public.users u on u.user_id=p.user_id
  where s.is_active and s.availability_status and c.is_active and p.verification_status='Verified' and u.is_active
 loop
  for offset_day in 1..14 loop
   day:=(now() at time zone 'Asia/Kuala_Lumpur')::date+offset_day;
   slots:=private.customer_booking_slots(service.service_id,day);
   if jsonb_array_length(slots)>0 then sid:=service.service_id; exit; end if;
  end loop;
  exit when sid is not null;
 end loop;
 if sid is null then raise exception 'No available service slot for the integration fixture'; end if;
 insert into public.saved_addresses(customer_id,label,address_line,city,state,postcode)
 values(cid,'Test','Synthetic address','Kuala Lumpur','Kuala Lumpur','50000') returning saved_addresses.address_id into address_id;
 payload:=public.customer_create_booking(sid,address_id,day,(slots->0->>'scheduled_time')::time,'Synthetic instructions','Medium',gen_random_uuid());
 bid:=(payload->>'booking_id')::uuid;
 if bid is null or not exists(select 1 from public.bookings where booking_id=bid and request_id is not null) then
  raise exception 'Expected a real app booking with request token';
 end if;
 perform public.customer_cancel_booking(bid,'Integration test cancellation');
 if current_setting('test.expect_original_conflict',true)='true' then
  begin
   perform public.customer_delete_prepare(aid);
   raise exception 'Expected the original booking guard conflict';
  exception when raise_exception then
   if sqlerrm<>'An existing booking keeps its agreed service, price, address and time' then raise; end if;
  end;
  insert into deletion_integration_results values('Reproduced original conflict after real booking creation and cancellation');
  return;
 end if;
 payload:=public.customer_delete_prepare(aid);
 if payload->>'prepared'<>'true' then raise exception 'Deletion preparation did not succeed'; end if;
 if not exists(select 1 from public.bookings where booking_id=bid and booking_status='Cancelled'
   and customer_address='Deleted customer' and customer_coordinates is null and special_instructions is null
   and request_id is not null) then raise exception 'History was not correctly anonymized'; end if;
 if exists(select 1 from public.users where user_id=uid and (auth_user_id is not null or is_active)) then
  raise exception 'Customer identity was not detached'; end if;
 payload:=public.customer_delete_prepare(aid);
 if payload->>'prepared'<>'true' then raise exception 'Deletion retry failed'; end if;
 if public.customer_delete_objects(aid)<>'[]'::jsonb then raise exception 'Fixture unexpectedly owns storage'; end if;
 -- Exercise Auth database cascades and the email cooldown trigger. HTTP password
 -- verification and Storage API handling are covered by the Edge handler tests.
 delete from auth.users where id=aid;
 perform public.customer_delete_finish(aid);
 if not exists(select 1 from private.customer_deletions where auth_user_id=aid and completed_at is not null) then
  raise exception 'Deletion completion was not recorded'; end if;
 begin
  perform public.customer_registration_check(mail);
  raise exception 'Expected the deleted email cooldown';
 exception when raise_exception then
  if sqlerrm<>'This email can be used again 14 days after account deletion.' then raise; end if;
 end;
 insert into deletion_integration_results values('PASS: real booking RPC, cancellation, anonymization, retry, Auth deletion, finish and email cooldown; all fixture changes rolled back');
end $$;
select * from deletion_integration_results;
rollback;
