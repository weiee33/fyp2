-- Expired unpaid reservations are not active customer obligations.
create or replace function private.customer_delete_prepare(p_auth_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid; cid uuid; prior private.customer_deletions%rowtype;
begin
 if p_auth_id is null then raise exception 'Sign in again' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_auth_id::text,719));
 select * into prior from private.customer_deletions where auth_user_id=p_auth_id;
 if found then return jsonb_build_object('prepared',true,'completed',prior.completed_at is not null); end if;
 select u.user_id,c.customer_id into uid,cid from public.users u join public.customer_profiles c using(user_id)
 join auth.users a on a.id=u.auth_user_id
 where u.auth_user_id=p_auth_id and u.role='customer' and u.is_active is true and a.email_confirmed_at is not null;
 if uid is null then raise exception 'An active verified customer account is required' using errcode='42501'; end if;
 -- Same customer lock used by booking creation; then lock bookings before examining payment state.
 perform 1 from public.customer_profiles where customer_id=cid for update;
 perform 1 from public.bookings where customer_id=cid order by booking_id for update;
 perform 1 from public.users where user_id=uid for update;
 -- Match the effective expiry shown in the customer app. A paid booking
 -- remains active until completed/cancelled, even after its appointment date.
 if exists(
  select 1 from public.bookings b where b.customer_id=cid and (
   b.booking_status='In-Progress' or
   (b.booking_status in ('Pending','Confirmed') and (
    exists(select 1 from public.payments p where p.booking_id=b.booking_id and p.payment_status in ('Success','Refunded'))
    or ((b.reservation_expires_at is null or b.reservation_expires_at>now())
        and (b.scheduled_datetime is null or b.scheduled_datetime>now()))
   ))
  )
 ) then
  raise exception 'You still have active bookings. Complete or cancel them first. For past paid bookings, contact Help Centre.';
 end if;
 if exists(select 1 from public.booking_disputes d join public.bookings b using(booking_id)
           where b.customer_id=cid and d.status in ('Open','Under Review')) then
  raise exception 'A booking dispute is still open. Contact Help Centre to resolve it before deleting your account.';
 end if;
 -- Do not infer a gateway result from an elapsed local deadline: FPX can
 -- settle asynchronously. Only verified gateway outcomes clear this guard.
 if exists(select 1 from private.checkout_attempts a join public.bookings b using(booking_id)
           where b.customer_id=cid and a.state in ('Creating','Open'))
 or exists(select 1 from public.payments p join public.bookings b using(booking_id)
           where b.customer_id=cid and p.payment_status='Pending') then
  raise exception 'A payment is still being verified. Try again later, or contact Help Centre if it remains pending.';
 end if;
 if exists(select 1 from public.refund_requests r join public.payments p using(payment_id)
           join public.bookings b using(booking_id)
           where b.customer_id=cid and r.status in ('Requested','Processing')) then
  raise exception 'A refund is still pending. Wait for it to finish or contact Help Centre before deleting your account.';
 end if;
 insert into private.customer_deletions(auth_user_id,user_id) values(p_auth_id,uid);
 -- Detach before Auth deletion. Old JWTs immediately lose the application's active identity.
 update public.users set auth_user_id=null,email='deleted-'||uid::text||'@deleted.invalid',phone=null,password_hash=null,
 full_name='Deleted customer',profile_photo_url=null,is_active=false,email_verified=false,phone_verified=false,last_login_at=null where user_id=uid;
 update public.customer_profiles set default_address=null,location_coordinates=null,service_preferences='{}',bio=null,gender=null,birthday=null where customer_id=cid;
 delete from public.saved_addresses where customer_id=cid;
 delete from private.notification_outbox where recipient_user_id=uid;
 delete from public.notifications where user_id=uid;
 delete from public.otp_verifications where user_id=uid;
 update public.bookings set customer_address='Deleted customer',customer_coordinates=null,special_instructions=null where customer_id=cid;
 update public.reviews set review_comment=null,review_image_url=null where customer_id=cid;
 update public.chat_messages set body='[Message removed: account deleted]' where sender_id=uid;
 update public.chat_members set hidden=true,blocked=true where user_id=uid;
 return jsonb_build_object('prepared',true,'completed',false);
end $$;

revoke all on function private.customer_delete_prepare(uuid) from public,anon,authenticated;
grant execute on function private.customer_delete_prepare(uuid) to service_role;
