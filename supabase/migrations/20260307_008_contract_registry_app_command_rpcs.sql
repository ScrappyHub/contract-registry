-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 008
-- App command RPCs
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
--   004_contract_registry_release_orchestration.sql
--   005_contract_registry_release_artifacts.sql
--   006_contract_registry_billing_entitlements.sql
--   007_contract_registry_views_and_rpc.sql
-- Rooted-style posture:
--   narrow command surface
--   explicit permission checks
--   no hidden workflow magic
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Create contract draft
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_contract_draft_v1(
  p_organization_id uuid,
  p_contract_key text,
  p_title text,
  p_description text default null
)
returns contract_registry.contracts
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_row contract_registry.contracts;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not contract_registry.user_can_write_billed_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_CONTRACT_WRITE';
  end if;

  if exists (
    select 1
    from contract_registry.contracts c
    where c.organization_id = p_organization_id
      and c.contract_key = lower(trim(p_contract_key))
  ) then
    raise exception 'CONTRACT_KEY_ALREADY_EXISTS';
  end if;

  insert into contract_registry.contracts (
    organization_id,
    contract_key,
    title,
    description,
    status,
    created_by,
    updated_by
  )
  values (
    p_organization_id,
    lower(trim(p_contract_key)),
    trim(p_title),
    p_description,
    'draft',
    v_uid,
    v_uid
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_create_contract_draft_v1(uuid, text, text, text) from public;
grant execute on function contract_registry.app_create_contract_draft_v1(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------
-- 2) Create contract version draft
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_contract_version_draft_v1(
  p_contract_id uuid,
  p_version_label text,
  p_source_json_sha256 text,
  p_source_json_storage_path text,
  p_changelog text default null
)
returns contract_registry.contract_versions
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_next_version_no integer;
  v_row contract_registry.contract_versions;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  select c.organization_id
    into v_org_id
  from contract_registry.contracts c
  where c.id = p_contract_id;

  if v_org_id is null then
    raise exception 'CONTRACT_NOT_FOUND';
  end if;

  if not contract_registry.user_can_write_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_CONTRACT_VERSION_WRITE';
  end if;

  select coalesce(max(cv.version_no), 0) + 1
    into v_next_version_no
  from contract_registry.contract_versions cv
  where cv.contract_id = p_contract_id;

  insert into contract_registry.contract_versions (
    contract_id,
    version_no,
    version_label,
    status,
    source_json_sha256,
    source_json_storage_path,
    changelog,
    created_by,
    updated_by
  )
  values (
    p_contract_id,
    v_next_version_no,
    trim(p_version_label),
    'draft',
    lower(trim(p_source_json_sha256)),
    trim(p_source_json_storage_path),
    p_changelog,
    v_uid,
    v_uid
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_create_contract_version_draft_v1(uuid, text, text, text, text) from public;
grant execute on function contract_registry.app_create_contract_version_draft_v1(uuid, text, text, text, text) to authenticated;

-- ---------------------------------------------------------
-- 3) Set current contract version
-- ---------------------------------------------------------

create or replace function contract_registry.app_set_current_contract_version_v1(
  p_contract_id uuid,
  p_contract_version_id uuid
)
returns contract_registry.contracts
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.contracts;
  v_match integer;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  select c.organization_id
    into v_org_id
  from contract_registry.contracts c
  where c.id = p_contract_id;

  if v_org_id is null then
    raise exception 'CONTRACT_NOT_FOUND';
  end if;

  if not contract_registry.user_can_write_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_SET_CURRENT_VERSION';
  end if;

  select count(*)
    into v_match
  from contract_registry.contract_versions cv
  where cv.id = p_contract_version_id
    and cv.contract_id = p_contract_id;

  if v_match <> 1 then
    raise exception 'CONTRACT_VERSION_NOT_OWNED_BY_CONTRACT';
  end if;

  update contract_registry.contracts
     set current_version_id = p_contract_version_id,
         updated_by = v_uid
   where id = p_contract_id
   returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_set_current_contract_version_v1(uuid, uuid) from public;
grant execute on function contract_registry.app_set_current_contract_version_v1(uuid, uuid) to authenticated;

-- ---------------------------------------------------------
-- 4) Create policy overlay profile
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_policy_overlay_profile_v1(
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
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_row contract_registry.policy_overlay_profiles;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not contract_registry.user_can_manage_overlays_billed_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_POLICY_OVERLAY_MANAGE';
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

revoke all on function contract_registry.app_create_policy_overlay_profile_v1(uuid, text, text, text, text, text) from public;
grant execute on function contract_registry.app_create_policy_overlay_profile_v1(uuid, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------
-- 5) Create schema overlay profile
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_schema_overlay_profile_v1(
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
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_row contract_registry.schema_overlay_profiles;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();

  if not contract_registry.user_can_manage_overlays_billed_v1(p_organization_id) then
    raise exception 'ACCESS_DENIED_SCHEMA_OVERLAY_MANAGE';
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

revoke all on function contract_registry.app_create_schema_overlay_profile_v1(uuid, text, text, text, text, text) from public;
grant execute on function contract_registry.app_create_schema_overlay_profile_v1(uuid, text, text, text, text, text) to authenticated;

-- ---------------------------------------------------------
-- 6) Bind overlays to release
-- ---------------------------------------------------------

create or replace function contract_registry.app_bind_release_overlays_v1(
  p_release_id uuid,
  p_policy_overlay_profile_id uuid default null,
  p_schema_overlay_profile_id uuid default null,
  p_bound_policy_overlay_sha256 text default null,
  p_bound_schema_overlay_sha256 text default null
)
returns contract_registry.contract_release_overlay_bindings
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.contract_release_overlay_bindings;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.contract_release_org_id_v1(p_release_id);

  if v_org_id is null then
    raise exception 'RELEASE_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_overlays_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE_OVERLAY_BIND';
  end if;

  insert into contract_registry.contract_release_overlay_bindings (
    release_id,
    policy_overlay_profile_id,
    schema_overlay_profile_id,
    bound_policy_overlay_sha256,
    bound_schema_overlay_sha256,
    created_at
  )
  values (
    p_release_id,
    p_policy_overlay_profile_id,
    p_schema_overlay_profile_id,
    case when p_bound_policy_overlay_sha256 is null then null else lower(trim(p_bound_policy_overlay_sha256)) end,
    case when p_bound_schema_overlay_sha256 is null then null else lower(trim(p_bound_schema_overlay_sha256)) end,
    now()
  )
  on conflict (release_id)
  do update set
    policy_overlay_profile_id = excluded.policy_overlay_profile_id,
    schema_overlay_profile_id = excluded.schema_overlay_profile_id,
    bound_policy_overlay_sha256 = excluded.bound_policy_overlay_sha256,
    bound_schema_overlay_sha256 = excluded.bound_schema_overlay_sha256
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_bind_release_overlays_v1(uuid, uuid, uuid, text, text) from public;
grant execute on function contract_registry.app_bind_release_overlays_v1(uuid, uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------
-- 7) Create release job (billed gate)
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_release_job_v1(
  p_contract_version_id uuid,
  p_job_type text,
  p_runner_ref text default null
)
returns contract_registry.release_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.release_jobs;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.contract_version_org_id_v1(p_contract_version_id);

  if v_org_id is null then
    raise exception 'CONTRACT_VERSION_NOT_FOUND';
  end if;

  if not contract_registry.user_can_release_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE_JOB_CREATE';
  end if;

  insert into contract_registry.release_jobs (
    organization_id,
    contract_version_id,
    job_type,
    job_status,
    requested_by,
    runner_ref
  )
  values (
    v_org_id,
    p_contract_version_id,
    trim(p_job_type),
    'queued',
    v_uid,
    p_runner_ref
  )
  returning * into v_row;

  insert into contract_registry.job_events (
    job_id,
    event_type,
    message,
    event_json
  )
  values (
    v_row.id,
    'job.created',
    'Release job created',
    jsonb_build_object(
      'job_type', v_row.job_type,
      'job_status', v_row.job_status,
      'requested_by', v_uid
    )
  );

  return v_row;
end;
$$;

revoke all on function contract_registry.app_create_release_job_v1(uuid, text, text) from public;
grant execute on function contract_registry.app_create_release_job_v1(uuid, text, text) to authenticated;

-- ---------------------------------------------------------
-- 8) Create contract release shell
-- ---------------------------------------------------------

create or replace function contract_registry.app_create_contract_release_v1(
  p_contract_version_id uuid,
  p_release_kind text
)
returns contract_registry.contract_releases
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
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

  if not contract_registry.user_can_release_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE_CREATE';
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
    trim(p_release_kind)
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_create_contract_release_v1(uuid, text) from public;
grant execute on function contract_registry.app_create_contract_release_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 9) Finalize release artifacts
-- ---------------------------------------------------------

create or replace function contract_registry.app_finalize_contract_release_v1(
  p_release_id uuid,
  p_packet_id text,
  p_packet_root_storage_path text,
  p_release_receipt_storage_path text,
  p_release_receipt_sha256 text,
  p_effective_sets_receipt_storage_path text,
  p_effective_sets_receipt_sha256 text,
  p_verification_receipt_storage_path text,
  p_verification_receipt_sha256 text,
  p_manifest_sha256 text,
  p_packet_dir_sha256 text,
  p_signing_state text,
  p_tier0_receipt_storage_path text,
  p_tier0_receipt_sha256 text,
  p_golden_receipt_storage_path text default null,
  p_golden_receipt_sha256 text default null,
  p_policy_effective_hash text default null,
  p_schema_effective_hash text default null,
  p_allow_overrides boolean default false
)
returns contract_registry.contract_releases
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private, billing
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.contract_releases;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.contract_release_org_id_v1(p_release_id);

  if v_org_id is null then
    raise exception 'RELEASE_NOT_FOUND';
  end if;

  if not contract_registry.user_can_release_billed_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE_FINALIZE';
  end if;

  update contract_registry.contract_releases
     set release_status = 'succeeded',
         released_at = now(),
         released_by = v_uid,
         packet_id = lower(trim(p_packet_id)),
         packet_root_storage_path = trim(p_packet_root_storage_path),
         release_receipt_storage_path = trim(p_release_receipt_storage_path),
         release_receipt_sha256 = lower(trim(p_release_receipt_sha256)),
         effective_sets_receipt_storage_path = trim(p_effective_sets_receipt_storage_path),
         effective_sets_receipt_sha256 = lower(trim(p_effective_sets_receipt_sha256)),
         verification_receipt_storage_path = trim(p_verification_receipt_storage_path),
         verification_receipt_sha256 = lower(trim(p_verification_receipt_sha256))
   where id = p_release_id
   returning * into v_row;

  if v_row.id is null then
    raise exception 'RELEASE_NOT_FOUND';
  end if;

  insert into contract_registry.release_packets (
    release_id,
    packet_id,
    packet_root_storage_path,
    manifest_sha256,
    packet_dir_sha256,
    packet_created_utc,
    signing_state
  )
  values (
    p_release_id,
    lower(trim(p_packet_id)),
    trim(p_packet_root_storage_path),
    lower(trim(p_manifest_sha256)),
    case when p_packet_dir_sha256 is null then null else lower(trim(p_packet_dir_sha256)) end,
    now(),
    trim(p_signing_state)
  )
  on conflict (release_id)
  do update set
    packet_id = excluded.packet_id,
    packet_root_storage_path = excluded.packet_root_storage_path,
    manifest_sha256 = excluded.manifest_sha256,
    packet_dir_sha256 = excluded.packet_dir_sha256,
    packet_created_utc = excluded.packet_created_utc,
    signing_state = excluded.signing_state;

  insert into contract_registry.release_receipts (
    release_id,
    tier0_receipt_storage_path,
    tier0_receipt_sha256,
    golden_receipt_storage_path,
    golden_receipt_sha256,
    verification_receipt_storage_path,
    verification_receipt_sha256
  )
  values (
    p_release_id,
    trim(p_tier0_receipt_storage_path),
    lower(trim(p_tier0_receipt_sha256)),
    case when p_golden_receipt_storage_path is null then null else trim(p_golden_receipt_storage_path) end,
    case when p_golden_receipt_sha256 is null then null else lower(trim(p_golden_receipt_sha256)) end,
    trim(p_verification_receipt_storage_path),
    lower(trim(p_verification_receipt_sha256))
  )
  on conflict (release_id)
  do update set
    tier0_receipt_storage_path = excluded.tier0_receipt_storage_path,
    tier0_receipt_sha256 = excluded.tier0_receipt_sha256,
    golden_receipt_storage_path = excluded.golden_receipt_storage_path,
    golden_receipt_sha256 = excluded.golden_receipt_sha256,
    verification_receipt_storage_path = excluded.verification_receipt_storage_path,
    verification_receipt_sha256 = excluded.verification_receipt_sha256;

  if p_policy_effective_hash is not null and p_schema_effective_hash is not null then
    insert into contract_registry.effective_sets (
      release_id,
      policy_effective_hash,
      schema_effective_hash,
      effective_sets_receipt_storage_path,
      effective_sets_receipt_sha256,
      allow_overrides
    )
    values (
      p_release_id,
      lower(trim(p_policy_effective_hash)),
      lower(trim(p_schema_effective_hash)),
      trim(p_effective_sets_receipt_storage_path),
      lower(trim(p_effective_sets_receipt_sha256)),
      coalesce(p_allow_overrides, false)
    )
    on conflict (release_id)
    do update set
      policy_effective_hash = excluded.policy_effective_hash,
      schema_effective_hash = excluded.schema_effective_hash,
      effective_sets_receipt_storage_path = excluded.effective_sets_receipt_storage_path,
      effective_sets_receipt_sha256 = excluded.effective_sets_receipt_sha256,
      allow_overrides = excluded.allow_overrides;
  end if;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_finalize_contract_release_v1(uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean) from public;
grant execute on function contract_registry.app_finalize_contract_release_v1(uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean) to authenticated;

commit;