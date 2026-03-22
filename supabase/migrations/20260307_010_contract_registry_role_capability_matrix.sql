-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 010
-- Role/capability matrix + user tiers + downstream capability law
-- Depends on:
--   001..009B1
-- Rooted-style posture:
--   auth answers identity
--   org membership answers tenancy
--   role grants capability
--   billing/entitlements gate hosted capability
--   no vague permissions
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Canonical role registry
-- ---------------------------------------------------------

create table if not exists contract_registry.role_definitions (
  role_key text primary key,
  title text not null,
  description text null,
  is_system boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint role_definitions_role_key_chk
    check (length(btrim(role_key)) > 0),

  constraint role_definitions_title_chk
    check (length(btrim(title)) > 0)
);

create index if not exists role_definitions_active_idx
  on contract_registry.role_definitions(is_active);

insert into contract_registry.role_definitions (
  role_key,
  title,
  description,
  is_system,
  is_active
)
values
  ('owner', 'Owner', 'Full organization owner with all customer-org capabilities', true, true),
  ('admin', 'Admin', 'Administrative manager for organization operations', true, true),
  ('editor', 'Editor', 'Can create and edit contracts and versions', true, true),
  ('reviewer', 'Reviewer', 'Can review contract data and release readiness', true, true),
  ('release_manager', 'Release Manager', 'Can create/finalize release jobs and release artifacts', true, true),
  ('viewer', 'Viewer', 'Read-only org member', true, true),
  ('billing_admin', 'Billing Admin', 'Can view/manage billing and entitlements', true, true),
  ('support_readonly', 'Support Readonly', 'Read-only support/diagnostic access when granted explicitly', true, true),
  ('workbench_downloader', 'Workbench Downloader', 'Can access workbench/download surface when entitled', true, true)
on conflict (role_key) do update
set
  title = excluded.title,
  description = excluded.description,
  is_system = excluded.is_system,
  is_active = excluded.is_active;

-- ---------------------------------------------------------
-- 2) Canonical capability registry
-- ---------------------------------------------------------

create table if not exists contract_registry.capability_definitions (
  capability_key text primary key,
  title text not null,
  description text null,
  is_billing_gated boolean not null default false,
  entitlement_key text null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint capability_definitions_key_chk
    check (length(btrim(capability_key)) > 0),

  constraint capability_definitions_title_chk
    check (length(btrim(title)) > 0),

  constraint capability_definitions_entitlement_consistency_chk
    check (
      (is_billing_gated = false and entitlement_key is null)
      or
      (is_billing_gated = true and entitlement_key is not null)
    )
);

create index if not exists capability_definitions_active_idx
  on contract_registry.capability_definitions(is_active);

insert into contract_registry.capability_definitions (
  capability_key,
  title,
  description,
  is_billing_gated,
  entitlement_key,
  is_active
)
values
  ('contract.read', 'Read Contracts', 'Read contracts, versions, releases, and receipts within org scope', false, null, true),
  ('contract.write', 'Write Contracts', 'Create and edit contracts', true, 'contract_registry.write', true),
  ('contract.version.write', 'Write Contract Versions', 'Create/edit contract versions', true, 'contract_registry.write', true),
  ('contract.current_version.set', 'Set Current Version', 'Select the current contract version', true, 'contract_registry.write', true),
  ('overlay.manage', 'Manage Overlays', 'Create/update policy and schema overlay profiles', true, 'contract_registry.overlay.manage', true),
  ('release.job.create', 'Create Release Job', 'Create release jobs', true, 'contract_registry.release', true),
  ('release.finalize', 'Finalize Release', 'Finalize release artifacts and hosted refs', true, 'contract_registry.release', true),
  ('billing.read', 'Read Billing', 'View billing summary and entitlements', true, 'contract_registry.api.access', true),
  ('billing.manage', 'Manage Billing', 'Manage plan/billing administrative actions', true, 'contract_registry.api.access', true),
  ('audit.read', 'Read Audit', 'Read release receipts, evidence refs, and hosted audit surfaces', true, 'contract_registry.audit.read', true),
  ('admin.members.manage', 'Manage Members', 'Invite/remove/change member roles', true, 'contract_registry.team.invite', true),
  ('admin.org.manage', 'Manage Org', 'Manage organization-level hosted settings', true, 'contract_registry.admin.console', true),
  ('support.readonly', 'Support Readonly', 'Support-only diagnostic read surface', false, null, true),
  ('workbench.download', 'Download Workbench', 'Access workbench/download portal', true, 'contract_registry.workbench.download', true)
on conflict (capability_key) do update
set
  title = excluded.title,
  description = excluded.description,
  is_billing_gated = excluded.is_billing_gated,
  entitlement_key = excluded.entitlement_key,
  is_active = excluded.is_active;

-- ---------------------------------------------------------
-- 3) Role → capability matrix
-- ---------------------------------------------------------

create table if not exists contract_registry.role_capabilities (
  role_key text not null references contract_registry.role_definitions(role_key) on delete cascade,
  capability_key text not null references contract_registry.capability_definitions(capability_key) on delete cascade,
  is_granted boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (role_key, capability_key)
);

create index if not exists role_capabilities_capability_idx
  on contract_registry.role_capabilities(capability_key);

insert into contract_registry.role_capabilities (role_key, capability_key, is_granted)
values
  -- owner
  ('owner','contract.read',true),
  ('owner','contract.write',true),
  ('owner','contract.version.write',true),
  ('owner','contract.current_version.set',true),
  ('owner','overlay.manage',true),
  ('owner','release.job.create',true),
  ('owner','release.finalize',true),
  ('owner','billing.read',true),
  ('owner','billing.manage',true),
  ('owner','audit.read',true),
  ('owner','admin.members.manage',true),
  ('owner','admin.org.manage',true),
  ('owner','workbench.download',true),

  -- admin
  ('admin','contract.read',true),
  ('admin','contract.write',true),
  ('admin','contract.version.write',true),
  ('admin','contract.current_version.set',true),
  ('admin','overlay.manage',true),
  ('admin','release.job.create',true),
  ('admin','release.finalize',true),
  ('admin','billing.read',true),
  ('admin','audit.read',true),
  ('admin','admin.members.manage',true),
  ('admin','admin.org.manage',true),
  ('admin','workbench.download',true),

  -- editor
  ('editor','contract.read',true),
  ('editor','contract.write',true),
  ('editor','contract.version.write',true),
  ('editor','contract.current_version.set',true),

  -- reviewer
  ('reviewer','contract.read',true),
  ('reviewer','audit.read',true),

  -- release_manager
  ('release_manager','contract.read',true),
  ('release_manager','release.job.create',true),
  ('release_manager','release.finalize',true),
  ('release_manager','audit.read',true),

  -- viewer
  ('viewer','contract.read',true),

  -- billing_admin
  ('billing_admin','billing.read',true),
  ('billing_admin','billing.manage',true),

  -- support_readonly
  ('support_readonly','contract.read',true),
  ('support_readonly','audit.read',true),
  ('support_readonly','support.readonly',true),

  -- workbench_downloader
  ('workbench_downloader','workbench.download',true)
on conflict (role_key, capability_key) do update
set
  is_granted = excluded.is_granted;

-- ---------------------------------------------------------
-- 4) Organization member role validation
-- ---------------------------------------------------------

alter table contract_registry.organization_members
  drop constraint if exists organization_members_role_fk;

alter table contract_registry.organization_members
  add constraint organization_members_role_fk
  foreign key (role)
  references contract_registry.role_definitions(role_key);

-- ---------------------------------------------------------
-- 5) Capability helpers
-- ---------------------------------------------------------

create or replace function contract_registry.user_has_role_in_org_v1(
  p_organization_id uuid,
  p_role_key text
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
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
      and o.is_active = true
      and rd.is_active = true
      and om.role = trim(p_role_key)
  )
$$;

revoke all on function contract_registry.user_has_role_in_org_v1(uuid, text) from public;
grant execute on function contract_registry.user_has_role_in_org_v1(uuid, text) to authenticated;

create or replace function contract_registry.user_has_capability_in_org_v1(
  p_organization_id uuid,
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
      and om.user_id = auth.uid()
      and om.status = 'active'
      and o.is_active = true
      and rd.is_active = true
      and rc.is_granted = true
      and cd.is_active = true
      and cd.capability_key = trim(p_capability_key)
  )
$$;

revoke all on function contract_registry.user_has_capability_in_org_v1(uuid, text) from public;
grant execute on function contract_registry.user_has_capability_in_org_v1(uuid, text) to authenticated;

create or replace function contract_registry.user_has_capability_billed_v1(
  p_organization_id uuid,
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
  if not contract_registry.user_has_capability_in_org_v1(p_organization_id, p_capability_key) then
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

revoke all on function contract_registry.user_has_capability_billed_v1(uuid, text) from public;
grant execute on function contract_registry.user_has_capability_billed_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 6) Replace old coarse helpers with capability-based law
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_write_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'contract.write'
  )
$$;

revoke all on function contract_registry.user_can_write_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_write_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_release_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'release.finalize'
  )
$$;

revoke all on function contract_registry.user_can_release_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_release_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_manage_overlays_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'overlay.manage'
  )
$$;

revoke all on function contract_registry.user_can_manage_overlays_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_overlays_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_manage_billing_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'billing.manage'
  )
$$;

revoke all on function contract_registry.user_can_manage_billing_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_billing_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_download_workbench_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'workbench.download'
  )
$$;

revoke all on function contract_registry.user_can_download_workbench_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_download_workbench_billed_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Read views for role/capability introspection
-- ---------------------------------------------------------

create or replace view contract_registry.v_role_capability_matrix_v1 as
select
  rd.role_key,
  rd.title as role_title,
  rd.description as role_description,
  cd.capability_key,
  cd.title as capability_title,
  cd.description as capability_description,
  cd.is_billing_gated,
  cd.entitlement_key,
  rc.is_granted
from contract_registry.role_definitions rd
join contract_registry.role_capabilities rc
  on rc.role_key = rd.role_key
join contract_registry.capability_definitions cd
  on cd.capability_key = rc.capability_key
where rd.is_active = true
  and cd.is_active = true
order by rd.role_key, cd.capability_key;

grant select on contract_registry.v_role_capability_matrix_v1 to authenticated;

create or replace view contract_registry.v_organization_members_with_capabilities_v1 as
select
  om.organization_id,
  om.user_id,
  om.role,
  rd.title as role_title,
  om.status,
  rc.capability_key,
  cd.title as capability_title,
  cd.is_billing_gated,
  cd.entitlement_key,
  rc.is_granted,
  om.created_at,
  om.created_by
from contract_registry.organization_members om
join contract_registry.role_definitions rd
  on rd.role_key = om.role
join contract_registry.role_capabilities rc
  on rc.role_key = om.role
join contract_registry.capability_definitions cd
  on cd.capability_key = rc.capability_key;

grant select on contract_registry.v_organization_members_with_capabilities_v1 to authenticated;

commit;