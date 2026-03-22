-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 011B
-- Plan presets + entitlement bundles + hosted tier law (fixed)
-- Replaces failed 011 attempt
-- Grounded to actual billing shape:
--   billing.accounts.organization_id
--   billing.subscriptions.account_id
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Plan registry
-- ---------------------------------------------------------

create table if not exists billing.plan_definitions (
  plan_key text primary key,
  title text not null,
  description text null,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),

  constraint billing_plan_definitions_key_chk
    check (length(btrim(plan_key)) > 0),

  constraint billing_plan_definitions_title_chk
    check (length(btrim(title)) > 0)
);

create index if not exists billing_plan_definitions_active_idx
  on billing.plan_definitions(is_active, sort_order);

insert into billing.plan_definitions (
  plan_key,
  title,
  description,
  is_active,
  sort_order
)
values
  ('trial', 'Trial', 'Initial hosted evaluation tier', true, 10),
  ('starter', 'Starter', 'Small team hosted tier', true, 20),
  ('pro', 'Pro', 'Full professional hosted tier', true, 30),
  ('business', 'Business', 'Expanded team/business hosted tier', true, 40),
  ('enterprise', 'Enterprise', 'High-trust enterprise hosted tier', true, 50)
on conflict (plan_key) do update
set
  title = excluded.title,
  description = excluded.description,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order;

-- ---------------------------------------------------------
-- 2) Plan entitlement presets
-- ---------------------------------------------------------

create table if not exists billing.plan_entitlement_presets (
  plan_key text not null references billing.plan_definitions(plan_key) on delete cascade,
  entitlement_key text not null,
  is_enabled boolean not null default true,
  limit_int integer null,
  created_at timestamptz not null default now(),
  primary key (plan_key, entitlement_key)
);

create index if not exists billing_plan_entitlement_presets_entitlement_idx
  on billing.plan_entitlement_presets(entitlement_key);

insert into billing.plan_entitlement_presets (
  plan_key,
  entitlement_key,
  is_enabled,
  limit_int
)
values
  ('trial', 'contract_registry.write', true, null),
  ('trial', 'contract_registry.release', true, null),
  ('trial', 'contract_registry.overlay.manage', false, null),
  ('trial', 'contract_registry.api.access', true, null),
  ('trial', 'contract_registry.audit.read', false, null),
  ('trial', 'contract_registry.team.invite', false, 1),
  ('trial', 'contract_registry.admin.console', false, null),
  ('trial', 'contract_registry.workbench.download', false, 1),

  ('starter', 'contract_registry.write', true, null),
  ('starter', 'contract_registry.release', true, null),
  ('starter', 'contract_registry.overlay.manage', true, null),
  ('starter', 'contract_registry.api.access', true, null),
  ('starter', 'contract_registry.audit.read', true, null),
  ('starter', 'contract_registry.team.invite', true, 3),
  ('starter', 'contract_registry.admin.console', false, null),
  ('starter', 'contract_registry.workbench.download', true, 3),

  ('pro', 'contract_registry.write', true, null),
  ('pro', 'contract_registry.release', true, null),
  ('pro', 'contract_registry.overlay.manage', true, null),
  ('pro', 'contract_registry.api.access', true, null),
  ('pro', 'contract_registry.audit.read', true, null),
  ('pro', 'contract_registry.team.invite', true, 10),
  ('pro', 'contract_registry.admin.console', true, null),
  ('pro', 'contract_registry.workbench.download', true, 10),

  ('business', 'contract_registry.write', true, null),
  ('business', 'contract_registry.release', true, null),
  ('business', 'contract_registry.overlay.manage', true, null),
  ('business', 'contract_registry.api.access', true, null),
  ('business', 'contract_registry.audit.read', true, null),
  ('business', 'contract_registry.team.invite', true, 50),
  ('business', 'contract_registry.admin.console', true, null),
  ('business', 'contract_registry.workbench.download', true, 50),

  ('enterprise', 'contract_registry.write', true, null),
  ('enterprise', 'contract_registry.release', true, null),
  ('enterprise', 'contract_registry.overlay.manage', true, null),
  ('enterprise', 'contract_registry.api.access', true, null),
  ('enterprise', 'contract_registry.audit.read', true, null),
  ('enterprise', 'contract_registry.team.invite', true, 500),
  ('enterprise', 'contract_registry.admin.console', true, null),
  ('enterprise', 'contract_registry.workbench.download', true, 500)
on conflict (plan_key, entitlement_key) do update
set
  is_enabled = excluded.is_enabled,
  limit_int = excluded.limit_int;

-- ---------------------------------------------------------
-- 3) Plan limit presets
-- ---------------------------------------------------------

create table if not exists billing.plan_limit_presets (
  plan_key text not null references billing.plan_definitions(plan_key) on delete cascade,
  limit_key text not null,
  limit_int integer not null,
  created_at timestamptz not null default now(),
  primary key (plan_key, limit_key),

  constraint billing_plan_limit_presets_limit_key_chk
    check (length(btrim(limit_key)) > 0),

  constraint billing_plan_limit_presets_limit_int_chk
    check (limit_int >= 0)
);

insert into billing.plan_limit_presets (
  plan_key,
  limit_key,
  limit_int
)
values
  ('trial', 'contracts.max', 3),
  ('trial', 'contract_versions.max_per_contract', 10),
  ('trial', 'releases.max_per_month', 20),
  ('trial', 'members.max', 1),
  ('trial', 'overlay_profiles.max', 0),
  ('trial', 'storage_mb.max', 250),

  ('starter', 'contracts.max', 25),
  ('starter', 'contract_versions.max_per_contract', 50),
  ('starter', 'releases.max_per_month', 100),
  ('starter', 'members.max', 3),
  ('starter', 'overlay_profiles.max', 10),
  ('starter', 'storage_mb.max', 2048),

  ('pro', 'contracts.max', 250),
  ('pro', 'contract_versions.max_per_contract', 250),
  ('pro', 'releases.max_per_month', 1000),
  ('pro', 'members.max', 10),
  ('pro', 'overlay_profiles.max', 50),
  ('pro', 'storage_mb.max', 10240),

  ('business', 'contracts.max', 2500),
  ('business', 'contract_versions.max_per_contract', 1000),
  ('business', 'releases.max_per_month', 5000),
  ('business', 'members.max', 50),
  ('business', 'overlay_profiles.max', 250),
  ('business', 'storage_mb.max', 51200),

  ('enterprise', 'contracts.max', 50000),
  ('enterprise', 'contract_versions.max_per_contract', 5000),
  ('enterprise', 'releases.max_per_month', 50000),
  ('enterprise', 'members.max', 500),
  ('enterprise', 'overlay_profiles.max', 5000),
  ('enterprise', 'storage_mb.max', 512000)
on conflict (plan_key, limit_key) do update
set
  limit_int = excluded.limit_int;

-- ---------------------------------------------------------
-- 4) Helper: organization -> plan key
-- Grounded to actual shape:
--   accounts.organization_id
--   subscriptions.account_id
-- ---------------------------------------------------------

create or replace function billing.organization_plan_key_v1(
  p_organization_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select coalesce(
    (
      select s.plan_key
      from billing.accounts a
      join billing.subscriptions s
        on s.account_id = a.id
      where a.organization_id = p_organization_id
        and s.status in ('trialing','active','past_due')
      order by s.created_at desc
      limit 1
    ),
    (
      select case
        when a.billing_state = 'trial' then 'trial'
        when a.billing_state = 'starter' then 'starter'
        when a.billing_state = 'pro' then 'pro'
        when a.billing_state = 'business' then 'business'
        when a.billing_state = 'enterprise' then 'enterprise'
        else null
      end
      from billing.accounts a
      where a.organization_id = p_organization_id
      limit 1
    )
  )
$$;

revoke all on function billing.organization_plan_key_v1(uuid) from public;
grant execute on function billing.organization_plan_key_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5) Plan helpers
-- ---------------------------------------------------------

create or replace function billing.plan_entitlement_enabled_v1(
  p_plan_key text,
  p_entitlement_key text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select coalesce(
    (
      select pep.is_enabled
      from billing.plan_entitlement_presets pep
      where pep.plan_key = trim(p_plan_key)
        and pep.entitlement_key = trim(p_entitlement_key)
    ),
    false
  )
$$;

revoke all on function billing.plan_entitlement_enabled_v1(text, text) from public;
grant execute on function billing.plan_entitlement_enabled_v1(text, text) to authenticated;

create or replace function billing.plan_entitlement_limit_v1(
  p_plan_key text,
  p_entitlement_key text
)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select pep.limit_int
  from billing.plan_entitlement_presets pep
  where pep.plan_key = trim(p_plan_key)
    and pep.entitlement_key = trim(p_entitlement_key)
$$;

revoke all on function billing.plan_entitlement_limit_v1(text, text) from public;
grant execute on function billing.plan_entitlement_limit_v1(text, text) to authenticated;

create or replace function billing.plan_limit_value_v1(
  p_plan_key text,
  p_limit_key text
)
returns integer
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select plp.limit_int
  from billing.plan_limit_presets plp
  where plp.plan_key = trim(p_plan_key)
    and plp.limit_key = trim(p_limit_key)
$$;

revoke all on function billing.plan_limit_value_v1(text, text) from public;
grant execute on function billing.plan_limit_value_v1(text, text) to authenticated;

-- ---------------------------------------------------------
-- 6) Sync account entitlements from plan
-- ---------------------------------------------------------

create or replace function billing.apply_plan_presets_to_account_v1(
  p_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, billing
as $$
declare
  v_account_id uuid;
  v_plan_key text;
  v_row record;
begin
  select a.id
    into v_account_id
  from billing.accounts a
  where a.organization_id = p_organization_id;

  if v_account_id is null then
    raise exception 'BILLING_ACCOUNT_NOT_FOUND';
  end if;

  v_plan_key := billing.organization_plan_key_v1(p_organization_id);

  if v_plan_key is null then
    raise exception 'PLAN_KEY_NOT_FOUND';
  end if;

  for v_row in
    select pep.entitlement_key, pep.is_enabled, pep.limit_int
    from billing.plan_entitlement_presets pep
    where pep.plan_key = v_plan_key
  loop
    insert into billing.entitlements (
      account_id,
      entitlement_key,
      is_enabled,
      limit_int
    )
    values (
      v_account_id,
      v_row.entitlement_key,
      v_row.is_enabled,
      v_row.limit_int
    )
    on conflict (account_id, entitlement_key) do update
    set
      is_enabled = excluded.is_enabled,
      limit_int = excluded.limit_int,
      updated_at = now();
  end loop;
end;
$$;

revoke all on function billing.apply_plan_presets_to_account_v1(uuid) from public;
grant execute on function billing.apply_plan_presets_to_account_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Views
-- ---------------------------------------------------------

create or replace view billing.v_plan_entitlement_presets_v1 as
select
  pd.plan_key,
  pd.title as plan_title,
  pep.entitlement_key,
  pep.is_enabled,
  pep.limit_int
from billing.plan_definitions pd
join billing.plan_entitlement_presets pep
  on pep.plan_key = pd.plan_key
where pd.is_active = true
order by pd.sort_order, pep.entitlement_key;

grant select on billing.v_plan_entitlement_presets_v1 to authenticated;

create or replace view billing.v_plan_limit_presets_v1 as
select
  pd.plan_key,
  pd.title as plan_title,
  plp.limit_key,
  plp.limit_int
from billing.plan_definitions pd
join billing.plan_limit_presets plp
  on plp.plan_key = pd.plan_key
where pd.is_active = true
order by pd.sort_order, plp.limit_key;

grant select on billing.v_plan_limit_presets_v1 to authenticated;

create or replace view billing.v_organization_plan_summary_v1 as
select
  o.id as organization_id,
  o.slug,
  billing.organization_plan_key_v1(o.id) as plan_key,
  pd.title as plan_title,
  pd.description as plan_description
from contract_registry.organizations o
left join billing.plan_definitions pd
  on pd.plan_key = billing.organization_plan_key_v1(o.id);

grant select on billing.v_organization_plan_summary_v1 to authenticated;

commit;