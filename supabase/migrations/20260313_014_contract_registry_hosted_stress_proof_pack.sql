-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 014
-- Hosted auth / billing / admin / download stress proof pack
-- Depends on:
--   001..013A
--
-- Purpose:
--   - add deterministic proof tables
--   - add bounded stress/proof RPCs that do not depend on SQL editor auth.uid()
--   - prove hosted gating logic for:
--       * trial vs starter workbench access
--       * member/admin/support boundaries
--       * release visibility surfaces
--   - produce append-only proof rows
--
-- Notes:
--   - This is a proof harness, not product runtime mutation surface
--   - It is deterministic and explicit
--   - It does not weaken the app RPC auth law
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Proof run header
-- ---------------------------------------------------------

create table if not exists contract_registry.hosted_proof_runs (
  id uuid primary key default gen_random_uuid(),
  proof_key text not null unique,
  proof_status text not null default 'running',
  started_at timestamptz not null default now(),
  finished_at timestamptz null,
  note text null,

  constraint hosted_proof_runs_key_chk
    check (length(btrim(proof_key)) > 0),

  constraint hosted_proof_runs_status_chk
    check (proof_status in ('running','passed','failed'))
);

create index if not exists hosted_proof_runs_started_idx
  on contract_registry.hosted_proof_runs(started_at desc);

-- ---------------------------------------------------------
-- 2) Proof events (append-only)
-- ---------------------------------------------------------

create table if not exists contract_registry.hosted_proof_events (
  id bigserial primary key,
  proof_run_id uuid not null references contract_registry.hosted_proof_runs(id) on delete cascade,
  event_utc timestamptz not null default now(),
  event_type text not null,
  event_status text not null,
  event_key text not null,
  detail text null,
  event_json jsonb not null default '{}'::jsonb,

  constraint hosted_proof_events_type_chk
    check (length(btrim(event_type)) > 0),

  constraint hosted_proof_events_status_chk
    check (event_status in ('pass','fail','info')),

  constraint hosted_proof_events_key_chk
    check (length(btrim(event_key)) > 0)
);

create index if not exists hosted_proof_events_run_idx
  on contract_registry.hosted_proof_events(proof_run_id, id);

-- ---------------------------------------------------------
-- 3) Internal helper: append proof event
-- ---------------------------------------------------------

create or replace function contract_registry_private.append_hosted_proof_event_v1(
  p_proof_run_id uuid,
  p_event_type text,
  p_event_status text,
  p_event_key text,
  p_detail text,
  p_event_json jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
begin
  insert into contract_registry.hosted_proof_events (
    proof_run_id,
    event_type,
    event_status,
    event_key,
    detail,
    event_json
  )
  values (
    p_proof_run_id,
    trim(p_event_type),
    trim(p_event_status),
    trim(p_event_key),
    p_detail,
    coalesce(p_event_json, '{}'::jsonb)
  );
end;
$$;

revoke all on function contract_registry_private.append_hosted_proof_event_v1(uuid, text, text, text, text, jsonb) from public;

-- ---------------------------------------------------------
-- 4) Helper: evaluate capability for an explicit user
--     This is proof-only and does NOT replace app auth law.
-- ---------------------------------------------------------

create or replace function contract_registry_private.user_has_capability_in_org_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid,
  p_capability_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select exists (
    select 1
    from contract_registry.organization_members om
    join contract_registry.organizations o
      on o.id = om.organization_id
    join contract_registry.role_definitions rd
      on rd.role_key = om.role
    join contract_registry.role_capabilities rc
      on rc.role_key = om.role
    join contract_registry.capability_definitions cd
      on cd.capability_key = rc.capability_key
    where om.organization_id = p_organization_id
      and om.user_id = p_user_id
      and om.status = 'active'
      and o.is_active = true
      and rd.is_active = true
      and rc.is_granted = true
      and cd.is_active = true
      and cd.capability_key = trim(p_capability_key)
  )
$$;

revoke all on function contract_registry_private.user_has_capability_in_org_as_user_v1(uuid, uuid, text) from public;

create or replace function contract_registry_private.user_has_capability_billed_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
declare
  v_capability contract_registry.capability_definitions%rowtype;
begin
  if not contract_registry_private.user_has_capability_in_org_as_user_v1(
    p_organization_id,
    p_user_id,
    p_capability_key
  ) then
    return false;
  end if;

  select *
    into v_capability
  from contract_registry.capability_definitions cd
  where cd.capability_key = trim(p_capability_key)
    and cd.is_active = true;

  if v_capability.capability_key is null then
    return false;
  end if;

  if v_capability.is_billing_gated = false then
    return true;
  end if;

  return
    billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, v_capability.entitlement_key);
end;
$$;

revoke all on function contract_registry_private.user_has_capability_billed_as_user_v1(uuid, uuid, text) from public;

-- ---------------------------------------------------------
-- 5) Helper: workbench portal access for explicit user
-- ---------------------------------------------------------

create or replace function contract_registry_private.user_can_view_workbench_portal_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry_private.user_has_capability_billed_as_user_v1(
    p_organization_id,
    p_user_id,
    'workbench.download'
  )
$$;

revoke all on function contract_registry_private.user_can_view_workbench_portal_as_user_v1(uuid, uuid) from public;

-- ---------------------------------------------------------
-- 6) Proof runner
-- ---------------------------------------------------------

create or replace function contract_registry.run_hosted_stress_proof_pack_v1(
  p_bootstrap_user_id uuid,
  p_organization_id uuid
)
returns table (
  proof_run_id uuid,
  proof_key text,
  proof_status text,
  total_events bigint,
  pass_events bigint,
  fail_events bigint
)
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
declare
  v_run_id uuid := gen_random_uuid();
  v_proof_key text := 'contract_registry_hosted_proof_' || to_char(now() at time zone 'utc', 'YYYYMMDD_HH24MISS');
  v_plan_before text;
  v_owner_member contract_registry.organization_members%rowtype;
  v_trial_workbench boolean;
  v_starter_workbench boolean;
  v_support_grant_id uuid;
  v_fail_count bigint;
  v_total_count bigint;
  v_pass_count bigint;
begin
  insert into contract_registry.hosted_proof_runs (
    id,
    proof_key,
    proof_status,
    started_at,
    note
  )
  values (
    v_run_id,
    v_proof_key,
    'running',
    now(),
    'Hosted auth/billing/admin/download proof pack'
  );

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,
    'proof.start',
    'info',
    'RUN_CREATED',
    'Hosted proof run created',
    jsonb_build_object(
      'bootstrap_user_id', p_bootstrap_user_id,
      'organization_id', p_organization_id
    )
  );

  if not exists (
    select 1
    from auth.users
    where id = p_bootstrap_user_id
  ) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'fail',
      'BOOTSTRAP_USER_MISSING',
      'Bootstrap user does not exist in auth.users',
      jsonb_build_object('bootstrap_user_id', p_bootstrap_user_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'pass',
      'BOOTSTRAP_USER_EXISTS',
      'Bootstrap user exists',
      jsonb_build_object('bootstrap_user_id', p_bootstrap_user_id)
    );
  end if;

  if not exists (
    select 1
    from contract_registry.organizations o
    where o.id = p_organization_id
      and o.is_active = true
  ) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'fail',
      'ORG_MISSING_OR_INACTIVE',
      'Organization missing or inactive',
      jsonb_build_object('organization_id', p_organization_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'pass',
      'ORG_EXISTS_ACTIVE',
      'Organization exists and is active',
      jsonb_build_object('organization_id', p_organization_id)
    );
  end if;

  select *
    into v_owner_member
  from contract_registry.organization_members om
  where om.organization_id = p_organization_id
    and om.user_id = p_bootstrap_user_id
    and om.status = 'active'
  limit 1;

  if v_owner_member.id is null then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'fail',
      'BOOTSTRAP_MEMBER_MISSING',
      'Bootstrap user is not an active org member',
      jsonb_build_object(
        'organization_id', p_organization_id,
        'bootstrap_user_id', p_bootstrap_user_id
      )
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'proof.precondition',
      'pass',
      'BOOTSTRAP_MEMBER_EXISTS',
      'Bootstrap user is active org member',
      jsonb_build_object(
        'role', v_owner_member.role,
        'status', v_owner_member.status
      )
    );
  end if;

  -- Role/capability proof
  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'contract.read') then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'pass',
      'OWNER_HAS_CONTRACT_READ',
      'Bootstrap member has contract.read',
      '{}'::jsonb
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'fail',
      'OWNER_MISSING_CONTRACT_READ',
      'Bootstrap member missing contract.read',
      '{}'::jsonb
    );
  end if;

  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'release.finalize') then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'pass',
      'OWNER_HAS_RELEASE_FINALIZE',
      'Bootstrap member has release.finalize',
      '{}'::jsonb
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'fail',
      'OWNER_MISSING_RELEASE_FINALIZE',
      'Bootstrap member missing release.finalize',
      '{}'::jsonb
    );
  end if;

  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'admin.members.manage') then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'pass',
      'OWNER_HAS_MEMBER_MANAGE',
      'Bootstrap member has admin.members.manage',
      '{}'::jsonb
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'role.capability',
      'fail',
      'OWNER_MISSING_MEMBER_MANAGE',
      'Bootstrap member missing admin.members.manage',
      '{}'::jsonb
    );
  end if;

  -- Plan / workbench gating proof
  v_plan_before := billing.organization_plan_key_v1(p_organization_id);

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,
    'billing.plan',
    'info',
    'PLAN_BEFORE',
    'Plan before proof transition captured',
    jsonb_build_object('plan_key', v_plan_before)
  );

  v_trial_workbench := contract_registry_private.user_can_view_workbench_portal_as_user_v1(
    p_organization_id,
    p_bootstrap_user_id
  );

  if v_plan_before = 'trial' and v_trial_workbench = false then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'billing.gate',
      'pass',
      'TRIAL_BLOCKS_WORKBENCH',
      'Trial plan correctly blocks workbench portal',
      jsonb_build_object('plan_key', v_plan_before)
    );
  elsif v_plan_before = 'trial' and v_trial_workbench = true then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'billing.gate',
      'fail',
      'TRIAL_UNEXPECTEDLY_ALLOWS_WORKBENCH',
      'Trial plan unexpectedly allows workbench portal',
      jsonb_build_object('plan_key', v_plan_before)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'billing.gate',
      'info',
      'TRIAL_PROOF_SKIPPED',
      'Org was not on trial at proof start',
      jsonb_build_object('plan_key', v_plan_before)
    );
  end if;

  -- Temporarily transition account to starter, apply presets, prove enablement
  update billing.accounts
  set billing_state = 'starter'
  where organization_id = p_organization_id;

  perform billing.apply_plan_presets_to_account_v1(p_organization_id);

  v_starter_workbench := contract_registry_private.user_can_view_workbench_portal_as_user_v1(
    p_organization_id,
    p_bootstrap_user_id
  );

  if v_starter_workbench then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'billing.gate',
      'pass',
      'STARTER_ALLOWS_WORKBENCH',
      'Starter plan enables workbench portal',
      jsonb_build_object('plan_key', 'starter')
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'billing.gate',
      'fail',
      'STARTER_DOES_NOT_ALLOW_WORKBENCH',
      'Starter plan failed to enable workbench portal',
      jsonb_build_object('plan_key', 'starter')
    );
  end if;

  -- Support readonly grant lifecycle proof
  insert into contract_registry.support_access_grants (
    organization_id,
    granted_user_id,
    granted_role,
    access_status,
    reason,
    created_by
  )
  values (
    p_organization_id,
    p_bootstrap_user_id,
    'support_readonly',
    'active',
    'Proof pack self-grant for lifecycle check',
    p_bootstrap_user_id
  )
  returning id
  into v_support_grant_id;

  if contract_registry.user_has_active_support_grant_v1(p_organization_id) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'support.grant',
      'pass',
      'SUPPORT_GRANT_ACTIVE',
      'Support readonly grant recognized as active',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'support.grant',
      'fail',
      'SUPPORT_GRANT_NOT_ACTIVE',
      'Support readonly grant not recognized',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  end if;

  update contract_registry.support_access_grants
  set
    access_status = 'revoked',
    revoked_at = now(),
    revoked_by = p_bootstrap_user_id
  where id = v_support_grant_id;

  if not contract_registry.user_has_active_support_grant_v1(p_organization_id) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'support.grant',
      'pass',
      'SUPPORT_GRANT_REVOKED',
      'Support readonly grant revoked successfully',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'support.grant',
      'fail',
      'SUPPORT_GRANT_REVOKE_FAILED',
      'Support readonly grant remained active after revoke',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  end if;

  -- Workbench catalog proof against seeded 013A release
  if exists (
    select 1
    from contract_registry.v_workbench_release_catalog_v1
    where release_key = 'contract-registry-workbench-v0.1.0'
      and workbench_release_artifact_id = '88888888-8888-8888-8888-888888888888'::uuid
  ) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'workbench.catalog',
      'pass',
      'SEEDED_WORKBENCH_VISIBLE',
      'Seeded published workbench release is visible in catalog view',
      '{}'::jsonb
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,
      'workbench.catalog',
      'fail',
      'SEEDED_WORKBENCH_NOT_VISIBLE',
      'Seeded published workbench release missing from catalog view',
      '{}'::jsonb
    );
  end if;

  -- Restore original plan state and entitlements
  update billing.accounts
  set billing_state = v_plan_before
  where organization_id = p_organization_id;

  perform billing.apply_plan_presets_to_account_v1(p_organization_id);

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,
    'billing.plan',
    'info',
    'PLAN_RESTORED',
    'Organization plan restored after proof run',
    jsonb_build_object('plan_key', v_plan_before)
  );

  select count(*) into v_fail_count
  from contract_registry.hosted_proof_events e
  where e.proof_run_id = v_run_id
    and e.event_status = 'fail';

  select count(*) into v_pass_count
  from contract_registry.hosted_proof_events e
  where e.proof_run_id = v_run_id
    and e.event_status = 'pass';

  select count(*) into v_total_count
  from contract_registry.hosted_proof_events e
  where e.proof_run_id = v_run_id;

  update contract_registry.hosted_proof_runs
  set
    proof_status = case when v_fail_count = 0 then 'passed' else 'failed' end,
    finished_at = now()
  where id = v_run_id;

  return query
  select
    r.id,
    r.proof_key,
    r.proof_status,
    v_total_count,
    v_pass_count,
    v_fail_count
  from contract_registry.hosted_proof_runs r
  where r.id = v_run_id;
end;
$$;

revoke all on function contract_registry.run_hosted_stress_proof_pack_v1(uuid, uuid) from public;
grant execute on function contract_registry.run_hosted_stress_proof_pack_v1(uuid, uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Views
-- ---------------------------------------------------------

create or replace view contract_registry.v_hosted_proof_run_summary_v1 as
select
  r.id as proof_run_id,
  r.proof_key,
  r.proof_status,
  r.started_at,
  r.finished_at,
  (
    select count(*)
    from contract_registry.hosted_proof_events e
    where e.proof_run_id = r.id
  ) as total_events,
  (
    select count(*)
    from contract_registry.hosted_proof_events e
    where e.proof_run_id = r.id
      and e.event_status = 'pass'
  ) as pass_events,
  (
    select count(*)
    from contract_registry.hosted_proof_events e
    where e.proof_run_id = r.id
      and e.event_status = 'fail'
  ) as fail_events
from contract_registry.hosted_proof_runs r
order by r.started_at desc;

grant select on contract_registry.v_hosted_proof_run_summary_v1 to authenticated;

create or replace view contract_registry.v_hosted_proof_events_v1 as
select
  e.id,
  e.proof_run_id,
  r.proof_key,
  r.proof_status as run_status,
  e.event_utc,
  e.event_type,
  e.event_status,
  e.event_key,
  e.detail,
  e.event_json
from contract_registry.hosted_proof_events e
join contract_registry.hosted_proof_runs r
  on r.id = e.proof_run_id
order by e.id;

grant select on contract_registry.v_hosted_proof_events_v1 to authenticated;

commit;