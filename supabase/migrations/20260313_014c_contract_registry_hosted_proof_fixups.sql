-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 014C
-- Hosted proof fixups
-- Purpose:
--   1) explicit-user support grant helper for proof harness
--   2) normalize billed workbench entitlement evaluation
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Explicit-user support grant helper
-- ---------------------------------------------------------

create or replace function contract_registry_private.user_has_active_support_grant_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select exists (
    select 1
    from contract_registry.support_access_grants sag
    where sag.organization_id = p_organization_id
      and sag.granted_user_id = p_user_id
      and sag.granted_role = 'support_readonly'
      and sag.access_status = 'active'
      and (sag.expires_at is null or sag.expires_at > now())
  )
$$;

revoke all on function contract_registry_private.user_has_active_support_grant_as_user_v1(uuid, uuid) from public;

-- ---------------------------------------------------------
-- 2) Explicit-user support readonly org read helper
-- ---------------------------------------------------------

create or replace function contract_registry_private.user_can_support_read_org_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_user_id, 'contract.read')
    or contract_registry_private.user_has_active_support_grant_as_user_v1(p_organization_id, p_user_id)
$$;

revoke all on function contract_registry_private.user_can_support_read_org_as_user_v1(uuid, uuid) from public;

-- ---------------------------------------------------------
-- 3) Normalize workbench billed helper by explicit entitlement check
--     This keeps runtime law aligned with actual entitlement rows.
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_download_workbench_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.user_has_capability_in_org_v1(p_organization_id, 'workbench.download')
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.workbench.download')
$$;

revoke all on function contract_registry.user_can_download_workbench_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_download_workbench_billed_v1(uuid) to authenticated;

create or replace function contract_registry_private.user_can_view_workbench_portal_as_user_v1(
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry_private.user_has_capability_in_org_as_user_v1(
      p_organization_id,
      p_user_id,
      'workbench.download'
    )
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.workbench.download')
$$;

revoke all on function contract_registry_private.user_can_view_workbench_portal_as_user_v1(uuid, uuid) from public;

commit;