-- No screenshots or user prompts are stored in the visual-agent quota ledger.
create table private.customer_visual_runs (
 id uuid primary key,
 owner_id uuid not null references public.users(user_id) on delete cascade,
 auth_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 steps integer not null check (steps between 1 and 12)
);
alter table private.customer_visual_runs enable row level security;
revoke all on private.customer_visual_runs from public,anon,authenticated;
create index customer_visual_runs_owner_created on private.customer_visual_runs(owner_id,created_at);
create index customer_visual_runs_auth on private.customer_visual_runs(auth_id);
create index customer_visual_runs_created on private.customer_visual_runs(created_at);

create function private.customer_ai_visual_budget(p_run_id uuid,p_step integer) returns void
language plpgsql security definer set search_path='' as $$
declare uid uuid:=private.current_user_id(); r private.customer_visual_runs%rowtype;
begin
 perform private.customer_id();
 if p_run_id is null or p_step is null or p_step not between 1 and 12 then
  raise exception 'Invalid agent step.' using errcode='22023'; end if;
 -- Short serialised reservation also bounds aggregate paid model requests.
 perform pg_catalog.pg_advisory_xact_lock(748190341);
 delete from private.customer_visual_runs where created_at < now()-interval '2 days';
 select * into r from private.customer_visual_runs where id=p_run_id for update;
 if found then
  if r.owner_id<>uid or r.auth_id<>auth.uid() then raise exception 'Agent run unavailable.' using errcode='42501'; end if;
  if r.created_at < now()-interval '5 minutes' or p_step<>r.steps+1 then
   raise exception 'Agent run expired or step already used.' using errcode='22023'; end if;
  if r.updated_at>now()-interval '1 second' then raise exception 'Agent is moving too quickly.' using errcode='P0001'; end if;
  update private.customer_visual_runs set steps=p_step,updated_at=now() where id=p_run_id;
 else
  if p_step<>1 then raise exception 'Start a new agent run.' using errcode='22023'; end if;
  if (select count(*) from private.customer_visual_runs where owner_id=uid and created_at>now()-interval '24 hours')>=20
   or (select count(*) from private.customer_visual_runs where owner_id=uid and created_at>now()-interval '1 minute')>=2
   or (select count(*) from private.customer_visual_runs where created_at>now()-interval '24 hours')>=500 then
   raise exception 'AI Agent usage limit reached. Please try again later.' using errcode='P0001'; end if;
  insert into private.customer_visual_runs(id,owner_id,auth_id,steps) values(p_run_id,uid,auth.uid(),1);
 end if;
end $$;
create function public.customer_ai_visual_budget(p_run_id uuid,p_step integer) returns void
language sql security invoker set search_path='' as $$select private.customer_ai_visual_budget(p_run_id,p_step)$$;
revoke all on function private.customer_ai_visual_budget(uuid,integer),public.customer_ai_visual_budget(uuid,integer) from public,anon;
grant execute on function private.customer_ai_visual_budget(uuid,integer),public.customer_ai_visual_budget(uuid,integer) to authenticated;
