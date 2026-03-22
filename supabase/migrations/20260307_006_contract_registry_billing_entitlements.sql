-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 006
-- Billing + entitlements:
--   billing schema
--   accounts
--   subscriptions
--   entitlements
--   entitlement helpers
--   release/write gating helpers
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
--   005_contract_registry_release_artifacts.sql
-- Rooted-style posture:
--   hosted control-plane only
--   entitlement checks explicit
--   no hidden product logic
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Billing schema
-- ---------------------------------------------------------

create schema if not exists billing;

revoke all on schema billing from public;
grant usage on schema billing to authenticated;

-- ---------------------------------------------------------
-- 2) Billing tables
-- ---------------------------------------------------------

create table if not exists billing.accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique,
  billing_state text not null,
  created_at timestamptz not null default now(),

  constraint billing_accounts_organization_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint billing_accounts_state_chk
    check (billing_state in ('trial','active','past_due','cancelled'))
);

create table if not exists billing.subscriptions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null,
  provider text not null,
  provider_customer_id text null,
  provider_subscription_id text null,
  plan_key text not null,
  status text not null,
  period_start timestamptz null,
  period_end timestamptz null,
  created_at timestamptz not null default now(),

  constraint billing_subscriptions_account_fk
    foreign key (account_id)
    references billing.accounts(id)
    on delete cascade,

  constraint billing_subscriptions_provider_chk
    check (length(btrim(provider)) > 0),

  constraint billing_subscriptions_plan_key_chk
    check (length(btrim(plan_key)) > 0),

  constraint billing_subscriptions_status_chk
    check (status in ('trialing','active','past_due','cancelled','incomplete','incomplete_expired'))
);

create table if not exists billing.entitlements (
  account_id uuid not null,
  entitlement_key text not null,
  is_enabled boolean not null,
  limit_int integer null,
  updated_at timestamptz not null default now(),

  constraint billing_entitlements_pk
    primary key (account_id, entitlement_key),

  constraint billing_entitlements_account_fk
    foreign key (account_id)
    references billing.accounts(id)
    on delete cascade,

  constraint billing_entitlements_key_chk
    check (length(btrim(entitlement_key)) > 0),

  constraint billing_entitlements_limit_chk
    check (limit_int is null or limit_int >= 0)
);

-- ---------------------------------------------------------
-- 3) Indexes
-- ---------------------------------------------------------

create index if not exists billing_accounts_billing_state_idx
  on billing.accounts(billing_state);

create index if not exists billing_subscriptions_account_created_at_idx
  on billing.subscriptions(account_id, created_at desc);

create index if not exists billing_subscriptions_status_idx
  on billing.subscriptions(status);

create index if not exists billing_entitlements_enabled_idx
  on billing.entitlements(account_id, is_enabled);

-- ---------------------------------------------------------
-- 4) Updated-at trigger helper for billing.entitlements
-- ---------------------------------------------------------

create or replace function contract_registry_private.set_updated_at_only_v1()
returns trigger
language plpgsql
security invoker
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_billing_entitlements_set_updated_at_v1
  on billing.entitlements;

create trigger trg_billing_entitlements_set_updated_at_v1
before update on billing.entitlements
for each row
execute function contract_registry_private.set_updated_at_only_v1();

-- ---------------------------------------------------------
-- 5) Billing helper functions
-- ---------------------------------------------------------

create or replace function billing.account_org_id_v1(
  p_account_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, billing, contract_registry
as $$
  select a.organization_id
  from billing.accounts a
  where a.id = p_account_id
$$;

revoke all on function billing.account_org_id_v1(uuid) from public;
grant execute on function billing.account_org_id_v1(uuid) to authenticated;

create or replace function billing.account_id_by_org_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select a.id
  from billing.accounts a
  where a.organization_id = p_organization_id
$$;

revoke all on function billing.account_id_by_org_v1(uuid) from public;
grant execute on function billing.account_id_by_org_v1(uuid) to authenticated;

create or replace function billing.user_can_manage_billing_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_org_role_v1(
    p_organization_id,
    array['owner','admin']
  )
$$;

revoke all on function billing.user_can_manage_billing_v1(uuid) from public;
grant execute on function billing.user_can_manage_billing_v1(uuid) to authenticated;

create or replace function billing.account_is_in_good_standing_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select exists (
    select 1
    from billing.accounts a
    where a.organization_id = p_organization_id
      and a.billing_state in ('trial','active')
  )
$$;

revoke all on function billing.account_is_in_good_standing_v1(uuid) from public;
grant execute on function billing.account_is_in_good_standing_v1(uuid) to authenticated;

create or replace function billing.entitlement_enabled_v1(
  p_organization_id uuid,
  p_entitlement_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select coalesce((
    select e.is_enabled
    from billing.accounts a
    join billing.entitlements e
      on e.account_id = a.id
    where a.organization_id = p_organization_id
      and e.entitlement_key = p_entitlement_key
    limit 1
  ), false)
$$;

revoke all on function billing.entitlement_enabled_v1(uuid, text) from public;
grant execute on function billing.entitlement_enabled_v1(uuid, text) to authenticated;

create or replace function billing.entitlement_limit_v1(
  p_organization_id uuid,
  p_entitlement_key text
)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select (
    select e.limit_int
    from billing.accounts a
    join billing.entitlements e
      on e.account_id = a.id
    where a.organization_id = p_organization_id
      and e.entitlement_key = p_entitlement_key
    limit 1
  )
$$;

revoke all on function billing.entitlement_limit_v1(uuid, text) from public;
grant execute on function billing.entitlement_limit_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 6) Contract Registry gating helpers (billing-aware)
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_write_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.user_can_write_v1(p_organization_id)
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.write')
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
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.user_can_release_v1(p_organization_id)
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.release')
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
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.user_can_manage_overlays_v1(p_organization_id)
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.overlay.manage')
$$;

revoke all on function contract_registry.user_can_manage_overlays_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_overlays_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_api_access_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.user_is_org_member_v1(p_organization_id)
    and billing.account_is_in_good_standing_v1(p_organization_id)
    and billing.entitlement_enabled_v1(p_organization_id, 'contract_registry.api.access')
$$;

revoke all on function contract_registry.user_can_api_access_v1(uuid) from public;
grant execute on function contract_registry.user_can_api_access_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Bootstrap helper: create billing account
-- ---------------------------------------------------------

create or replace function billing.create_account_v1(
  p_organization_id uuid,
  p_billing_state text default 'trial'
)
returns billing.accounts
language plpgsql
security definer
set search_path = pg_catalog, public, billing, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_row billing.accounts;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if p_billing_state not in ('trial','active','past_due','cancelled') then
    raise exception 'INVALID_BILLING_STATE';
  end if;

  if not billing.user_can_manage_billing_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_BILLING_MANAGE';
  end if;

  insert into billing.accounts (
    organization_id,
    billing_state
  )
  values (
    p_organization_id,
    p_billing_state
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function billing.create_account_v1(uuid, text) from public;
grant execute on function billing.create_account_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 8) Bootstrap helper: upsert entitlement
-- ---------------------------------------------------------

create or replace function billing.upsert_entitlement_v1(
  p_organization_id uuid,
  p_entitlement_key text,
  p_is_enabled boolean,
  p_limit_int integer default null
)
returns billing.entitlements
language plpgsql
security definer
set search_path = pg_catalog, public, billing, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_account_id uuid;
  v_row billing.entitlements;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not billing.user_can_manage_billing_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_BILLING_MANAGE';
  end if;

  v_account_id := billing.account_id_by_org_v1(p_organization_id);

  if v_account_id is null then
    raise exception 'BILLING_ACCOUNT_NOT_FOUND';
  end if;

  insert into billing.entitlements (
    account_id,
    entitlement_key,
    is_enabled,
    limit_int
  )
  values (
    v_account_id,
    trim(p_entitlement_key),
    p_is_enabled,
    p_limit_int
  )
  on conflict (account_id, entitlement_key)
  do update set
    is_enabled = excluded.is_enabled,
    limit_int = excluded.limit_int,
    updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function billing.upsert_entitlement_v1(uuid, text, boolean, integer) from public;
grant execute on function billing.upsert_entitlement_v1(uuid, text, boolean, integer) to authenticated;

-- ---------------------------------------------------------
-- 9) Privileges
-- ---------------------------------------------------------

revoke all on all tables in schema billing from public;
revoke all on all functions in schema billing from public;

grant select, insert, update, delete on billing.accounts to authenticated;
grant select, insert, update, delete on billing.subscriptions to authenticated;
grant select, insert, update, delete on billing.entitlements to authenticated;

-- ---------------------------------------------------------
-- 10) RLS
-- ---------------------------------------------------------

alter table billing.accounts enable row level security;
alter table billing.accounts force row level security;

alter table billing.subscriptions enable row level security;
alter table billing.subscriptions force row level security;

alter table billing.entitlements enable row level security;
alter table billing.entitlements force row level security;

-- ---------------------------------------------------------
-- 11) RLS policies: billing.accounts
-- ---------------------------------------------------------

drop policy if exists billing_accounts_select_member_v1
  on billing.accounts;

create policy billing_accounts_select_member_v1
on billing.accounts
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists billing_accounts_insert_owner_admin_v1
  on billing.accounts;

create policy billing_accounts_insert_owner_admin_v1
on billing.accounts
for insert
to authenticated
with check (
  billing.user_can_manage_billing_v1(organization_id)
);

drop policy if exists billing_accounts_update_owner_admin_v1
  on billing.accounts;

create policy billing_accounts_update_owner_admin_v1
on billing.accounts
for update
to authenticated
using (
  billing.user_can_manage_billing_v1(organization_id)
)
with check (
  billing.user_can_manage_billing_v1(organization_id)
);

drop policy if exists billing_accounts_delete_owner_v1
  on billing.accounts;

create policy billing_accounts_delete_owner_v1
on billing.accounts
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(organization_id, array['owner'])
);

-- ---------------------------------------------------------
-- 12) RLS policies: billing.subscriptions
-- ---------------------------------------------------------

drop policy if exists billing_subscriptions_select_member_v1
  on billing.subscriptions;

create policy billing_subscriptions_select_member_v1
on billing.subscriptions
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_subscriptions_insert_owner_admin_v1
  on billing.subscriptions;

create policy billing_subscriptions_insert_owner_admin_v1
on billing.subscriptions
for insert
to authenticated
with check (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_subscriptions_update_owner_admin_v1
  on billing.subscriptions;

create policy billing_subscriptions_update_owner_admin_v1
on billing.subscriptions
for update
to authenticated
using (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
)
with check (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_subscriptions_delete_owner_admin_v1
  on billing.subscriptions;

create policy billing_subscriptions_delete_owner_admin_v1
on billing.subscriptions
for delete
to authenticated
using (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

-- ---------------------------------------------------------
-- 13) RLS policies: billing.entitlements
-- ---------------------------------------------------------

drop policy if exists billing_entitlements_select_member_v1
  on billing.entitlements;

create policy billing_entitlements_select_member_v1
on billing.entitlements
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_entitlements_insert_owner_admin_v1
  on billing.entitlements;

create policy billing_entitlements_insert_owner_admin_v1
on billing.entitlements
for insert
to authenticated
with check (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_entitlements_update_owner_admin_v1
  on billing.entitlements;

create policy billing_entitlements_update_owner_admin_v1
on billing.entitlements
for update
to authenticated
using (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
)
with check (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

drop policy if exists billing_entitlements_delete_owner_admin_v1
  on billing.entitlements;

create policy billing_entitlements_delete_owner_admin_v1
on billing.entitlements
for delete
to authenticated
using (
  billing.user_can_manage_billing_v1(
    billing.account_org_id_v1(account_id)
  )
);

commit;