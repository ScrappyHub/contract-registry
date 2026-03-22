-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 001
-- Foundation: schemas + organizations + members + helpers + RLS
-- Canonical environment: Supabase Postgres
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Schemas
-- ---------------------------------------------------------
create schema if not exists contract_registry;
create schema if not exists contract_registry_private;

-- ---------------------------------------------------------
-- 2) Extensions
-- ---------------------------------------------------------
create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- 3) Core tables
-- ---------------------------------------------------------

create table if not exists contract_registry.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  is_active boolean not null default true,

  constraint contract_registry_organizations_slug_chk
    check (slug = lower(slug)),

  constraint contract_registry_organizations_slug_unique
    unique (slug)
);

create table if not exists contract_registry.organization_members (
  organization_id uuid not null,
  user_id uuid not null,
  role text not null,
  status text not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,

  constraint organization_members_pk
    primary key (organization_id, user_id),

  constraint organization_members_org_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint organization_members_role_chk
    check (role in ('owner','admin','editor','viewer','release_manager')),

  constraint organization_members_status_chk
    check (status in ('active','invited','suspended'))
);

-- ---------------------------------------------------------
-- 4) Indexes
-- ---------------------------------------------------------

create index if not exists organization_members_user_id_idx
  on contract_registry.organization_members(user_id);

create index if not exists organization_members_org_role_status_idx
  on contract_registry.organization_members(organization_id, role, status);

create index if not exists organizations_is_active_idx
  on contract_registry.organizations(is_active);

-- ---------------------------------------------------------
-- 5) Trigger helpers
-- ---------------------------------------------------------

create or replace function contract_registry_private.set_created_by_from_auth_uid_v1()
returns trigger
language plpgsql
security invoker
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'AUTH_CONTEXT_MISSING_SUB';
  end if;

  if tg_op = 'INSERT' then
    if new.created_by is null then
      new.created_by := v_uid;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_organizations_set_created_by_v1
  on contract_registry.organizations;

create trigger trg_organizations_set_created_by_v1
before insert on contract_registry.organizations
for each row
execute function contract_registry_private.set_created_by_from_auth_uid_v1();

drop trigger if exists trg_organization_members_set_created_by_v1
  on contract_registry.organization_members;

create trigger trg_organization_members_set_created_by_v1
before insert on contract_registry.organization_members
for each row
execute function contract_registry_private.set_created_by_from_auth_uid_v1();

-- ---------------------------------------------------------
-- 6) Auth / membership helpers
-- ---------------------------------------------------------

create or replace function contract_registry_private.auth_uid_required_v1()
returns uuid
language plpgsql
stable
security invoker
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();

  if v_uid is null then
    raise exception 'AUTH_CONTEXT_MISSING_SUB';
  end if;

  return v_uid;
end;
$$;

create or replace function contract_registry.user_org_roles_v1()
returns table (
  organization_id uuid,
  role text,
  status text
)
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    om.organization_id,
    om.role,
    om.status
  from contract_registry.organization_members om
  where om.user_id = auth.uid()
$$;

revoke all on function contract_registry.user_org_roles_v1() from public;
grant execute on function contract_registry.user_org_roles_v1() to authenticated;

create or replace function contract_registry.current_org_membership_v1(p_organization_id uuid)
returns table (
  organization_id uuid,
  role text,
  status text
)
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    om.organization_id,
    om.role,
    om.status
  from contract_registry.organization_members om
  where om.organization_id = p_organization_id
    and om.user_id = auth.uid()
$$;

revoke all on function contract_registry.current_org_membership_v1(uuid) from public;
grant execute on function contract_registry.current_org_membership_v1(uuid) to authenticated;

create or replace function contract_registry.user_has_org_role_v1(
  p_organization_id uuid,
  p_roles text[]
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
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
      and om.role = any(p_roles)
  )
$$;

revoke all on function contract_registry.user_has_org_role_v1(uuid, text[]) from public;
grant execute on function contract_registry.user_has_org_role_v1(uuid, text[]) to authenticated;

create or replace function contract_registry.user_is_org_member_v1(
  p_organization_id uuid
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
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
  )
$$;

revoke all on function contract_registry.user_is_org_member_v1(uuid) from public;
grant execute on function contract_registry.user_is_org_member_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 7) Table privileges
-- ---------------------------------------------------------

revoke all on schema contract_registry from public;
grant usage on schema contract_registry to authenticated;

revoke all on all tables in schema contract_registry from public;
revoke all on all functions in schema contract_registry from public;

grant select, insert, update, delete on contract_registry.organizations to authenticated;
grant select, insert, update, delete on contract_registry.organization_members to authenticated;

-- ---------------------------------------------------------
-- 8) Row Level Security
-- ---------------------------------------------------------

alter table contract_registry.organizations enable row level security;
alter table contract_registry.organizations force row level security;

alter table contract_registry.organization_members enable row level security;
alter table contract_registry.organization_members force row level security;

-- ---------------------------------------------------------
-- 9) RLS policies: organizations
-- ---------------------------------------------------------

drop policy if exists organizations_select_member_v1
  on contract_registry.organizations;

create policy organizations_select_member_v1
on contract_registry.organizations
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(id)
);

drop policy if exists organizations_insert_authenticated_v1
  on contract_registry.organizations;

create policy organizations_insert_authenticated_v1
on contract_registry.organizations
for insert
to authenticated
with check (
  auth.uid() is not null
);

drop policy if exists organizations_update_owner_admin_v1
  on contract_registry.organizations;

create policy organizations_update_owner_admin_v1
on contract_registry.organizations
for update
to authenticated
using (
  contract_registry.user_has_org_role_v1(id, array['owner','admin'])
)
with check (
  contract_registry.user_has_org_role_v1(id, array['owner','admin'])
);

drop policy if exists organizations_delete_owner_v1
  on contract_registry.organizations;

create policy organizations_delete_owner_v1
on contract_registry.organizations
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(id, array['owner'])
);

-- ---------------------------------------------------------
-- 10) RLS policies: organization_members
-- ---------------------------------------------------------

drop policy if exists organization_members_select_member_v1
  on contract_registry.organization_members;

create policy organization_members_select_member_v1
on contract_registry.organization_members
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists organization_members_insert_owner_admin_v1
  on contract_registry.organization_members;

create policy organization_members_insert_owner_admin_v1
on contract_registry.organization_members
for insert
to authenticated
with check (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
);

drop policy if exists organization_members_update_owner_admin_v1
  on contract_registry.organization_members;

create policy organization_members_update_owner_admin_v1
on contract_registry.organization_members
for update
to authenticated
using (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
)
with check (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
);

drop policy if exists organization_members_delete_owner_admin_v1
  on contract_registry.organization_members;

create policy organization_members_delete_owner_admin_v1
on contract_registry.organization_members
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
);

-- ---------------------------------------------------------
-- 11) Bootstrap helper: creator becomes owner
-- ---------------------------------------------------------
-- This function creates an organization and inserts the caller
-- as owner in one deterministic operation.

create or replace function contract_registry.create_organization_v1(
  p_slug text,
  p_name text
)
returns contract_registry.organizations
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org contract_registry.organizations;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  insert into contract_registry.organizations (
    slug,
    name,
    created_by
  )
  values (
    lower(trim(p_slug)),
    trim(p_name),
    v_uid
  )
  returning * into v_org;

  insert into contract_registry.organization_members (
    organization_id,
    user_id,
    role,
    status,
    created_by
  )
  values (
    v_org.id,
    v_uid,
    'owner',
    'active',
    v_uid
  );

  return v_org;
end;
$$;

revoke all on function contract_registry.create_organization_v1(text, text) from public;
grant execute on function contract_registry.create_organization_v1(text, text) to authenticated;

commit;