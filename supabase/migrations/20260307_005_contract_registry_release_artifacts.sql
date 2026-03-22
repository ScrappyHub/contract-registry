-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 005
-- Release artifacts:
--   contract_releases
--   release_packets
--   release_receipts
--   effective_sets
--   finalize FK for contract_release_overlay_bindings.release_id
--   helper functions
--   RLS
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
-- Rooted-style posture:
--   artifact refs only
--   hosted registry state, not truth-law mutation
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Contract releases
-- ---------------------------------------------------------

create table if not exists contract_registry.contract_releases (
  id uuid primary key default gen_random_uuid(),
  contract_version_id uuid not null,
  organization_id uuid not null,
  release_status text not null,
  release_kind text not null,
  released_at timestamptz null,
  released_by uuid null,
  packet_id text null,
  packet_root_storage_path text null,
  release_receipt_storage_path text null,
  release_receipt_sha256 text null,
  effective_sets_receipt_storage_path text null,
  effective_sets_receipt_sha256 text null,
  verification_receipt_storage_path text null,
  verification_receipt_sha256 text null,
  created_at timestamptz not null default now(),

  constraint contract_releases_contract_version_fk
    foreign key (contract_version_id)
    references contract_registry.contract_versions(id)
    on delete cascade,

  constraint contract_releases_organization_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint contract_releases_release_status_chk
    check (release_status in ('pending','running','succeeded','failed','superseded')),

  constraint contract_releases_release_kind_chk
    check (release_kind in ('manual','api','scheduled')),

  constraint contract_releases_packet_id_chk
    check (
      packet_id is null
      or packet_id ~ '^[0-9a-f]{64}$'
    ),

  constraint contract_releases_release_receipt_sha256_chk
    check (
      release_receipt_sha256 is null
      or release_receipt_sha256 ~ '^[0-9a-f]{64}$'
    ),

  constraint contract_releases_effective_sets_receipt_sha256_chk
    check (
      effective_sets_receipt_sha256 is null
      or effective_sets_receipt_sha256 ~ '^[0-9a-f]{64}$'
    ),

  constraint contract_releases_verification_receipt_sha256_chk
    check (
      verification_receipt_sha256 is null
      or verification_receipt_sha256 ~ '^[0-9a-f]{64}$'
    )
);

-- ---------------------------------------------------------
-- 2) Release packet refs
-- ---------------------------------------------------------

create table if not exists contract_registry.release_packets (
  release_id uuid primary key,
  packet_id text not null unique,
  packet_root_storage_path text not null,
  manifest_sha256 text not null,
  packet_dir_sha256 text null,
  packet_created_utc timestamptz null,
  signing_state text not null,
  created_at timestamptz not null default now(),

  constraint release_packets_release_fk
    foreign key (release_id)
    references contract_registry.contract_releases(id)
    on delete cascade,

  constraint release_packets_packet_id_chk
    check (packet_id ~ '^[0-9a-f]{64}$'),

  constraint release_packets_manifest_sha256_chk
    check (manifest_sha256 ~ '^[0-9a-f]{64}$'),

  constraint release_packets_packet_dir_sha256_chk
    check (
      packet_dir_sha256 is null
      or packet_dir_sha256 ~ '^[0-9a-f]{64}$'
    ),

  constraint release_packets_signing_state_chk
    check (signing_state in ('unsigned','signed','verified'))
);

-- ---------------------------------------------------------
-- 3) Release receipt refs
-- ---------------------------------------------------------

create table if not exists contract_registry.release_receipts (
  release_id uuid primary key,
  tier0_receipt_storage_path text not null,
  tier0_receipt_sha256 text not null,
  golden_receipt_storage_path text null,
  golden_receipt_sha256 text null,
  verification_receipt_storage_path text null,
  verification_receipt_sha256 text null,
  created_at timestamptz not null default now(),

  constraint release_receipts_release_fk
    foreign key (release_id)
    references contract_registry.contract_releases(id)
    on delete cascade,

  constraint release_receipts_tier0_receipt_sha256_chk
    check (tier0_receipt_sha256 ~ '^[0-9a-f]{64}$'),

  constraint release_receipts_golden_receipt_sha256_chk
    check (
      golden_receipt_sha256 is null
      or golden_receipt_sha256 ~ '^[0-9a-f]{64}$'
    ),

  constraint release_receipts_verification_receipt_sha256_chk
    check (
      verification_receipt_sha256 is null
      or verification_receipt_sha256 ~ '^[0-9a-f]{64}$'
    )
);

-- ---------------------------------------------------------
-- 4) Effective sets refs
-- ---------------------------------------------------------

create table if not exists contract_registry.effective_sets (
  release_id uuid primary key,
  policy_effective_hash text not null,
  schema_effective_hash text not null,
  effective_sets_receipt_storage_path text not null,
  effective_sets_receipt_sha256 text not null,
  allow_overrides boolean not null default false,
  created_at timestamptz not null default now(),

  constraint effective_sets_release_fk
    foreign key (release_id)
    references contract_registry.contract_releases(id)
    on delete cascade,

  constraint effective_sets_policy_effective_hash_chk
    check (policy_effective_hash ~ '^[0-9a-f]{64}$'),

  constraint effective_sets_schema_effective_hash_chk
    check (schema_effective_hash ~ '^[0-9a-f]{64}$'),

  constraint effective_sets_receipt_sha256_chk
    check (effective_sets_receipt_sha256 ~ '^[0-9a-f]{64}$')
);

-- ---------------------------------------------------------
-- 5) Finalize FK for overlay bindings -> releases
-- ---------------------------------------------------------

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'contract_release_overlay_bindings_release_fk'
  ) then
    alter table contract_registry.contract_release_overlay_bindings
      add constraint contract_release_overlay_bindings_release_fk
      foreign key (release_id)
      references contract_registry.contract_releases(id)
      on delete cascade;
  end if;
end
$$;

-- ---------------------------------------------------------
-- 6) Indexes
-- ---------------------------------------------------------

create index if not exists contract_releases_org_created_at_idx
  on contract_registry.contract_releases(organization_id, created_at desc);

create index if not exists contract_releases_contract_version_created_at_idx
  on contract_registry.contract_releases(contract_version_id, created_at desc);

create index if not exists contract_releases_status_created_at_idx
  on contract_registry.contract_releases(release_status, created_at desc);

create index if not exists contract_releases_packet_id_idx
  on contract_registry.contract_releases(packet_id);

create index if not exists release_packets_signing_state_idx
  on contract_registry.release_packets(signing_state);

create index if not exists release_receipts_created_at_idx
  on contract_registry.release_receipts(created_at desc);

create index if not exists effective_sets_created_at_idx
  on contract_registry.effective_sets(created_at desc);

-- ---------------------------------------------------------
-- 7) Helper functions
-- ---------------------------------------------------------

create or replace function contract_registry.contract_release_org_id_v1(
  p_release_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select cr.organization_id
  from contract_registry.contract_releases cr
  where cr.id = p_release_id
$$;

revoke all on function contract_registry.contract_release_org_id_v1(uuid) from public;
grant execute on function contract_registry.contract_release_org_id_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_publish_release_v1(
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
    array['owner','admin','release_manager']
  )
$$;

revoke all on function contract_registry.user_can_publish_release_v1(uuid) from public;
grant execute on function contract_registry.user_can_publish_release_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 8) Integrity trigger:
-- release org must match contract version org
-- ---------------------------------------------------------

create or replace function contract_registry_private.enforce_contract_release_integrity_v1()
returns trigger
language plpgsql
security invoker
as $$
declare
  v_org_id uuid;
begin
  v_org_id := contract_registry.contract_version_org_id_v1(new.contract_version_id);

  if v_org_id is null then
    raise exception 'CONTRACT_VERSION_NOT_FOUND';
  end if;

  if new.organization_id <> v_org_id then
    raise exception 'CONTRACT_RELEASE_ORG_CONTRACT_VERSION_MISMATCH';
  end if;

  if new.release_status = 'succeeded' then
    if new.released_at is null then
      raise exception 'SUCCEEDED_RELEASE_REQUIRES_RELEASED_AT';
    end if;
    if new.released_by is null then
      raise exception 'SUCCEEDED_RELEASE_REQUIRES_RELEASED_BY';
    end if;
    if new.packet_id is null then
      raise exception 'SUCCEEDED_RELEASE_REQUIRES_PACKET_ID';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contract_releases_integrity_v1
  on contract_registry.contract_releases;

create trigger trg_contract_releases_integrity_v1
before insert or update on contract_registry.contract_releases
for each row
execute function contract_registry_private.enforce_contract_release_integrity_v1();

-- ---------------------------------------------------------
-- 9) Privileges
-- ---------------------------------------------------------

grant select, insert, update, delete on contract_registry.contract_releases to authenticated;
grant select, insert, update, delete on contract_registry.release_packets to authenticated;
grant select, insert, update, delete on contract_registry.release_receipts to authenticated;
grant select, insert, update, delete on contract_registry.effective_sets to authenticated;
grant select, insert, update, delete on contract_registry.contract_release_overlay_bindings to authenticated;

-- ---------------------------------------------------------
-- 10) RLS
-- ---------------------------------------------------------

alter table contract_registry.contract_releases enable row level security;
alter table contract_registry.contract_releases force row level security;

alter table contract_registry.release_packets enable row level security;
alter table contract_registry.release_packets force row level security;

alter table contract_registry.release_receipts enable row level security;
alter table contract_registry.release_receipts force row level security;

alter table contract_registry.effective_sets enable row level security;
alter table contract_registry.effective_sets force row level security;

-- overlay binding table already has RLS enabled in Migration 003

-- ---------------------------------------------------------
-- 11) RLS policies: contract_releases
-- ---------------------------------------------------------

drop policy if exists contract_releases_select_member_v1
  on contract_registry.contract_releases;

create policy contract_releases_select_member_v1
on contract_registry.contract_releases
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists contract_releases_insert_release_manager_v1
  on contract_registry.contract_releases;

create policy contract_releases_insert_release_manager_v1
on contract_registry.contract_releases
for insert
to authenticated
with check (
  contract_registry.user_can_publish_release_v1(organization_id)
);

drop policy if exists contract_releases_update_release_manager_v1
  on contract_registry.contract_releases;

create policy contract_releases_update_release_manager_v1
on contract_registry.contract_releases
for update
to authenticated
using (
  contract_registry.user_can_publish_release_v1(organization_id)
)
with check (
  contract_registry.user_can_publish_release_v1(organization_id)
);

drop policy if exists contract_releases_delete_owner_admin_v1
  on contract_registry.contract_releases;

create policy contract_releases_delete_owner_admin_v1
on contract_registry.contract_releases
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
);

-- ---------------------------------------------------------
-- 12) RLS policies: release_packets
-- ---------------------------------------------------------

drop policy if exists release_packets_select_member_v1
  on contract_registry.release_packets;

create policy release_packets_select_member_v1
on contract_registry.release_packets
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_packets_insert_release_manager_v1
  on contract_registry.release_packets;

create policy release_packets_insert_release_manager_v1
on contract_registry.release_packets
for insert
to authenticated
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_packets_update_release_manager_v1
  on contract_registry.release_packets;

create policy release_packets_update_release_manager_v1
on contract_registry.release_packets
for update
to authenticated
using (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
)
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_packets_delete_owner_admin_v1
  on contract_registry.release_packets;

create policy release_packets_delete_owner_admin_v1
on contract_registry.release_packets
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(
    contract_registry.contract_release_org_id_v1(release_id),
    array['owner','admin']
  )
);

-- ---------------------------------------------------------
-- 13) RLS policies: release_receipts
-- ---------------------------------------------------------

drop policy if exists release_receipts_select_member_v1
  on contract_registry.release_receipts;

create policy release_receipts_select_member_v1
on contract_registry.release_receipts
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_receipts_insert_release_manager_v1
  on contract_registry.release_receipts;

create policy release_receipts_insert_release_manager_v1
on contract_registry.release_receipts
for insert
to authenticated
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_receipts_update_release_manager_v1
  on contract_registry.release_receipts;

create policy release_receipts_update_release_manager_v1
on contract_registry.release_receipts
for update
to authenticated
using (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
)
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists release_receipts_delete_owner_admin_v1
  on contract_registry.release_receipts;

create policy release_receipts_delete_owner_admin_v1
on contract_registry.release_receipts
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(
    contract_registry.contract_release_org_id_v1(release_id),
    array['owner','admin']
  )
);

-- ---------------------------------------------------------
-- 14) RLS policies: effective_sets
-- ---------------------------------------------------------

drop policy if exists effective_sets_select_member_v1
  on contract_registry.effective_sets;

create policy effective_sets_select_member_v1
on contract_registry.effective_sets
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists effective_sets_insert_release_manager_v1
  on contract_registry.effective_sets;

create policy effective_sets_insert_release_manager_v1
on contract_registry.effective_sets
for insert
to authenticated
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists effective_sets_update_release_manager_v1
  on contract_registry.effective_sets;

create policy effective_sets_update_release_manager_v1
on contract_registry.effective_sets
for update
to authenticated
using (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
)
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists effective_sets_delete_owner_admin_v1
  on contract_registry.effective_sets;

create policy effective_sets_delete_owner_admin_v1
on contract_registry.effective_sets
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(
    contract_registry.contract_release_org_id_v1(release_id),
    array['owner','admin']
  )
);

-- ---------------------------------------------------------
-- 15) Tighten overlay binding RLS now that releases exist
-- Replace the weaker pre-release policies from Migration 003
-- ---------------------------------------------------------

drop policy if exists contract_release_overlay_bindings_select_member_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_select_member_v1
on contract_registry.contract_release_overlay_bindings
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists contract_release_overlay_bindings_insert_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_insert_admin_v1
on contract_registry.contract_release_overlay_bindings
for insert
to authenticated
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists contract_release_overlay_bindings_update_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_update_admin_v1
on contract_registry.contract_release_overlay_bindings
for update
to authenticated
using (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
)
with check (
  contract_registry.user_can_publish_release_v1(
    contract_registry.contract_release_org_id_v1(release_id)
  )
);

drop policy if exists contract_release_overlay_bindings_delete_admin_v1
  on contract_registry.contract_release_overlay_bindings;

create policy contract_release_overlay_bindings_delete_admin_v1
on contract_registry.contract_release_overlay_bindings
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(
    contract_registry.contract_release_org_id_v1(release_id),
    array['owner','admin']
  )
);

-- ---------------------------------------------------------
-- 16) Helper: create release record
-- ---------------------------------------------------------

create or replace function contract_registry.create_contract_release_v1(
  p_contract_version_id uuid,
  p_release_kind text
)
returns contract_registry.contract_releases
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.contract_releases;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.contract_version_org_id_v1(p_contract_version_id);

  if v_org_id is null then
    raise exception 'CONTRACT_VERSION_NOT_FOUND';
  end if;

  if p_release_kind not in ('manual','api','scheduled') then
    raise exception 'INVALID_RELEASE_KIND';
  end if;

  if not contract_registry.user_can_publish_release_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE_PUBLISH';
  end if;

  insert into contract_registry.contract_releases (
    contract_version_id,
    organization_id,
    release_status,
    release_kind
  )
  values (
    p_contract_version_id,
    v_org_id,
    'pending',
    p_release_kind
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.create_contract_release_v1(uuid, text) from public;
grant execute on function contract_registry.create_contract_release_v1(uuid, text) to authenticated;

commit;