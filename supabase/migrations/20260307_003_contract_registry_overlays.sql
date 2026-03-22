-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 003
-- Overlays:
--   policy_overlay_profiles
--   schema_overlay_profiles
--   contract_release_overlay_bindings
--   helper functions
--   RLS
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
-- Rooted-style posture:
--   explicit schema ownership
--   simple helper functions
--   minimal guessed abstraction
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Overlay profile tables
-- ---------------------------------------------------------

create table if not exists contract_registry.policy_overlay_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  overlay_key text not null,
  title text not null,
  description text null,
  overlay_storage_path text not null,
  overlay_sha256 text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null,

  constraint policy_overlay_profiles_org_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint policy_overlay_profiles_overlay_key_chk
    check (
      overlay_key = lower(overlay_key)
      and length(btrim(overlay_key)) > 0
    ),

  constraint policy_overlay_profiles_overlay_sha256_chk
    check (overlay_sha256 ~ '^[0-9a-f]{64}$'),

  constraint policy_overlay_profiles_overlay_storage_path_chk
    check (length(btrim(overlay_storage_path)) > 0),

  constraint policy_overlay_profiles_org_overlay_key_unique
    unique (organization_id, overlay_key)
);

create table if not exists contract_registry.schema_overlay_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  overlay_key text not null,
  title text not null,
  description text null,
  overlay_storage_path text not null,
  overlay_sha256 text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null,

  constraint schema_overlay_profiles_org_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint schema_overlay_profiles_overlay_key_chk
    check (
      overlay_key = lower(overlay_key)
      and length(btrim(overlay_key)) > 0
    ),

  constraint schema_overlay_profiles_overlay_sha256_chk
    check (overlay_sha256 ~ '^[0-9a-f]{64}$'),

  constraint schema_overlay_profiles_overlay_storage_path_chk
    check (length(btrim(overlay_storage_path)) > 0),

  constraint schema_overlay_profiles_org_overlay_key_unique
    unique (organization_id, overlay_key)
);

-- ---------------------------------------------------------
-- 2) Release overlay binding table
-- NOTE:
-- release table does not exist yet (Migration 005),
-- so we create this table now without FK to releases.
-- We add the FK later once contract_releases exists.
-- ---------------------------------------------------------

create table if not exists contract_registry.contract_release_overlay_bindings (
  release_id uuid primary key,
  policy_overlay_profile_id uuid null,
  schema_overlay_profile_id uuid null,
  bound_policy_overlay_sha256 text null,
  bound_schema_overlay_sha256 text null,
  created_at timestamptz not null default now(),

  constraint contract_release_overlay_bindings_policy_overlay_fk
    foreign key (policy_overlay_profile_id)
    references contract_registry.policy_overlay_profiles(id)
    on delete set null,

  constraint contract_release_overlay_bindings_schema_overlay_fk
    foreign key (schema_overlay_profile_id)
    references contract_registry.schema_overlay_profiles(id)
    on delete set null,

  constraint contract_release_overlay_bindings_bound_policy_overlay_sha256_chk
    check (
      bound_policy_overlay_sha256 is null
      or bound_policy_overlay_sha256 ~ '^[0-9a-f]{64}$'
    ),

  constraint contract_release_overlay_bindings_bound_schema_overlay_sha256_chk
    check (
      bound_schema_overlay_sha256 is null
      or bound_schema_overlay_sha256 ~ '^[0-9a-f]{64}$'
    )
);

-- ---------------------------------------------------------
-- 3) Indexes
-- ---------------------------------------------------------

create index if not exists policy_overlay_profiles_org_active_idx
  on contract_registry.policy_overlay_profiles(organization_id, is_active);

create index if not exists policy_overlay_profiles_org_updated_at_idx
  on contract_registry.policy_overlay_profiles(organization_id, updated_at desc);

create index if not exists schema_overlay_profiles_org_active_idx
  on contract_registry.schema_overlay_profiles(organization_id, is_active);

create index if not exists schema_overlay_profiles_org_updated_at_idx
  on contract_registry.schema_overlay_profiles(organization_id, updated_at desc);

create index if not exists contract_release_overlay_bindings_policy_idx
  on contract_registry.contract_release_overlay_bindings(policy_overlay_profile_id);

create index if not exists contract_release_overlay_bindings_schema_idx
  on contract_registry.contract_release_overlay_bindings(schema_overlay_profile_id);

-- ---------------------------------------------------------
-- 4) Triggers for created_by / updated_by / updated_at
-- Reuse helpers from Migration 002
-- ---------------------------------------------------------

drop trigger if exists trg_policy_overlay_profiles_set_created_updated_by_v1
  on contract_registry.policy_overlay_profiles;

create trigger trg_policy_overlay_profiles_set_created_updated_by_v1
before insert or update on contract_registry.policy_overlay_profiles
for each row
execute function contract_registry_private.set_created_by_updated_by_from_auth_uid_v1();

drop trigger if exists trg_policy_overlay_profiles_set_updated_at_v1
  on contract_registry.policy_overlay_profiles;

create trigger trg_policy_overlay_profiles_set_updated_at_v1
before update on contract_registry.policy_overlay_profiles
for each row
execute function contract_registry_private.set_updated_at_v1();

drop trigger if exists trg_schema_overlay_profiles_set_created_updated_by_v1
  on contract_registry.schema_overlay_profiles;

create trigger trg_schema_overlay_profiles_set_created_updated_by_v1
before insert or update on contract_registry.schema_overlay_profiles
for each row
execute function contract_registry_private.set_created_by_updated_by_from_auth_uid_v1();

drop trigger if exists trg_schema_overlay_profiles_set_updated_at_v1
  on contract_registry.schema_overlay_profiles;

create trigger trg_schema_overlay_profiles_set_updated_at_v1
before update on contract_registry.schema_overlay_profiles
for each row
execute function contract_registry_private.set_updated_at_v1();

-- ---------------------------------------------------------
-- 5) Helper functions
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_manage_overlays_v1(
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

revoke all on function contract_registry.user_can_manage_overlays_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_overlays_v1(uuid) to authenticated;

create or replace function contract_registry.policy_overlay_org_id_v1(
  p_policy_overlay_profile_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select p.organization_id
  from contract_registry.policy_overlay_profiles p
  where p.id = p_policy_overlay_profile_id
$$;

revoke all on function contract_registry.policy_overlay_org_id_v1(uuid) from public;
grant execute on function contract_registry.policy_overlay_org_id_v1(uuid) to authenticated;

create or replace function contract_registry.schema_overlay_org_id_v1(
  p_schema_overlay_profile_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select s.organization_id
  from contract_registry.schema_overlay_profiles s
  where s.id = p_schema_overlay_profile_id
$$;

revoke all on function contract_registry.schema_overlay_org_id_v1(uuid) from public;
grant execute on function contract_registry.schema_overlay_org_id_v1(uuid) to authenticated;

create or replace function contract_registry.overlay_binding_org_id_v1(
  p_release_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select coalesce(
    (
      select p.organization_id
      from contract_registry.contract_release_overlay_bindings b
      join contract_registry.policy_overlay_profiles p
        on p.id = b.policy_overlay_profile_id
      where b.release_id = p_release_id
      limit 1
    ),
    (
      select s.organization_id
      from contract_registry.contract_release_overlay_bindings b
      join contract_registry.schema_overlay_profiles s
        on s.id = b.schema_overlay_profile_id
      where b.release_id = p_release_id
      limit 1
    )
  )
$$;

revoke all on function contract_registry.overlay_binding_org_id_v1(uuid) from public;
grant execute on function contract_registry.overlay_binding_org_id_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 6) Integrity trigger:
-- if both overlay profiles are supplied, they must belong to same org
-- if bound hash exists, matching profile id should normally exist too
-- ---------------------------------------------------------

create or replace function contract_registry_private.enforce_overlay_binding_integrity_v1()
returns trigger
language plpgsql
security invoker
as $$
declare
  v_policy_org uuid;
  v_schema_org uuid;
begin
  if new.policy_overlay_profile_id is not null then
    select p.organization_id
      into v_policy_org
    from contract_registry.policy_overlay_profiles p
    where p.id = new.policy_overlay_profile_id;

    if v_policy_org is null then
      raise exception 'POLICY_OVERLAY_PROFILE_NOT_FOUND';
    end if;
  end if;

  if new.schema_overlay_profile_id is not null then
    select s.organization_id
      into v_schema_org
    from contract_registry.schema_overlay_profiles s
    where s.id = new.schema_overlay_profile_id;

    if v_schema_org is null then
      raise exception 'SCHEMA_OVERLAY_PROFILE_NOT_FOUND';
    end if;
  end if;

  if new.policy_overlay_profile_id is not null
     and new.schema_overlay_profile_id is not null
     and v_policy_org <> v_schema_org then
    raise exception 'OVERLAY_PROFILE_ORG_MISMATCH';
  end if;

  if new.bound_policy_overlay_sha256 is not null
     and new.policy_overlay_profile_id is null then
    raise exception 'BOUND_POLICY_HASH_WITHOUT_PROFILE';
  end if;

  if new.bound_schema_overlay_sha256 is not null
     and new.schema_overlay_profile_id is null then
    raise exception 'BOUND_SCHEMA_HASH_WITHOUT_PROFILE';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contract_release_overlay_bindings_integrity_v1
  on contract_registry.contract_release_overlay_bindings;

create trigger trg_contract_release_overlay_bindings_integrity_v1
before insert or update on contract_registry.contract_release_overlay_bindings
for each row
execute function contract_registry_private.enforce_overlay_binding_integrity_v1();

-- ---------------------------------------------------------
-- 7) Privileges
-- ---------------------------------------------------------

grant select, insert, update, delete on contract_registry.policy_overlay_profiles to authenticated;
grant select, insert, update, delete on contract_registry.schema_overlay_profiles to authenticated;
grant select, insert, update, delete on contract_registry.contract_release_overlay_bindings to authenticated;

-- ---------------------------------------------------------
-- 8) RLS
-- ---------------------------------------------------------

alter table contract_registry.policy_overlay_profiles enable row level security;
alter table contract_registry.policy_overlay_profiles force row level security;

alter table contract_registry.schema_overlay_profiles enable row level security;
alter table contract_registry.schema_overlay_profiles force row level security;

alter table contract_registry.contract_release_overlay_bindings enable row level security;
alter table contract_registry.contract_release_overlay_bindings force row level security;

-- ---------------------------------------------------------
-- 9) RLS policies: policy_overlay_profiles
-- ---------------------------------------------------------

drop policy if exists policy_overlay_profiles_select_member_v1
  on contract_registry.policy_overlay_profiles;

create policy policy_overlay_profiles_select_member_v1
on contract_registry.policy_overlay_profiles
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists policy_overlay_profiles_insert_admin_v1
  on contract_registry.policy_overlay_profiles;

create policy policy_overlay_profiles_insert_admin_v1
on contract_registry.policy_overlay_profiles
for insert
to authenticated
with check (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

drop policy if exists policy_overlay_profiles_update_admin_v1
  on contract_registry.policy_overlay_profiles;

create policy policy_overlay_profiles_update_admin_v1
on contract_registry.policy_overlay_profiles
for update
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(organization_id)
)
with check (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

drop policy if exists policy_overlay_profiles_delete_admin_v1
  on contract_registry.policy_overlay_profiles;

create policy policy_overlay_profiles_delete_admin_v1
on contract_registry.policy_overlay_profiles
for delete
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

-- ---------------------------------------------------------
-- 10) RLS policies: schema_overlay_profiles
-- ---------------------------------------------------------

drop policy if exists schema_overlay_profiles_select_member_v1
  on contract_registry.schema_overlay_profiles;

create policy schema_overlay_profiles_select_member_v1
on contract_registry.schema_overlay_profiles
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists schema_overlay_profiles_insert_admin_v1
  on contract_registry.schema_overlay_profiles;

create policy schema_overlay_profiles_insert_admin_v1
on contract_registry.schema_overlay_profiles
for insert
to authenticated
with check (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

drop policy if exists schema_overlay_profiles_update_admin_v1
  on contract_registry.schema_overlay_profiles;

create policy schema_overlay_profiles_update_admin_v1
on contract_registry.schema_overlay_profiles
for update
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(organization_id)
)
with check (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

drop policy if exists schema_overlay_profiles_delete_admin_v1
  on contract_registry.schema_overlay_profiles;

create policy schema_overlay_profiles_delete_admin_v1
on contract_registry.schema_overlay_profiles
for delete
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(organization_id)
);

-- ---------------------------------------------------------
-- 11) RLS policies: contract_release_overlay_bindings
-- Since releases table is not present yet, we gate by overlay org lookup
-- via the bound overlay profiles.
-- Later migrations can tighten/replace these once releases exist.
-- ---------------------------------------------------------

drop policy if exists contract_release_overlay_bindings_select_member_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_select_member_v1
on contract_registry.contract_release_overlay_bindings
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.overlay_binding_org_id_v1(release_id)
  )
);

drop policy if exists contract_release_overlay_bindings_insert_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_insert_admin_v1
on contract_registry.contract_release_overlay_bindings
for insert
to authenticated
with check (
  contract_registry.user_can_manage_overlays_v1(
    coalesce(
      contract_registry.policy_overlay_org_id_v1(policy_overlay_profile_id),
      contract_registry.schema_overlay_org_id_v1(schema_overlay_profile_id)
    )
  )
);

drop policy if exists contract_release_overlay_bindings_update_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_update_admin_v1
on contract_registry.contract_release_overlay_bindings
for update
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(
    contract_registry.overlay_binding_org_id_v1(release_id)
  )
)
with check (
  contract_registry.user_can_manage_overlays_v1(
    coalesce(
      contract_registry.policy_overlay_org_id_v1(policy_overlay_profile_id),
      contract_registry.schema_overlay_org_id_v1(schema_overlay_profile_id)
    )
  )
);

drop policy if exists contract_release_overlay_bindings_delete_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_delete_admin_v1
on contract_registry.contract_release_overlay_bindings
for delete
to authenticated
using (
  contract_registry.user_can_manage_overlays_v1(
    contract_registry.overlay_binding_org_id_v1(release_id)
  )
);

-- ---------------------------------------------------------
-- 12) Bootstrap helpers
-- ---------------------------------------------------------

create or replace function contract_registry.create_policy_overlay_profile_v1(
  p_organization_id uuid,
  p_overlay_key text,
  p_title text,
  p_overlay_storage_path text,
  p_overlay_sha256 text,
  p_description text default null
)
returns contract_registry.policy_overlay_profiles
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_row contract_registry.policy_overlay_profiles;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not contract_registry.user_can_manage_overlays_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_OVERLAY_MANAGE';
  end if;

  insert into contract_registry.policy_overlay_profiles (
    organization_id,
    overlay_key,
    title,
    description,
    overlay_storage_path,
    overlay_sha256,
    is_active,
    created_by,
    updated_by
  )
  values (
    p_organization_id,
    lower(trim(p_overlay_key)),
    trim(p_title),
    p_description,
    trim(p_overlay_storage_path),
    lower(trim(p_overlay_sha256)),
    true,
    v_uid,
    v_uid
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.create_policy_overlay_profile_v1(uuid, text, text, text, text, text) from public;
grant execute on function contract_registry.create_policy_overlay_profile_v1(uuid, text, text, text, text, text) to authenticated;

create or replace function contract_registry.create_schema_overlay_profile_v1(
  p_organization_id uuid,
  p_overlay_key text,
  p_title text,
  p_overlay_storage_path text,
  p_overlay_sha256 text,
  p_description text default null
)
returns contract_registry.schema_overlay_profiles
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_row contract_registry.schema_overlay_profiles;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not contract_registry.user_can_manage_overlays_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_OVERLAY_MANAGE';
  end if;

  insert into contract_registry.schema_overlay_profiles (
    organization_id,
    overlay_key,
    title,
    description,
    overlay_storage_path,
    overlay_sha256,
    is_active,
    created_by,
    updated_by
  )
  values (
    p_organization_id,
    lower(trim(p_overlay_key)),
    trim(p_title),
    p_description,
    trim(p_overlay_storage_path),
    lower(trim(p_overlay_sha256)),
    true,
    v_uid,
    v_uid
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.create_schema_overlay_profile_v1(uuid, text, text, text, text, text) from public;
grant execute on function contract_registry.create_schema_overlay_profile_v1(uuid, text, text, text, text, text) to authenticated;

commit;