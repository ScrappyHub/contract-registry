-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 013
-- Workbench distribution + download portal + download audit
-- Depends on:
--   001..012
-- Rooted-style posture:
--   download surface is entitlement-gated
--   artifacts are explicit
--   download events are append-only
--   no hidden/public distribution path
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Workbench releases
-- ---------------------------------------------------------

create table if not exists contract_registry.workbench_releases (
  id uuid primary key default gen_random_uuid(),
  release_key text not null unique,
  title text not null,
  version_text text not null,
  channel text not null default 'stable',
  release_status text not null default 'draft',
  release_notes text null,
  released_at timestamptz null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  updated_at timestamptz not null default now(),
  updated_by uuid not null,

  constraint workbench_releases_release_key_chk
    check (length(btrim(release_key)) > 0),

  constraint workbench_releases_title_chk
    check (length(btrim(title)) > 0),

  constraint workbench_releases_version_text_chk
    check (length(btrim(version_text)) > 0),

  constraint workbench_releases_channel_chk
    check (channel in ('stable','beta','internal')),

  constraint workbench_releases_status_chk
    check (release_status in ('draft','published','retired'))
);

create index if not exists workbench_releases_status_idx
  on contract_registry.workbench_releases(release_status, released_at desc);

-- ---------------------------------------------------------
-- 2) Workbench release artifacts
-- ---------------------------------------------------------

create table if not exists contract_registry.workbench_release_artifacts (
  id uuid primary key default gen_random_uuid(),
  workbench_release_id uuid not null references contract_registry.workbench_releases(id) on delete cascade,
  platform_key text not null,
  architecture_key text not null,
  artifact_kind text not null default 'installer',
  file_name text not null,
  storage_path text not null,
  file_sha256 text not null,
  file_size_bytes bigint null,
  signature_status text not null default 'unsigned',
  signature_ref text null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null,

  constraint workbench_release_artifacts_platform_chk
    check (platform_key in ('windows','macos','linux')),

  constraint workbench_release_artifacts_arch_chk
    check (architecture_key in ('x64','arm64')),

  constraint workbench_release_artifacts_kind_chk
    check (artifact_kind in ('installer','portable','archive','manifest')),

  constraint workbench_release_artifacts_file_name_chk
    check (length(btrim(file_name)) > 0),

  constraint workbench_release_artifacts_sha256_chk
    check (file_sha256 ~ '^[0-9a-f]{64}$'),

  constraint workbench_release_artifacts_signature_status_chk
    check (signature_status in ('unsigned','signed','verified'))
);

create index if not exists workbench_release_artifacts_release_idx
  on contract_registry.workbench_release_artifacts(workbench_release_id, is_active);

create unique index if not exists workbench_release_artifacts_unique_variant_idx
  on contract_registry.workbench_release_artifacts(workbench_release_id, platform_key, architecture_key, artifact_kind)
  where is_active = true;

-- ---------------------------------------------------------
-- 3) Download events (append-only audit)
-- ---------------------------------------------------------

create table if not exists contract_registry.workbench_download_events (
  id bigserial primary key,
  organization_id uuid not null references contract_registry.organizations(id) on delete cascade,
  workbench_release_id uuid not null references contract_registry.workbench_releases(id) on delete restrict,
  workbench_release_artifact_id uuid not null references contract_registry.workbench_release_artifacts(id) on delete restrict,
  user_id uuid not null,
  event_utc timestamptz not null default now(),
  event_type text not null default 'download.requested',
  delivery_kind text not null default 'storage-path',
  client_ip inet null,
  user_agent text null,
  note text null,

  constraint workbench_download_events_event_type_chk
    check (event_type in ('download.requested','download.granted','download.completed')),

  constraint workbench_download_events_delivery_kind_chk
    check (delivery_kind in ('storage-path','signed-url','token'))
);

create index if not exists workbench_download_events_org_idx
  on contract_registry.workbench_download_events(organization_id, event_utc desc);

create index if not exists workbench_download_events_user_idx
  on contract_registry.workbench_download_events(user_id, event_utc desc);

create index if not exists workbench_download_events_release_idx
  on contract_registry.workbench_download_events(workbench_release_id, event_utc desc);

-- ---------------------------------------------------------
-- 4) Storage path law for workbench artifacts
-- Bucket must be releases for now.
-- Path convention:
--   releases/workbench/<release_key>/<platform>/<arch>/<file>
-- ---------------------------------------------------------

create or replace function contract_registry.workbench_artifact_storage_path_v1(
  p_release_key text,
  p_platform_key text,
  p_architecture_key text,
  p_file_name text
)
returns text
language sql
immutable
as $$
  select
    'releases/workbench/'
    || lower(trim(p_release_key))
    || '/'
    || lower(trim(p_platform_key))
    || '/'
    || lower(trim(p_architecture_key))
    || '/'
    || trim(p_file_name)
$$;

revoke all on function contract_registry.workbench_artifact_storage_path_v1(text, text, text, text) from public;
grant execute on function contract_registry.workbench_artifact_storage_path_v1(text, text, text, text) to authenticated;

create or replace function contract_registry_private.enforce_workbench_artifact_storage_path_law_v1()
returns trigger
language plpgsql
security invoker
as $$
begin
  if not contract_registry.storage_path_valid_v1(new.storage_path) then
    raise exception 'INVALID_WORKBENCH_ARTIFACT_STORAGE_PATH';
  end if;

  if contract_registry.storage_bucket_from_path_v1(new.storage_path) <> 'releases' then
    raise exception 'WORKBENCH_ARTIFACT_BUCKET_MUST_BE_RELEASES';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_workbench_release_artifacts_storage_path_law_v1
  on contract_registry.workbench_release_artifacts;

create trigger trg_workbench_release_artifacts_storage_path_law_v1
before insert or update on contract_registry.workbench_release_artifacts
for each row
execute function contract_registry_private.enforce_workbench_artifact_storage_path_law_v1();

-- ---------------------------------------------------------
-- 5) Capability helpers
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_view_workbench_portal_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_can_download_workbench_billed_v1(p_organization_id)
$$;

revoke all on function contract_registry.user_can_view_workbench_portal_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_view_workbench_portal_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_access_workbench_artifact_v1(
  p_organization_id uuid,
  p_workbench_release_artifact_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    contract_registry.user_can_download_workbench_billed_v1(p_organization_id)
    and exists (
      select 1
      from contract_registry.workbench_release_artifacts wra
      join contract_registry.workbench_releases wr
        on wr.id = wra.workbench_release_id
      where wra.id = p_workbench_release_artifact_id
        and wra.is_active = true
        and wr.release_status = 'published'
    )
$$;

revoke all on function contract_registry.user_can_access_workbench_artifact_v1(uuid, uuid) from public;
grant execute on function contract_registry.user_can_access_workbench_artifact_v1(uuid, uuid) to authenticated;

-- ---------------------------------------------------------
-- 6) Portal views
-- ---------------------------------------------------------

create or replace view contract_registry.v_workbench_release_catalog_v1 as
select
  wr.id as workbench_release_id,
  wr.release_key,
  wr.title,
  wr.version_text,
  wr.channel,
  wr.release_status,
  wr.release_notes,
  wr.released_at,
  wra.id as workbench_release_artifact_id,
  wra.platform_key,
  wra.architecture_key,
  wra.artifact_kind,
  wra.file_name,
  wra.storage_path,
  wra.file_sha256,
  wra.file_size_bytes,
  wra.signature_status,
  wra.signature_ref,
  wra.is_active
from contract_registry.workbench_releases wr
join contract_registry.workbench_release_artifacts wra
  on wra.workbench_release_id = wr.id
where wr.release_status = 'published'
  and wra.is_active = true;

grant select on contract_registry.v_workbench_release_catalog_v1 to authenticated;

create or replace view contract_registry.v_workbench_download_audit_v1 as
select
  wde.id,
  wde.organization_id,
  o.slug as organization_slug,
  wde.workbench_release_id,
  wr.release_key,
  wr.version_text,
  wde.workbench_release_artifact_id,
  wra.platform_key,
  wra.architecture_key,
  wra.artifact_kind,
  wra.file_name,
  wde.user_id,
  wde.event_utc,
  wde.event_type,
  wde.delivery_kind,
  wde.client_ip,
  wde.user_agent,
  wde.note
from contract_registry.workbench_download_events wde
join contract_registry.organizations o
  on o.id = wde.organization_id
join contract_registry.workbench_releases wr
  on wr.id = wde.workbench_release_id
join contract_registry.workbench_release_artifacts wra
  on wra.id = wde.workbench_release_artifact_id;

grant select on contract_registry.v_workbench_download_audit_v1 to authenticated;

-- ---------------------------------------------------------
-- 7) App RPCs
-- ---------------------------------------------------------

create or replace function contract_registry.app_list_workbench_releases_v1(
  p_organization_id uuid
)
returns setof contract_registry.v_workbench_release_catalog_v1
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select *
  from contract_registry.v_workbench_release_catalog_v1 v
  where contract_registry.user_can_view_workbench_portal_billed_v1(p_organization_id)
$$;

revoke all on function contract_registry.app_list_workbench_releases_v1(uuid) from public;
grant execute on function contract_registry.app_list_workbench_releases_v1(uuid) to authenticated;

create or replace function contract_registry.app_get_workbench_download_v1(
  p_organization_id uuid,
  p_workbench_release_artifact_id uuid,
  p_client_ip inet default null,
  p_user_agent text default null
)
returns table (
  workbench_release_artifact_id uuid,
  storage_path text,
  file_name text,
  file_sha256 text,
  signature_status text
)
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_release_id uuid;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_access_workbench_artifact_v1(
    p_organization_id,
    p_workbench_release_artifact_id
  ) then
    raise exception 'WORKBENCH_DOWNLOAD_NOT_ALLOWED';
  end if;

  select wra.workbench_release_id
    into v_release_id
  from contract_registry.workbench_release_artifacts wra
  where wra.id = p_workbench_release_artifact_id
    and wra.is_active = true;

  if v_release_id is null then
    raise exception 'WORKBENCH_ARTIFACT_NOT_FOUND';
  end if;

  insert into contract_registry.workbench_download_events (
    organization_id,
    workbench_release_id,
    workbench_release_artifact_id,
    user_id,
    event_type,
    delivery_kind,
    client_ip,
    user_agent,
    note
  )
  values (
    p_organization_id,
    v_release_id,
    p_workbench_release_artifact_id,
    v_actor,
    'download.granted',
    'storage-path',
    p_client_ip,
    p_user_agent,
    'app_get_workbench_download_v1'
  );

  return query
  select
    wra.id,
    wra.storage_path,
    wra.file_name,
    wra.file_sha256,
    wra.signature_status
  from contract_registry.workbench_release_artifacts wra
  join contract_registry.workbench_releases wr
    on wr.id = wra.workbench_release_id
  where wra.id = p_workbench_release_artifact_id
    and wra.is_active = true
    and wr.release_status = 'published';
end;
$$;

revoke all on function contract_registry.app_get_workbench_download_v1(uuid, uuid, inet, text) from public;
grant execute on function contract_registry.app_get_workbench_download_v1(uuid, uuid, inet, text) to authenticated;

create or replace function contract_registry.app_record_workbench_download_completed_v1(
  p_organization_id uuid,
  p_workbench_release_artifact_id uuid,
  p_client_ip inet default null,
  p_user_agent text default null
)
returns contract_registry.workbench_download_events
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_release_id uuid;
  v_row contract_registry.workbench_download_events;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_access_workbench_artifact_v1(
    p_organization_id,
    p_workbench_release_artifact_id
  ) then
    raise exception 'WORKBENCH_DOWNLOAD_NOT_ALLOWED';
  end if;

  select wra.workbench_release_id
    into v_release_id
  from contract_registry.workbench_release_artifacts wra
  where wra.id = p_workbench_release_artifact_id
    and wra.is_active = true;

  if v_release_id is null then
    raise exception 'WORKBENCH_ARTIFACT_NOT_FOUND';
  end if;

  insert into contract_registry.workbench_download_events (
    organization_id,
    workbench_release_id,
    workbench_release_artifact_id,
    user_id,
    event_type,
    delivery_kind,
    client_ip,
    user_agent,
    note
  )
  values (
    p_organization_id,
    v_release_id,
    p_workbench_release_artifact_id,
    v_actor,
    'download.completed',
    'storage-path',
    p_client_ip,
    p_user_agent,
    'app_record_workbench_download_completed_v1'
  )
  returning *
  into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_record_workbench_download_completed_v1(uuid, uuid, inet, text) from public;
grant execute on function contract_registry.app_record_workbench_download_completed_v1(uuid, uuid, inet, text) to authenticated;

commit;