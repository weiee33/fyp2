-- Transaction-only verification. No profile, account status, notification,
-- audit record or push/outbox work is committed.
begin;
create temporary table activity_verification(check_name text, passed boolean) on commit drop;
do $$
declare account public.users%rowtype; admin_auth uuid; baseline uuid[]; notice public.notifications%rowtype;
  amount integer; expected_version text; inbox jsonb;
begin
 select u.* into account from public.users u join public.customer_profiles c using(user_id)
 where u.role='customer' and u.is_active and u.auth_user_id is not null order by u.user_id limit 1;
 select u.auth_user_id into admin_auth from public.users u join public.admin_profiles a using(user_id)
 where u.role='admin' and u.is_active and u.auth_user_id is not null order by u.user_id limit 1;
 if account.user_id is null or admin_auth is null then raise exception 'Customer and admin fixtures required'; end if;
 select coalesce(array_agg(notification_id),'{}') into baseline from public.notifications where user_id=account.user_id;
 update public.users set full_name=full_name where user_id=account.user_id;
 if exists(select 1 from public.notifications where user_id=account.user_id and not(notification_id=any(baseline))) then raise exception 'No-op emitted activity'; end if;
 insert into activity_verification values('unchanged profile emits no notification',true);
 update public.users set full_name='Notification validation fixture' where user_id=account.user_id;
 select * into strict notice from public.notifications where user_id=account.user_id and not(notification_id=any(baseline));
 if notice.message<>'Your name was updated.' or notice.event_key<>'customer.activity' then raise exception 'Incorrect changed field'; end if;
 insert into activity_verification values('name edit emits precise server activity',true);
 select coalesce(array_agg(notification_id),'{}') into baseline from public.notifications where user_id=account.user_id;
 update public.customer_profiles set bio='Rollback-only fixture bio',birthday=date '1991-02-03' where user_id=account.user_id;
 select * into strict notice from public.notifications where user_id=account.user_id and not(notification_id=any(baseline));
 if notice.message<>E'Your bio was updated.\nYour birthday was updated.' then raise exception 'Multiple fields missing'; end if;
 insert into activity_verification values('multi-field changes retain details without personal values',true);
 perform set_config('request.jwt.claim.sub',account.auth_user_id::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',account.auth_user_id,'role','authenticated','aal','aal1')::text,true);
 begin
  perform private.admin_notify(account.user_id,'Account status updated','Rollback-only validation');
  raise exception 'Customer bypassed admin guard';
 exception when insufficient_privilege then null; end;
 insert into activity_verification values('customer cannot generate admin status events',true);
 inbox:=public.chat_inbox();
 if exists(select 1 from jsonb_array_elements(inbox) r
   join public.chat_conversations c on c.conversation_id=(r->>'conversation_id')::uuid
   join public.users u on u.user_id=c.provider_user_id
   where r->>'profile_photo_url' is distinct from u.profile_photo_url)
 then raise exception 'Chat photo differs from provider profile'; end if;
 insert into activity_verification values('inbox photo matches provider profile for returned conversations',true);
 perform set_config('request.jwt.claim.sub',admin_auth::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_auth,'role','authenticated','aal','aal2')::text,true);
 select md5(to_jsonb(u)::text) into expected_version from public.users u where user_id=account.user_id;
 perform public.admin_mutate('user_status',account.user_id,expected_version,'{"active":false,"reason":"Rollback-only suspension validation"}');
 select count(*) into amount from public.notifications where user_id=account.user_id and event_key='account.suspended'
 and message='Rollback-only suspension validation';
 if amount<>1 then raise exception 'Suspension notification missing or duplicated'; end if;
 insert into activity_verification values('real admin suspension creates explicit warning event',true);
 select md5(to_jsonb(u)::text) into expected_version from public.users u where user_id=account.user_id;
 perform public.admin_mutate('user_status',account.user_id,expected_version,'{"active":true,"reason":"Rollback-only reactivation validation"}');
 if not exists(select 1 from public.notifications where user_id=account.user_id and event_key='account.reactivated'
   and message='Rollback-only reactivation validation') then raise exception 'Reactivation event missing'; end if;
 insert into activity_verification values('real admin reactivation creates a separate event',true);
 if has_column_privilege('authenticated','public.notifications','event_key','UPDATE')
 or has_function_privilege('authenticated','private.admin_notify(uuid,text,text,uuid)','EXECUTE')
 then raise exception 'Event write privilege exposed'; end if;
 insert into activity_verification values('client cannot forge event keys or invoke internal notifier',true);
end $$;
select * from activity_verification;
rollback;
