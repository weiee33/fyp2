-- Upload reservations must not block deletion of an Auth identity.
alter table private.customer_support_drafts drop constraint customer_support_drafts_auth_id_fkey;
alter table private.customer_support_drafts add constraint customer_support_drafts_auth_id_fkey foreign key(auth_id) references auth.users(id) on delete cascade;
