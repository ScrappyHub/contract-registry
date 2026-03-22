-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 009B
-- Supabase Storage RLS policies
-- Locked to Contract Registry spec + Rooted hosted posture
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
--   005_contract_registry_release_artifacts.sql
--   006_contract_registry_billing_entitlements.sql
--   007_contract_registry_views_and_rpc.sql
--   008_contract_registry_app_command_rpcs.sql
--   009A_contract_registry_storage_path_law.sql
--
-- Purpose:
--   - lock storage object access to org/capability-aware rules
--   - enforce bucket/path law at storage layer
--   - support logged-in workbench/artifact access later
--   - keep hosted posture explicit (no silent public access)
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Storage helper functions
-- ---------------------------------------------------------

create or replace function contract_registry.storage_object_bucket_v1(
  p_bucket_id text
)
returns text
language sql
immutable
as $$
  select trim(p_bucket_id)
$$;

revoke all on function contract_registry.storage_object_bucket_v1(text) from public;
grant execute on function contract_registry.storage_object_bucket_v1(text) to authenticated;

create or replace function contract_registry.storage_object_name_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select trim(p_name)
$$;

revoke all on function contract_registry.storage_object_name_v1(text) from public;
grant execute on function contract_registry.storage_object_name_v1(text) to authenticated;

create or replace function contract_registry.storage_full_path_v1(
  p_bucket_id text,
  p_name text
)
returns text
language sql
immutable
as $$
  select trim(p_bucket_id) || '/' || trim(p_name)
$$;

revoke all on function contract_registry.storage_full_path_v1(text, text) from public;
grant execute on function contract_registry.storage_full_path_v1(text, text) to authenticated;

create or replace function contract_registry.storage_top_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 1), '')
$$;

revoke all on function contract_registry.storage_top_folder_v1(text) from public;
grant execute on function contract_registry.storage_top_folder_v1(text) to authenticated;

create or replace function contract_registry.storage_second_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 2), '')
$$;

revoke all on function contract_registry.storage_second_folder_v1(text) from public;
grant execute on function contract_registry.storage_second_folder_v1(text) to authenticated;

create or replace function contract_registry.storage_third_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 3), '')
$$;

revoke all on function contract_registry.storage_third_folder_v1(text) from public;
grant execute on function contract_registry.storage_third_folder_v1(text) to authenticated;

-- ---------------------------------------------------------
-- 2) Bucket/path validation against canonical law
-- ---------------------------------------------------------

create or replace function contract_registry.storage_object_path_valid_v1(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.storage_path_valid_v1(
    contract_registry.storage_full_path_v1(p_bucket_id, p_name)
  )
$$;

revoke all on function contract_registry.storage_object_path_valid_v1(text, text) from public;
grant execute on function contract_registry.storage_object_path_valid_v1(text, text) to authenticated;

-- ---------------------------------------------------------
-- 3) Contracts bucket access
--   contracts/<contract_key>/versions/<version_label>/source.json
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_read_contract_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select exists (
    select 1
    from contract_registry.contracts c
    where lower(c.contract_key) = lower(contract_registry.storage_top_folder_v1(p_name))
      and contract_registry.user_is_org_member_v1(c.organization_id)
      and billing.account_is_in_good_standing_v1(c.organization_id)
      and billing.entitlement_enabled_v1(c.organization_id, 'contract_registry.api.access')
  )
$$;

revoke all on function contract_registry.user_can_read_contract_storage_v1(text) from public;
grant execute on function contract_registry.user_can_read_contract_storage_v1(text) to authenticated;

create or replace function contract_registry.user_can_write_contract_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select exists (
    select 1
    from contract_registry.contracts c
    where lower(c.contract_key) = lower(contract_registry.storage_top_folder_v1(p_name))
      and contract_registry.user_can_write_billed_v1(c.organization_id)
  )
$$;

revoke all on function contract_registry.user_can_write_contract_storage_v1(text) from public;
grant execute on function contract_registry.user_can_write_contract_storage_v1(text) to authenticated;

-- ---------------------------------------------------------
-- 4) Overlays bucket access
--   overlays/orgs/<org_uuid>/policy/<overlay>.json
--   overlays/orgs/<org_uuid>/schema/<overlay>.json
-- ---------------------------------------------------------

create or replace function contract_registry.storage_overlay_org_id_v1(
  p_name text
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_second text;
  v_third text;
begin
  v_second := contract_registry.storage_second_folder_v1(p_name);
  v_third := contract_registry.storage_third_folder_v1(p_name);

  if v_second <> 'orgs' then
    return null;
  end if;

  begin
    return v_third::uuid;
  exception when others then
    return null;
  end;
end;
$$;

revoke all on function contract_registry.storage_overlay_org_id_v1(text) from public;
grant execute on function contract_registry.storage_overlay_org_id_v1(text) to authenticated;

create or replace function contract_registry.user_can_read_overlay_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.storage_overlay_org_id_v1(p_name) is not null
    and contract_registry.user_is_org_member_v1(contract_registry.storage_overlay_org_id_v1(p_name))
    and billing.account_is_in_good_standing_v1(contract_registry.storage_overlay_org_id_v1(p_name))
    and billing.entitlement_enabled_v1(contract_registry.storage_overlay_org_id_v1(p_name), 'contract_registry.api.access')
$$;

revoke all on function contract_registry.user_can_read_overlay_storage_v1(text) from public;
grant execute on function contract_registry.user_can_read_overlay_storage_v1(text) to authenticated;

create or replace function contract_registry.user_can_write_overlay_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select
    contract_registry.storage_overlay_org_id_v1(p_name) is not null
    and contract_registry.user_can_manage_overlays_billed_v1(contract_registry.storage_overlay_org_id_v1(p_name))
$$;

revoke all on function contract_registry.user_can_write_overlay_storage_v1(text) from public;
grant execute on function contract_registry.user_can_write_overlay_storage_v1(text) to authenticated;

-- ---------------------------------------------------------
-- 5) Releases bucket access
--   releases/<contract_key>/<packet_id>/...
-- Read:
--   org member + api access
-- Write:
--   release capability
-- Download workbench/artifacts later can reuse read gate or a
--   dedicated entitlement when workbench tables arrive
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_read_release_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select exists (
    select 1
    from contract_registry.contracts c
    where lower(c.contract_key) = lower(contract_registry.storage_top_folder_v1(p_name))
      and contract_registry.user_is_org_member_v1(c.organization_id)
      and billing.account_is_in_good_standing_v1(c.organization_id)
      and (
        billing.entitlement_enabled_v1(c.organization_id, 'contract_registry.api.access')
        or billing.entitlement_enabled_v1(c.organization_id, 'contract_registry.audit.read')
        or billing.entitlement_enabled_v1(c.organization_id, 'contract_registry.workbench.download')
      )
  )
$$;

revoke all on function contract_registry.user_can_read_release_storage_v1(text) from public;
grant execute on function contract_registry.user_can_read_release_storage_v1(text) to authenticated;

create or replace function contract_registry.user_can_write_release_storage_v1(
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
  select exists (
    select 1
    from contract_registry.contracts c
    where lower(c.contract_key) = lower(contract_registry.storage_top_folder_v1(p_name))
      and contract_registry.user_can_release_billed_v1(c.organization_id)
  )
$$;

revoke all on function contract_registry.user_can_write_release_storage_v1(text) from public;
grant execute on function contract_registry.user_can_write_release_storage_v1(text) to authenticated;

-- ---------------------------------------------------------
-- 6) Unified storage access helpers
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_read_storage_object_v1(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select case
    when not contract_registry.storage_object_path_valid_v1(p_bucket_id, p_name) then false
    when trim(p_bucket_id) = 'contracts' then contract_registry.user_can_read_contract_storage_v1(p_name)
    when trim(p_bucket_id) = 'overlays'  then contract_registry.user_can_read_overlay_storage_v1(p_name)
    when trim(p_bucket_id) = 'releases'  then contract_registry.user_can_read_release_storage_v1(p_name)
    else false
  end
$$;

revoke all on function contract_registry.user_can_read_storage_object_v1(text, text) from public;
grant execute on function contract_registry.user_can_read_storage_object_v1(text, text) to authenticated;

create or replace function contract_registry.user_can_write_storage_object_v1(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select case
    when not contract_registry.storage_object_path_valid_v1(p_bucket_id, p_name) then false
    when trim(p_bucket_id) = 'contracts' then contract_registry.user_can_write_contract_storage_v1(p_name)
    when trim(p_bucket_id) = 'overlays'  then contract_registry.user_can_write_overlay_storage_v1(p_name)
    when trim(p_bucket_id) = 'releases'  then contract_registry.user_can_write_release_storage_v1(p_name)
    else false
  end
$$;

revoke all on function contract_registry.user_can_write_storage_object_v1(text, text) from public;
grant execute on function contract_registry.user_can_write_storage_object_v1(text, text) to authenticated;

-- ---------------------------------------------------------
-- 7) Storage.objects RLS
-- ---------------------------------------------------------

alter table storage.objects enable row level security;
alter table storage.objects force row level security;

-- Clean prior project-local policies if re-run
drop policy if exists contract_registry_storage_objects_select_v1 on storage.objects;
drop policy if exists contract_registry_storage_objects_insert_v1 on storage.objects;
drop policy if exists contract_registry_storage_objects_update_v1 on storage.objects;
drop policy if exists contract_registry_storage_objects_delete_v1 on storage.objects;

create policy contract_registry_storage_objects_select_v1
on storage.objects
for select
to authenticated
using (
  contract_registry.user_can_read_storage_object_v1(bucket_id, name)
);

create policy contract_registry_storage_objects_insert_v1
on storage.objects
for insert
to authenticated
with check (
  contract_registry.user_can_write_storage_object_v1(bucket_id, name)
);

create policy contract_registry_storage_objects_update_v1
on storage.objects
for update
to authenticated
using (
  contract_registry.user_can_write_storage_object_v1(bucket_id, name)
)
with check (
  contract_registry.user_can_write_storage_object_v1(bucket_id, name)
);

create policy contract_registry_storage_objects_delete_v1
on storage.objects
for delete
to authenticated
using (
  contract_registry.user_can_write_storage_object_v1(bucket_id, name)
);

-- ---------------------------------------------------------
-- 8) Optional bucket table tightening
--    Only if storage.buckets is exposed in this project.
-- ---------------------------------------------------------

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'storage'
      and table_name = 'buckets'
  ) then
    execute 'alter table storage.buckets enable row level security';
    execute 'alter table storage.buckets force row level security';

    begin
      execute 'drop policy if exists contract_registry_storage_buckets_select_v1 on storage.buckets';
    exception when others then
      null;
    end;

    execute '
      create policy contract_registry_storage_buckets_select_v1
      on storage.buckets
      for select
      to authenticated
      using (
        id in (''contracts'',''overlays'',''releases'')
      )
    ';
  end if;
end
$$;

commit;