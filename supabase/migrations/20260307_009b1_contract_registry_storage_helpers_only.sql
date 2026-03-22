-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 009B1
-- Storage helper layer only
-- No direct ALTER/POLICY on storage.objects
-- Safe under project-owned schema permissions
-- =========================================================

begin;

create or replace function contract_registry.storage_object_bucket_v1(
  p_bucket_id text
)
returns text
language sql
immutable
as $$
  select trim(p_bucket_id)
$$;

create or replace function contract_registry.storage_object_name_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select trim(p_name)
$$;

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

create or replace function contract_registry.storage_top_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 1), '')
$$;

create or replace function contract_registry.storage_second_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 2), '')
$$;

create or replace function contract_registry.storage_third_folder_v1(
  p_name text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_name), '/', 3), '')
$$;

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

revoke all on function contract_registry.storage_object_bucket_v1(text) from public;
revoke all on function contract_registry.storage_object_name_v1(text) from public;
revoke all on function contract_registry.storage_full_path_v1(text,text) from public;
revoke all on function contract_registry.storage_top_folder_v1(text) from public;
revoke all on function contract_registry.storage_second_folder_v1(text) from public;
revoke all on function contract_registry.storage_third_folder_v1(text) from public;
revoke all on function contract_registry.storage_object_path_valid_v1(text,text) from public;
revoke all on function contract_registry.user_can_read_contract_storage_v1(text) from public;
revoke all on function contract_registry.user_can_write_contract_storage_v1(text) from public;
revoke all on function contract_registry.storage_overlay_org_id_v1(text) from public;
revoke all on function contract_registry.user_can_read_overlay_storage_v1(text) from public;
revoke all on function contract_registry.user_can_write_overlay_storage_v1(text) from public;
revoke all on function contract_registry.user_can_read_release_storage_v1(text) from public;
revoke all on function contract_registry.user_can_write_release_storage_v1(text) from public;
revoke all on function contract_registry.user_can_read_storage_object_v1(text,text) from public;
revoke all on function contract_registry.user_can_write_storage_object_v1(text,text) from public;

grant execute on function contract_registry.storage_object_bucket_v1(text) to authenticated;
grant execute on function contract_registry.storage_object_name_v1(text) to authenticated;
grant execute on function contract_registry.storage_full_path_v1(text,text) to authenticated;
grant execute on function contract_registry.storage_top_folder_v1(text) to authenticated;
grant execute on function contract_registry.storage_second_folder_v1(text) to authenticated;
grant execute on function contract_registry.storage_third_folder_v1(text) to authenticated;
grant execute on function contract_registry.storage_object_path_valid_v1(text,text) to authenticated;
grant execute on function contract_registry.user_can_read_contract_storage_v1(text) to authenticated;
grant execute on function contract_registry.user_can_write_contract_storage_v1(text) to authenticated;
grant execute on function contract_registry.storage_overlay_org_id_v1(text) to authenticated;
grant execute on function contract_registry.user_can_read_overlay_storage_v1(text) to authenticated;
grant execute on function contract_registry.user_can_write_overlay_storage_v1(text) to authenticated;
grant execute on function contract_registry.user_can_read_release_storage_v1(text) to authenticated;
grant execute on function contract_registry.user_can_write_release_storage_v1(text) to authenticated;
grant execute on function contract_registry.user_can_read_storage_object_v1(text,text) to authenticated;
grant execute on function contract_registry.user_can_write_storage_object_v1(text,text) to authenticated;

commit;