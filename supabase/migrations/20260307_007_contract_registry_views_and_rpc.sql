-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 007
-- App-facing views + narrow RPC helpers
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
--   005_contract_registry_release_artifacts.sql
--   006_contract_registry_billing_entitlements.sql
-- Rooted-style posture:
--   thin views
--   narrow RPC helpers
--   no truth-law logic moved into SQL surface
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) App-facing views
-- ---------------------------------------------------------

create or replace view contract_registry.v_contracts_overview_v1 as
select
  c.id,
  c.organization_id,
  c.contract_key,
  c.title,
  c.description,
  c.status,
  c.current_version_id,
  c.created_at,
  c.created_by,
  c.updated_at,
  c.updated_by,
  cv.version_no as current_version_no,
  cv.version_label as current_version_label,
  cv.status as current_version_status
from contract_registry.contracts c
left join contract_registry.contract_versions cv
  on cv.id = c.current_version_id;

create or replace view contract_registry.v_contract_versions_overview_v1 as
select
  cv.id,
  cv.contract_id,
  c.organization_id,
  c.contract_key,
  c.title as contract_title,
  cv.version_no,
  cv.version_label,
  cv.status,
  cv.source_json_sha256,
  cv.source_json_storage_path,
  cv.changelog,
  cv.created_at,
  cv.created_by,
  cv.updated_at,
  cv.updated_by
from contract_registry.contract_versions cv
join contract_registry.contracts c
  on c.id = cv.contract_id;

create or replace view contract_registry.v_release_jobs_overview_v1 as
select
  rj.id,
  rj.organization_id,
  rj.contract_version_id,
  cv.contract_id,
  c.contract_key,
  c.title as contract_title,
  cv.version_no,
  cv.version_label,
  rj.job_type,
  rj.job_status,
  rj.requested_by,
  rj.started_at,
  rj.finished_at,
  rj.runner_ref,
  rj.error_code,
  rj.error_detail,
  rj.created_at
from contract_registry.release_jobs rj
join contract_registry.contract_versions cv
  on cv.id = rj.contract_version_id
join contract_registry.contracts c
  on c.id = cv.contract_id;

create or replace view contract_registry.v_contract_releases_overview_v1 as
select
  cr.id,
  cr.organization_id,
  cr.contract_version_id,
  cv.contract_id,
  c.contract_key,
  c.title as contract_title,
  cv.version_no,
  cv.version_label,
  cr.release_status,
  cr.release_kind,
  cr.released_at,
  cr.released_by,
  cr.packet_id,
  cr.packet_root_storage_path,
  cr.release_receipt_storage_path,
  cr.release_receipt_sha256,
  cr.effective_sets_receipt_storage_path,
  cr.effective_sets_receipt_sha256,
  cr.verification_receipt_storage_path,
  cr.verification_receipt_sha256,
  cr.created_at
from contract_registry.contract_releases cr
join contract_registry.contract_versions cv
  on cv.id = cr.contract_version_id
join contract_registry.contracts c
  on c.id = cv.contract_id;

create or replace view contract_registry.v_overlay_profiles_overview_v1 as
select
  'policy'::text as overlay_type,
  p.id,
  p.organization_id,
  p.overlay_key,
  p.title,
  p.description,
  p.overlay_storage_path,
  p.overlay_sha256,
  p.is_active,
  p.created_at,
  p.created_by,
  p.updated_at,
  p.updated_by
from contract_registry.policy_overlay_profiles p

union all

select
  'schema'::text as overlay_type,
  s.id,
  s.organization_id,
  s.overlay_key,
  s.title,
  s.description,
  s.overlay_storage_path,
  s.overlay_sha256,
  s.is_active,
  s.created_at,
  s.created_by,
  s.updated_at,
  s.updated_by
from contract_registry.schema_overlay_profiles s;

create or replace view contract_registry.v_billing_overview_v1 as
select
  a.id as account_id,
  a.organization_id,
  a.billing_state,
  a.created_at as account_created_at,
  s.id as subscription_id,
  s.provider,
  s.provider_customer_id,
  s.provider_subscription_id,
  s.plan_key,
  s.status as subscription_status,
  s.period_start,
  s.period_end,
  s.created_at as subscription_created_at
from billing.accounts a
left join billing.subscriptions s
  on s.account_id = a.id;

-- ---------------------------------------------------------
-- 2) View privileges
-- ---------------------------------------------------------

grant select on contract_registry.v_contracts_overview_v1 to authenticated;
grant select on contract_registry.v_contract_versions_overview_v1 to authenticated;
grant select on contract_registry.v_release_jobs_overview_v1 to authenticated;
grant select on contract_registry.v_contract_releases_overview_v1 to authenticated;
grant select on contract_registry.v_overlay_profiles_overview_v1 to authenticated;
grant select on contract_registry.v_billing_overview_v1 to authenticated;

-- ---------------------------------------------------------
-- 3) Narrow RPC: list org contracts
-- ---------------------------------------------------------

create or replace function contract_registry.list_contracts_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_contracts_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_contracts_overview_v1 v
  where v.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
  order by v.updated_at desc, v.contract_key asc
$$;

revoke all on function contract_registry.list_contracts_v1(uuid) from public;
grant execute on function contract_registry.list_contracts_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 4) Narrow RPC: list contract versions
-- ---------------------------------------------------------

create or replace function contract_registry.list_contract_versions_v1(
  p_contract_id uuid
)
returns setof contract_registry.v_contract_versions_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_contract_versions_overview_v1 v
  where v.contract_id = p_contract_id
    and contract_registry.user_is_org_member_v1(v.organization_id)
  order by v.version_no desc
$$;

revoke all on function contract_registry.list_contract_versions_v1(uuid) from public;
grant execute on function contract_registry.list_contract_versions_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5) Narrow RPC: list release jobs for org
-- ---------------------------------------------------------

create or replace function contract_registry.list_release_jobs_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_release_jobs_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_release_jobs_overview_v1 v
  where v.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
  order by v.created_at desc
$$;

revoke all on function contract_registry.list_release_jobs_v1(uuid) from public;
grant execute on function contract_registry.list_release_jobs_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 6) Narrow RPC: list releases for org
-- ---------------------------------------------------------

create or replace function contract_registry.list_contract_releases_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_contract_releases_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_contract_releases_overview_v1 v
  where v.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
  order by coalesce(v.released_at, v.created_at) desc
$$;

revoke all on function contract_registry.list_contract_releases_v1(uuid) from public;
grant execute on function contract_registry.list_contract_releases_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Narrow RPC: list overlays for org
-- ---------------------------------------------------------

create or replace function contract_registry.list_overlay_profiles_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_overlay_profiles_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_overlay_profiles_overview_v1 v
  where v.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
  order by v.overlay_type asc, v.overlay_key asc
$$;

revoke all on function contract_registry.list_overlay_profiles_v1(uuid) from public;
grant execute on function contract_registry.list_overlay_profiles_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 8) Narrow RPC: org billing overview
-- ---------------------------------------------------------

create or replace function contract_registry.get_billing_overview_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_billing_overview_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select *
  from contract_registry.v_billing_overview_v1 v
  where v.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
$$;

revoke all on function contract_registry.get_billing_overview_v1(uuid) from public;
grant execute on function contract_registry.get_billing_overview_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 9) Narrow RPC: org entitlement snapshot
-- ---------------------------------------------------------

create or replace function contract_registry.get_entitlements_v1(
  p_organization_id uuid
)
returns table (
  organization_id uuid,
  account_id uuid,
  entitlement_key text,
  is_enabled boolean,
  limit_int integer,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    a.organization_id,
    e.account_id,
    e.entitlement_key,
    e.is_enabled,
    e.limit_int,
    e.updated_at
  from billing.accounts a
  join billing.entitlements e
    on e.account_id = a.id
  where a.organization_id = p_organization_id
    and contract_registry.user_is_org_member_v1(p_organization_id)
  order by e.entitlement_key asc
$$;

revoke all on function contract_registry.get_entitlements_v1(uuid) from public;
grant execute on function contract_registry.get_entitlements_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 10) Narrow RPC: get release artifact bundle by release id
-- ---------------------------------------------------------

create or replace function contract_registry.get_release_artifact_bundle_v1(
  p_release_id uuid
)
returns table (
  release_id uuid,
  organization_id uuid,
  contract_version_id uuid,
  release_status text,
  release_kind text,
  packet_id text,
  packet_root_storage_path text,
  tier0_receipt_storage_path text,
  tier0_receipt_sha256 text,
  golden_receipt_storage_path text,
  golden_receipt_sha256 text,
  verification_receipt_storage_path text,
  verification_receipt_sha256 text,
  effective_sets_receipt_storage_path text,
  effective_sets_receipt_sha256 text,
  policy_effective_hash text,
  schema_effective_hash text,
  allow_overrides boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    cr.id as release_id,
    cr.organization_id,
    cr.contract_version_id,
    cr.release_status,
    cr.release_kind,
    rp.packet_id,
    rp.packet_root_storage_path,
    rr.tier0_receipt_storage_path,
    rr.tier0_receipt_sha256,
    rr.golden_receipt_storage_path,
    rr.golden_receipt_sha256,
    rr.verification_receipt_storage_path,
    rr.verification_receipt_sha256,
    es.effective_sets_receipt_storage_path,
    es.effective_sets_receipt_sha256,
    es.policy_effective_hash,
    es.schema_effective_hash,
    es.allow_overrides
  from contract_registry.contract_releases cr
  left join contract_registry.release_packets rp
    on rp.release_id = cr.id
  left join contract_registry.release_receipts rr
    on rr.release_id = cr.id
  left join contract_registry.effective_sets es
    on es.release_id = cr.id
  where cr.id = p_release_id
    and contract_registry.user_is_org_member_v1(cr.organization_id)
$$;

revoke all on function contract_registry.get_release_artifact_bundle_v1(uuid) from public;
grant execute on function contract_registry.get_release_artifact_bundle_v1(uuid) to authenticated;

commit;