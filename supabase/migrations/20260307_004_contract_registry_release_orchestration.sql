-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 004
-- Release orchestration:
--   release_jobs
--   job_events
--   helper functions
--   append-only event model
--   RLS
-- Depends on:
--   001_contract_registry_foundation.sql
--   002_contract_registry_contract_authoring_core.sql
--   003_contract_registry_overlays.sql
-- Rooted-style posture:
--   deterministic state model
--   explicit job/event boundaries
--   minimal helper surface
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Release jobs
-- ---------------------------------------------------------

create table if not exists contract_registry.release_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  contract_version_id uuid not null,
  job_type text not null,
  job_status text not null,
  requested_by uuid not null,
  started_at timestamptz null,
  finished_at timestamptz null,
  runner_ref text null,
  error_code text null,
  error_detail text null,
  created_at timestamptz not null default now(),

  constraint release_jobs_organization_fk
    foreign key (organization_id)
    references contract_registry.organizations(id)
    on delete cascade,

  constraint release_jobs_contract_version_fk
    foreign key (contract_version_id)
    references contract_registry.contract_versions(id)
    on delete cascade,

  constraint release_jobs_job_type_chk
    check (job_type in ('release','verify','rebuild_effective_sets')),

  constraint release_jobs_job_status_chk
    check (job_status in ('queued','running','succeeded','failed','cancelled')),

  constraint release_jobs_runner_ref_chk
    check (runner_ref is null or length(btrim(runner_ref)) > 0),

  constraint release_jobs_error_code_chk
    check (error_code is null or length(btrim(error_code)) > 0)
);

-- ---------------------------------------------------------
-- 2) Append-only job events
-- ---------------------------------------------------------

create table if not exists contract_registry.job_events (
  id bigint generated always as identity primary key,
  job_id uuid not null,
  event_utc timestamptz not null default now(),
  event_type text not null,
  message text not null,
  event_json jsonb not null default '{}'::jsonb,

  constraint job_events_job_fk
    foreign key (job_id)
    references contract_registry.release_jobs(id)
    on delete cascade,

  constraint job_events_event_type_chk
    check (length(btrim(event_type)) > 0),

  constraint job_events_message_chk
    check (length(btrim(message)) > 0)
);

-- ---------------------------------------------------------
-- 3) Indexes
-- ---------------------------------------------------------

create index if not exists release_jobs_org_created_at_idx
  on contract_registry.release_jobs(organization_id, created_at desc);

create index if not exists release_jobs_contract_version_created_at_idx
  on contract_registry.release_jobs(contract_version_id, created_at desc);

create index if not exists release_jobs_status_created_at_idx
  on contract_registry.release_jobs(job_status, created_at desc);

create index if not exists release_jobs_requested_by_created_at_idx
  on contract_registry.release_jobs(requested_by, created_at desc);

create index if not exists job_events_job_event_utc_idx
  on contract_registry.job_events(job_id, event_utc);

create index if not exists job_events_job_id_idx
  on contract_registry.job_events(job_id);

-- ---------------------------------------------------------
-- 4) Helper functions
-- ---------------------------------------------------------

create or replace function contract_registry.contract_version_org_id_v1(
  p_contract_version_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select c.organization_id
  from contract_registry.contract_versions cv
  join contract_registry.contracts c
    on c.id = cv.contract_id
  where cv.id = p_contract_version_id
$$;

revoke all on function contract_registry.contract_version_org_id_v1(uuid) from public;
grant execute on function contract_registry.contract_version_org_id_v1(uuid) to authenticated;

create or replace function contract_registry.release_job_org_id_v1(
  p_release_job_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select rj.organization_id
  from contract_registry.release_jobs rj
  where rj.id = p_release_job_id
$$;

revoke all on function contract_registry.release_job_org_id_v1(uuid) from public;
grant execute on function contract_registry.release_job_org_id_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_release_v1(
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

revoke all on function contract_registry.user_can_release_v1(uuid) from public;
grant execute on function contract_registry.user_can_release_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_manage_release_jobs_v1(
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

revoke all on function contract_registry.user_can_manage_release_jobs_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_release_jobs_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 5) Integrity triggers
-- ---------------------------------------------------------

create or replace function contract_registry_private.enforce_release_job_integrity_v1()
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
    raise exception 'RELEASE_JOB_ORG_CONTRACT_VERSION_MISMATCH';
  end if;

  if new.job_status = 'queued' then
    if new.started_at is not null or new.finished_at is not null then
      raise exception 'QUEUED_JOB_CANNOT_HAVE_STARTED_OR_FINISHED_AT';
    end if;
  end if;

  if new.job_status = 'running' then
    if new.started_at is null then
      raise exception 'RUNNING_JOB_REQUIRES_STARTED_AT';
    end if;
    if new.finished_at is not null then
      raise exception 'RUNNING_JOB_CANNOT_HAVE_FINISHED_AT';
    end if;
  end if;

  if new.job_status in ('succeeded','failed','cancelled') then
    if new.finished_at is null then
      raise exception 'FINAL_JOB_STATE_REQUIRES_FINISHED_AT';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_release_jobs_integrity_v1
  on contract_registry.release_jobs;

create trigger trg_release_jobs_integrity_v1
before insert or update on contract_registry.release_jobs
for each row
execute function contract_registry_private.enforce_release_job_integrity_v1();

create or replace function contract_registry_private.job_events_append_only_v1()
returns trigger
language plpgsql
security invoker
as $$
begin
  raise exception 'JOB_EVENTS_APPEND_ONLY';
end;
$$;

drop trigger if exists trg_job_events_no_update_v1
  on contract_registry.job_events;

create trigger trg_job_events_no_update_v1
before update on contract_registry.job_events
for each row
execute function contract_registry_private.job_events_append_only_v1();

drop trigger if exists trg_job_events_no_delete_v1
  on contract_registry.job_events;

create trigger trg_job_events_no_delete_v1
before delete on contract_registry.job_events
for each row
execute function contract_registry_private.job_events_append_only_v1();

-- ---------------------------------------------------------
-- 6) Privileges
-- ---------------------------------------------------------

grant select, insert, update, delete on contract_registry.release_jobs to authenticated;
grant select, insert on contract_registry.job_events to authenticated;

grant usage, select on sequence contract_registry.job_events_id_seq to authenticated;

-- ---------------------------------------------------------
-- 7) RLS
-- ---------------------------------------------------------

alter table contract_registry.release_jobs enable row level security;
alter table contract_registry.release_jobs force row level security;

alter table contract_registry.job_events enable row level security;
alter table contract_registry.job_events force row level security;

-- ---------------------------------------------------------
-- 8) RLS policies: release_jobs
-- ---------------------------------------------------------

drop policy if exists release_jobs_select_member_v1
  on contract_registry.release_jobs;

create policy release_jobs_select_member_v1
on contract_registry.release_jobs
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(organization_id)
);

drop policy if exists release_jobs_insert_release_manager_v1
  on contract_registry.release_jobs;

create policy release_jobs_insert_release_manager_v1
on contract_registry.release_jobs
for insert
to authenticated
with check (
  contract_registry.user_can_release_v1(organization_id)
);

drop policy if exists release_jobs_update_release_manager_v1
  on contract_registry.release_jobs;

create policy release_jobs_update_release_manager_v1
on contract_registry.release_jobs
for update
to authenticated
using (
  contract_registry.user_can_manage_release_jobs_v1(organization_id)
)
with check (
  contract_registry.user_can_manage_release_jobs_v1(organization_id)
);

drop policy if exists release_jobs_delete_owner_admin_v1
  on contract_registry.release_jobs;

create policy release_jobs_delete_owner_admin_v1
on contract_registry.release_jobs
for delete
to authenticated
using (
  contract_registry.user_has_org_role_v1(organization_id, array['owner','admin'])
);

-- ---------------------------------------------------------
-- 9) RLS policies: job_events
-- ---------------------------------------------------------

drop policy if exists job_events_select_member_v1
  on contract_registry.job_events;

create policy job_events_select_member_v1
on contract_registry.job_events
for select
to authenticated
using (
  contract_registry.user_is_org_member_v1(
    contract_registry.release_job_org_id_v1(job_id)
  )
);

drop policy if exists job_events_insert_release_manager_v1
  on contract_registry.job_events;

create policy job_events_insert_release_manager_v1
on contract_registry.job_events
for insert
to authenticated
with check (
  contract_registry.user_can_manage_release_jobs_v1(
    contract_registry.release_job_org_id_v1(job_id)
  )
);

-- no update/delete policies on purpose; append-only model

-- ---------------------------------------------------------
-- 10) Bootstrap helper: create release job
-- ---------------------------------------------------------

create or replace function contract_registry.create_release_job_v1(
  p_contract_version_id uuid,
  p_job_type text,
  p_runner_ref text default null
)
returns contract_registry.release_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
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

  if p_job_type not in ('release','verify','rebuild_effective_sets') then
    raise exception 'INVALID_JOB_TYPE';
  end if;

  if not contract_registry.user_can_release_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_RELEASE';
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
    p_job_type,
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

revoke all on function contract_registry.create_release_job_v1(uuid, text, text) from public;
grant execute on function contract_registry.create_release_job_v1(uuid, text, text) to authenticated;

-- ---------------------------------------------------------
-- 11) Helper: append job event
-- ---------------------------------------------------------

create or replace function contract_registry.append_job_event_v1(
  p_job_id uuid,
  p_event_type text,
  p_message text,
  p_event_json jsonb default '{}'::jsonb
)
returns contract_registry.job_events
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.job_events;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.release_job_org_id_v1(p_job_id);

  if v_org_id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_release_jobs_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_JOB_EVENT_APPEND';
  end if;

  insert into contract_registry.job_events (
    job_id,
    event_type,
    message,
    event_json
  )
  values (
    p_job_id,
    trim(p_event_type),
    trim(p_message),
    coalesce(p_event_json, '{}'::jsonb)
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.append_job_event_v1(uuid, text, text, jsonb) from public;
grant execute on function contract_registry.append_job_event_v1(uuid, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------
-- 12) Helper: mark job running
-- ---------------------------------------------------------

create or replace function contract_registry.mark_release_job_running_v1(
  p_job_id uuid,
  p_runner_ref text default null
)
returns contract_registry.release_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.release_jobs;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.release_job_org_id_v1(p_job_id);

  if v_org_id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_release_jobs_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_JOB_MANAGE';
  end if;

  update contract_registry.release_jobs
     set job_status = 'running',
         started_at = coalesce(started_at, now()),
         runner_ref = coalesce(nullif(trim(p_runner_ref), ''), runner_ref)
   where id = p_job_id
   returning * into v_row;

  if v_row.id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  insert into contract_registry.job_events (
    job_id,
    event_type,
    message,
    event_json
  )
  values (
    v_row.id,
    'job.running',
    'Release job marked running',
    jsonb_build_object(
      'job_status', v_row.job_status,
      'runner_ref', v_row.runner_ref,
      'updated_by', v_uid
    )
  );

  return v_row;
end;
$$;

revoke all on function contract_registry.mark_release_job_running_v1(uuid, text) from public;
grant execute on function contract_registry.mark_release_job_running_v1(uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 13) Helper: mark job succeeded
-- ---------------------------------------------------------

create or replace function contract_registry.mark_release_job_succeeded_v1(
  p_job_id uuid
)
returns contract_registry.release_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.release_jobs;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.release_job_org_id_v1(p_job_id);

  if v_org_id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_release_jobs_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_JOB_MANAGE';
  end if;

  update contract_registry.release_jobs
     set job_status = 'succeeded',
         started_at = coalesce(started_at, now()),
         finished_at = now(),
         error_code = null,
         error_detail = null
   where id = p_job_id
   returning * into v_row;

  if v_row.id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  insert into contract_registry.job_events (
    job_id,
    event_type,
    message,
    event_json
  )
  values (
    v_row.id,
    'job.succeeded',
    'Release job marked succeeded',
    jsonb_build_object(
      'job_status', v_row.job_status,
      'updated_by', v_uid
    )
  );

  return v_row;
end;
$$;

revoke all on function contract_registry.mark_release_job_succeeded_v1(uuid) from public;
grant execute on function contract_registry.mark_release_job_succeeded_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 14) Helper: mark job failed
-- ---------------------------------------------------------

create or replace function contract_registry.mark_release_job_failed_v1(
  p_job_id uuid,
  p_error_code text,
  p_error_detail text default null
)
returns contract_registry.release_jobs
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, contract_registry_private
as $$
declare
  v_uid uuid;
  v_org_id uuid;
  v_row contract_registry.release_jobs;
begin
  v_uid := contract_registry_private.auth_uid_required_v1();
  v_org_id := contract_registry.release_job_org_id_v1(p_job_id);

  if v_org_id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_release_jobs_v1(v_org_id) then
    raise exception 'ACCESS_DENIED_JOB_MANAGE';
  end if;

  update contract_registry.release_jobs
     set job_status = 'failed',
         started_at = coalesce(started_at, now()),
         finished_at = now(),
         error_code = trim(p_error_code),
         error_detail = p_error_detail
   where id = p_job_id
   returning * into v_row;

  if v_row.id is null then
    raise exception 'RELEASE_JOB_NOT_FOUND';
  end if;

  insert into contract_registry.job_events (
    job_id,
    event_type,
    message,
    event_json
  )
  values (
    v_row.id,
    'job.failed',
    'Release job marked failed',
    jsonb_build_object(
      'job_status', v_row.job_status,
      'error_code', v_row.error_code,
      'updated_by', v_uid
    )
  );

  return v_row;
end;
$$;

revoke all on function contract_registry.mark_release_job_failed_v1(uuid, text, text) from public;
grant execute on function contract_registry.mark_release_job_failed_v1(uuid, text, text) to authenticated;

commit;