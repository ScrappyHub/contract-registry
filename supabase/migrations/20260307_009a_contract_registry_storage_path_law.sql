-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 009A
-- Storage buckets + canonical hosted path law
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
--   005_contract_registry_release_artifacts.sql
--   006_contract_registry_billing_entitlements.sql
--   007_contract_registry_views_and_rpc.sql
--   008_contract_registry_app_command_rpcs.sql
-- Rooted-style posture:
--   path law is explicit
--   storage refs are deterministic
--   bucket/path validation is data-layer enforced
--   no hidden path conventions in UI code
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Canonical bucket registry
-- ---------------------------------------------------------

create table if not exists contract_registry.storage_buckets (
  bucket_key text primary key,
  bucket_name text not null unique,
  purpose text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),

  constraint storage_buckets_key_chk
    check (length(btrim(bucket_key)) > 0),

  constraint storage_buckets_name_chk
    check (length(btrim(bucket_name)) > 0)
);

create index if not exists storage_buckets_active_idx
  on contract_registry.storage_buckets(is_active);

insert into contract_registry.storage_buckets (
  bucket_key,
  bucket_name,
  purpose,
  is_active
)
values
  ('contracts', 'contracts', 'Contract source artifacts and authored source payloads', true),
  ('overlays', 'overlays', 'Policy/schema overlay artifacts', true),
  ('releases', 'releases', 'Release packets and release receipts', true)
on conflict (bucket_key) do update
set
  bucket_name = excluded.bucket_name,
  purpose = excluded.purpose,
  is_active = excluded.is_active;

grant select on contract_registry.storage_buckets to authenticated;

alter table contract_registry.storage_buckets enable row level security;
alter table contract_registry.storage_buckets force row level security;

drop policy if exists storage_buckets_select_authenticated_v1
  on contract_registry.storage_buckets;

create policy storage_buckets_select_authenticated_v1
on contract_registry.storage_buckets
for select
to authenticated
using (true);

-- ---------------------------------------------------------
-- 2) Bucket/path helpers
-- ---------------------------------------------------------

create or replace function contract_registry.storage_bucket_from_path_v1(
  p_storage_path text
)
returns text
language sql
immutable
as $$
  select nullif(split_part(trim(p_storage_path), '/', 1), '')
$$;

revoke all on function contract_registry.storage_bucket_from_path_v1(text) from public;
grant execute on function contract_registry.storage_bucket_from_path_v1(text) to authenticated;

create or replace function contract_registry.storage_path_has_no_backslashes_v1(
  p_storage_path text
)
returns boolean
language sql
immutable
as $$
  select position(chr(92) in coalesce(p_storage_path, '')) = 0
$$;

revoke all on function contract_registry.storage_path_has_no_backslashes_v1(text) from public;
grant execute on function contract_registry.storage_path_has_no_backslashes_v1(text) to authenticated;

create or replace function contract_registry.storage_path_is_normalized_v1(
  p_storage_path text
)
returns boolean
language sql
immutable
as $$
  select
    p_storage_path is not null
    and length(btrim(p_storage_path)) > 0
    and p_storage_path = btrim(p_storage_path)
    and left(p_storage_path, 1) <> '/'
    and right(p_storage_path, 1) <> '/'
    and position('//' in p_storage_path) = 0
    and position('/./' in p_storage_path) = 0
    and position('../' in p_storage_path) = 0
    and position('/..' in p_storage_path) = 0
    and contract_registry.storage_path_has_no_backslashes_v1(p_storage_path)
$$;

revoke all on function contract_registry.storage_path_is_normalized_v1(text) from public;
grant execute on function contract_registry.storage_path_is_normalized_v1(text) to authenticated;

create or replace function contract_registry.storage_bucket_is_registered_v1(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select exists (
    select 1
    from contract_registry.storage_buckets b
    where b.bucket_name = contract_registry.storage_bucket_from_path_v1(p_storage_path)
      and b.is_active = true
  )
$$;

revoke all on function contract_registry.storage_bucket_is_registered_v1(text) from public;
grant execute on function contract_registry.storage_bucket_is_registered_v1(text) to authenticated;

create or replace function contract_registry.storage_path_valid_v1(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    contract_registry.storage_path_is_normalized_v1(p_storage_path)
    and contract_registry.storage_bucket_is_registered_v1(p_storage_path)
$$;

revoke all on function contract_registry.storage_path_valid_v1(text) from public;
grant execute on function contract_registry.storage_path_valid_v1(text) to authenticated;

-- ---------------------------------------------------------
-- 3) Canonical path builders
-- ---------------------------------------------------------

create or replace function contract_registry.contract_source_storage_path_v1(
  p_contract_key text,
  p_version_label text
)
returns text
language sql
immutable
as $$
  select
    'contracts/'
    || lower(trim(p_contract_key))
    || '/versions/'
    || lower(trim(p_version_label))
    || '/source.json'
$$;

revoke all on function contract_registry.contract_source_storage_path_v1(text, text) from public;
grant execute on function contract_registry.contract_source_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.policy_overlay_storage_path_v1(
  p_organization_id uuid,
  p_overlay_key text
)
returns text
language sql
immutable
as $$
  select
    'overlays/orgs/'
    || lower(p_organization_id::text)
    || '/policy/'
    || lower(trim(p_overlay_key))
    || '.json'
$$;

revoke all on function contract_registry.policy_overlay_storage_path_v1(uuid, text) from public;
grant execute on function contract_registry.policy_overlay_storage_path_v1(uuid, text) to authenticated;

create or replace function contract_registry.schema_overlay_storage_path_v1(
  p_organization_id uuid,
  p_overlay_key text
)
returns text
language sql
immutable
as $$
  select
    'overlays/orgs/'
    || lower(p_organization_id::text)
    || '/schema/'
    || lower(trim(p_overlay_key))
    || '.json'
$$;

revoke all on function contract_registry.schema_overlay_storage_path_v1(uuid, text) from public;
grant execute on function contract_registry.schema_overlay_storage_path_v1(uuid, text) to authenticated;

create or replace function contract_registry.release_packet_root_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/packet_root'
$$;

revoke all on function contract_registry.release_packet_root_storage_path_v1(text, text) from public;
grant execute on function contract_registry.release_packet_root_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.release_receipt_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/release_receipt.txt'
$$;

revoke all on function contract_registry.release_receipt_storage_path_v1(text, text) from public;
grant execute on function contract_registry.release_receipt_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.tier0_receipt_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/tier0_receipt.txt'
$$;

revoke all on function contract_registry.tier0_receipt_storage_path_v1(text, text) from public;
grant execute on function contract_registry.tier0_receipt_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.golden_receipt_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/golden_receipt.txt'
$$;

revoke all on function contract_registry.golden_receipt_storage_path_v1(text, text) from public;
grant execute on function contract_registry.golden_receipt_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.verification_receipt_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/verification_receipt.txt'
$$;

revoke all on function contract_registry.verification_receipt_storage_path_v1(text, text) from public;
grant execute on function contract_registry.verification_receipt_storage_path_v1(text, text) to authenticated;

create or replace function contract_registry.effective_sets_receipt_storage_path_v1(
  p_contract_key text,
  p_packet_id text
)
returns text
language sql
immutable
as $$
  select
    'releases/'
    || lower(trim(p_contract_key))
    || '/'
    || lower(trim(p_packet_id))
    || '/effective_sets/receipt.txt'
$$;

revoke all on function contract_registry.effective_sets_receipt_storage_path_v1(text, text) from public;
grant execute on function contract_registry.effective_sets_receipt_storage_path_v1(text, text) to authenticated;

-- ---------------------------------------------------------
-- 4) Path-law integrity trigger
-- ---------------------------------------------------------

create or replace function contract_registry_private.enforce_storage_path_law_v1()
returns trigger
language plpgsql
security invoker
as $$
begin
  if tg_table_name = 'contract_versions' then
    if new.source_json_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.source_json_storage_path) then
      raise exception 'INVALID_SOURCE_JSON_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'policy_overlay_profiles' then
    if new.overlay_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.overlay_storage_path) then
      raise exception 'INVALID_POLICY_OVERLAY_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'schema_overlay_profiles' then
    if new.overlay_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.overlay_storage_path) then
      raise exception 'INVALID_SCHEMA_OVERLAY_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'contract_releases' then
    if new.packet_root_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.packet_root_storage_path) then
      raise exception 'INVALID_RELEASE_PACKET_ROOT_STORAGE_PATH';
    end if;
    if new.release_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.release_receipt_storage_path) then
      raise exception 'INVALID_RELEASE_RECEIPT_STORAGE_PATH';
    end if;
    if new.effective_sets_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.effective_sets_receipt_storage_path) then
      raise exception 'INVALID_EFFECTIVE_SETS_RECEIPT_STORAGE_PATH';
    end if;
    if new.verification_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.verification_receipt_storage_path) then
      raise exception 'INVALID_VERIFICATION_RECEIPT_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'release_packets' then
    if new.packet_root_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.packet_root_storage_path) then
      raise exception 'INVALID_RELEASE_PACKETS_PACKET_ROOT_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'release_receipts' then
    if new.tier0_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.tier0_receipt_storage_path) then
      raise exception 'INVALID_TIER0_RECEIPT_STORAGE_PATH';
    end if;
    if new.golden_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.golden_receipt_storage_path) then
      raise exception 'INVALID_GOLDEN_RECEIPT_STORAGE_PATH';
    end if;
    if new.verification_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.verification_receipt_storage_path) then
      raise exception 'INVALID_RELEASE_RECEIPTS_VERIFICATION_STORAGE_PATH';
    end if;
  elsif tg_table_name = 'effective_sets' then
    if new.effective_sets_receipt_storage_path is not null
       and not contract_registry.storage_path_valid_v1(new.effective_sets_receipt_storage_path) then
      raise exception 'INVALID_EFFECTIVE_SETS_STORAGE_PATH';
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------
-- 5) Attach trigger to all path-bearing tables
-- ---------------------------------------------------------

drop trigger if exists trg_contract_versions_storage_path_law_v1
  on contract_registry.contract_versions;

create trigger trg_contract_versions_storage_path_law_v1
before insert or update on contract_registry.contract_versions
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_policy_overlay_profiles_storage_path_law_v1
  on contract_registry.policy_overlay_profiles;

create trigger trg_policy_overlay_profiles_storage_path_law_v1
before insert or update on contract_registry.policy_overlay_profiles
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_schema_overlay_profiles_storage_path_law_v1
  on contract_registry.schema_overlay_profiles;

create trigger trg_schema_overlay_profiles_storage_path_law_v1
before insert or update on contract_registry.schema_overlay_profiles
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_contract_releases_storage_path_law_v1
  on contract_registry.contract_releases;

create trigger trg_contract_releases_storage_path_law_v1
before insert or update on contract_registry.contract_releases
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_release_packets_storage_path_law_v1
  on contract_registry.release_packets;

create trigger trg_release_packets_storage_path_law_v1
before insert or update on contract_registry.release_packets
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_release_receipts_storage_path_law_v1
  on contract_registry.release_receipts;

create trigger trg_release_receipts_storage_path_law_v1
before insert or update on contract_registry.release_receipts
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

drop trigger if exists trg_effective_sets_storage_path_law_v1
  on contract_registry.effective_sets;

create trigger trg_effective_sets_storage_path_law_v1
before insert or update on contract_registry.effective_sets
for each row
execute function contract_registry_private.enforce_storage_path_law_v1();

-- ---------------------------------------------------------
-- 6) Hosted path summary view
-- ---------------------------------------------------------

create or replace view contract_registry.v_release_storage_paths_v1 as
select
  cr.id as release_id,
  cr.organization_id,
  c.contract_key,
  cr.packet_id,
  cr.packet_root_storage_path,
  cr.release_receipt_storage_path,
  cr.effective_sets_receipt_storage_path,
  cr.verification_receipt_storage_path,
  rr.tier0_receipt_storage_path,
  rr.golden_receipt_storage_path,
  rr.verification_receipt_storage_path as release_receipts_verification_receipt_storage_path
from contract_registry.contract_releases cr
join contract_registry.contract_versions cv
  on cv.id = cr.contract_version_id
join contract_registry.contracts c
  on c.id = cv.contract_id
left join contract_registry.release_receipts rr
  on rr.release_id = cr.id;

grant select on contract_registry.v_release_storage_paths_v1 to authenticated;

commit;