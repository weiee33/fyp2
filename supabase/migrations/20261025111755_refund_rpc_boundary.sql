-- Match the existing admin RPC boundary: exposed invoker, private privileged
-- implementation with active Super Admin and AAL2 checks on every invocation.
alter function public.admin_prepare_refund(uuid) set schema private;
create function public.admin_prepare_refund(p_refund_id uuid) returns jsonb
language sql security invoker set search_path='' as $$select private.admin_prepare_refund(p_refund_id)$$;
revoke all on function public.admin_prepare_refund(uuid),private.admin_prepare_refund(uuid) from public,anon;
grant execute on function public.admin_prepare_refund(uuid),private.admin_prepare_refund(uuid) to authenticated;
