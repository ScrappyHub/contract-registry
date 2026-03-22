-- =========================================================
-- CONTRACT REGISTRY — BOOTSTRAP 001
-- Deterministic bootstrap for validation
-- Safe to run repeatedly (idempotent where possible)
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Resolve current authenticated user
-- ---------------------------------------------------------

select auth.uid() as current_user;

-- ---------------------------------------------------------
-- 2) Create test organization
-- ---------------------------------------------------------

insert into contract_registry.organizations (
  id,
  org_key,
  title,
  description
)
values (
  gen_random_uuid(),
  'contract_registry_test_org',
  'Contract Registry Test Org',
  'Deterministic bootstrap organization'
)
on conflict (org_key)
do update set
  title = excluded.title
returning *;

-- ---------------------------------------------------------
-- 3) Add current user to organization
-- ---------------------------------------------------------

insert into contract_registry.organization_members (
  organization_id,
  user_id,
  role
)
select
  o.id,
  auth.uid(),
  'owner'
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org'
on conflict do nothing;

-- ---------------------------------------------------------
-- 4) Create billing account
-- ---------------------------------------------------------

select billing.create_account_v1(
  o.id,
  'trial'
)
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org';

-- ---------------------------------------------------------
-- 5) Enable baseline entitlements
-- ---------------------------------------------------------

select billing.upsert_entitlement_v1(
  o.id,
  'contract_registry.write',
  true,
  null
)
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org';

select billing.upsert_entitlement_v1(
  o.id,
  'contract_registry.release',
  true,
  null
)
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org';

select billing.upsert_entitlement_v1(
  o.id,
  'contract_registry.overlay.manage',
  true,
  null
)
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org';

select billing.upsert_entitlement_v1(
  o.id,
  'contract_registry.api.access',
  true,
  null
)
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org';

-- ---------------------------------------------------------
-- 6) Create example contract
-- ---------------------------------------------------------

insert into contract_registry.contracts (
  id,
  organization_id,
  contract_key,
  title,
  description,
  status,
  created_by,
  updated_by
)
select
  gen_random_uuid(),
  o.id,
  'example.contract.v1',
  'Example Contract',
  'Bootstrap validation contract',
  'active',
  auth.uid(),
  auth.uid()
from contract_registry.organizations o
where o.org_key = 'contract_registry_test_org'
on conflict (organization_id, contract_key)
do nothing;

-- ---------------------------------------------------------
-- 7) Create initial contract version
-- ---------------------------------------------------------

insert into contract_registry.contract_versions (
  id,
  contract_id,
  version_no,
  version_label,
  status,
  source_json_sha256,
  source_json_storage_path,
  created_by,
  updated_by
)
select
  gen_random_uuid(),
  c.id,
  1,
  'v1',
  'draft',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'contracts/example.contract.v1/source.json',
  auth.uid(),
  auth.uid()
from contract_registry.contracts c
where c.contract_key = 'example.contract.v1'
on conflict do nothing;

commit;