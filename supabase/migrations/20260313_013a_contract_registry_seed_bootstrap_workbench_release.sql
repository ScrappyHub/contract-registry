-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 013A
-- Bootstrap one published workbench release + one artifact
-- Depends on:
--   001..013
-- Purpose:
--   - seed a deterministic first published workbench release
--   - seed one Windows x64 artifact
--   - prove catalog/download surface has a known-good row
-- =========================================================

begin;

do $$
declare
  v_actor uuid := 'df749a8a-618d-46a2-9c16-e201743d4532'::uuid;
  v_release_id uuid := '77777777-7777-7777-7777-777777777777'::uuid;
  v_artifact_id uuid := '88888888-8888-8888-8888-888888888888'::uuid;
  v_release_key text := 'contract-registry-workbench-v0.1.0';
  v_file_name text := 'contract-registry-workbench-windows-x64-v0.1.0.zip';
  v_storage_path text;
begin
  if not exists (
    select 1
    from auth.users
    where id = v_actor
  ) then
    raise exception 'BOOTSTRAP_ACTOR_NOT_FOUND';
  end if;

  v_storage_path := contract_registry.workbench_artifact_storage_path_v1(
    v_release_key,
    'windows',
    'x64',
    v_file_name
  );

  insert into contract_registry.workbench_releases (
    id,
    release_key,
    title,
    version_text,
    channel,
    release_status,
    release_notes,
    released_at,
    created_at,
    created_by,
    updated_at,
    updated_by
  )
  values (
    v_release_id,
    v_release_key,
    'Contract Registry Workbench',
    '0.1.0',
    'stable',
    'published',
    'Bootstrap published workbench release for hosted portal proof.',
    '2026-03-13T02:15:00Z'::timestamptz,
    '2026-03-13T02:15:00Z'::timestamptz,
    v_actor,
    '2026-03-13T02:15:00Z'::timestamptz,
    v_actor
  )
  on conflict (id) do update
  set
    release_key = excluded.release_key,
    title = excluded.title,
    version_text = excluded.version_text,
    channel = excluded.channel,
    release_status = excluded.release_status,
    release_notes = excluded.release_notes,
    released_at = excluded.released_at,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;

  insert into contract_registry.workbench_release_artifacts (
    id,
    workbench_release_id,
    platform_key,
    architecture_key,
    artifact_kind,
    file_name,
    storage_path,
    file_sha256,
    file_size_bytes,
    signature_status,
    signature_ref,
    is_active,
    created_at,
    created_by
  )
  values (
    v_artifact_id,
    v_release_id,
    'windows',
    'x64',
    'archive',
    v_file_name,
    v_storage_path,
    '9999999999999999999999999999999999999999999999999999999999999999',
    1048576,
    'signed',
    'releases/workbench/contract-registry-workbench-v0.1.0/windows/x64/contract-registry-workbench-windows-x64-v0.1.0.zip.sig',
    true,
    '2026-03-13T02:15:00Z'::timestamptz,
    v_actor
  )
  on conflict (id) do update
  set
    workbench_release_id = excluded.workbench_release_id,
    platform_key = excluded.platform_key,
    architecture_key = excluded.architecture_key,
    artifact_kind = excluded.artifact_kind,
    file_name = excluded.file_name,
    storage_path = excluded.storage_path,
    file_sha256 = excluded.file_sha256,
    file_size_bytes = excluded.file_size_bytes,
    signature_status = excluded.signature_status,
    signature_ref = excluded.signature_ref,
    is_active = excluded.is_active;

end
$$;

commit;