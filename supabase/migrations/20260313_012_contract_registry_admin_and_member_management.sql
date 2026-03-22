-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 012
-- Admin surfaces + support readonly boundaries + member management RPCs
-- Depends on:
--   001..011B
-- Rooted-style posture:
--   org admin is explicit
--   support readonly is explicit
--   member management is capability-gated
--   no hidden write paths
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Invitations
-- ---------------------------------------------------------

create table if not exists contract_registry.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references contract_registry.organizations(id) on delete cascade,
  email text not null,
  role text not null references contract_registry.role_definitions(role_key),
  status text not null default 'pending',
  invite_token uuid not null default gen_random_uuid(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now(),
  created_by uuid not null,
  accepted_at timestamptz null,
  accepted_by uuid null,

  constraint organization_invitations_email_chk
    check (length(btrim(email)) > 0),

  constraint organization_invitations_status_chk
    check (status in ('pending','accepted','revoked','expired'))
);

create index if not exists organization_invitations_org_idx
  on contract_registry.organization_invitations(organization_id, status, created_at desc);

create index if not exists organization_invitations_email_idx
  on contract_registry.organization_invitations(lower(email));

create unique index if not exists organization_invitations_pending_unique_idx
  on contract_registry.organization_invitations(organization_id, lower(email))
  where status = 'pending';

-- ---------------------------------------------------------
-- 2) Support grants
-- Explicit hosted support boundary
-- ---------------------------------------------------------

create table if not exists contract_registry.support_access_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references contract_registry.organizations(id) on delete cascade,
  granted_user_id uuid not null,
  granted_role text not null references contract_registry.role_definitions(role_key),
  access_status text not null default 'active',
  reason text null,
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  revoked_at timestamptz null,
  revoked_by uuid null,

  constraint support_access_grants_role_chk
    check (granted_role = 'support_readonly'),

  constraint support_access_grants_status_chk
    check (access_status in ('active','revoked','expired'))
);

create index if not exists support_access_grants_org_idx
  on contract_registry.support_access_grants(organization_id, access_status);

create index if not exists support_access_grants_user_idx
  on contract_registry.support_access_grants(granted_user_id, access_status);

-- ---------------------------------------------------------
-- 3) Capability helpers for member/admin/support law
-- ---------------------------------------------------------

create or replace function contract_registry.user_can_manage_members_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'admin.members.manage'
  )
$$;

revoke all on function contract_registry.user_can_manage_members_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_members_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_manage_org_billed_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select contract_registry.user_has_capability_billed_v1(
    p_organization_id,
    'admin.org.manage'
  )
$$;

revoke all on function contract_registry.user_can_manage_org_billed_v1(uuid) from public;
grant execute on function contract_registry.user_can_manage_org_billed_v1(uuid) to authenticated;

create or replace function contract_registry.user_has_active_support_grant_v1(
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
    from contract_registry.support_access_grants sag
    where sag.organization_id = p_organization_id
      and sag.granted_user_id = auth.uid()
      and sag.granted_role = 'support_readonly'
      and sag.access_status = 'active'
      and (sag.expires_at is null or sag.expires_at > now())
  )
$$;

revoke all on function contract_registry.user_has_active_support_grant_v1(uuid) from public;
grant execute on function contract_registry.user_has_active_support_grant_v1(uuid) to authenticated;

create or replace function contract_registry.user_can_support_read_org_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, contract_registry
as $$
  select
    contract_registry.user_has_role_in_org_v1(p_organization_id, 'owner')
    or contract_registry.user_has_role_in_org_v1(p_organization_id, 'admin')
    or contract_registry.user_has_active_support_grant_v1(p_organization_id)
$$;

revoke all on function contract_registry.user_can_support_read_org_v1(uuid) from public;
grant execute on function contract_registry.user_can_support_read_org_v1(uuid) to authenticated;

-- ---------------------------------------------------------
-- 4) Admin/support views
-- ---------------------------------------------------------

create or replace view contract_registry.v_admin_member_directory_v1 as
select
  om.organization_id,
  o.slug as organization_slug,
  om.user_id,
  om.role,
  rd.title as role_title,
  om.status,
  om.created_at,
  om.created_by
from contract_registry.organization_members om
join contract_registry.organizations o
  on o.id = om.organization_id
join contract_registry.role_definitions rd
  on rd.role_key = om.role;

grant select on contract_registry.v_admin_member_directory_v1 to authenticated;

create or replace view contract_registry.v_admin_pending_invitations_v1 as
select
  oi.id,
  oi.organization_id,
  o.slug as organization_slug,
  oi.email,
  oi.role,
  rd.title as role_title,
  oi.status,
  oi.expires_at,
  oi.created_at,
  oi.created_by,
  oi.accepted_at,
  oi.accepted_by
from contract_registry.organization_invitations oi
join contract_registry.organizations o
  on o.id = oi.organization_id
join contract_registry.role_definitions rd
  on rd.role_key = oi.role;

grant select on contract_registry.v_admin_pending_invitations_v1 to authenticated;

create or replace view contract_registry.v_support_access_grants_v1 as
select
  sag.id,
  sag.organization_id,
  o.slug as organization_slug,
  sag.granted_user_id,
  sag.granted_role,
  sag.access_status,
  sag.reason,
  sag.expires_at,
  sag.created_at,
  sag.created_by,
  sag.revoked_at,
  sag.revoked_by
from contract_registry.support_access_grants sag
join contract_registry.organizations o
  on o.id = sag.organization_id;

grant select on contract_registry.v_support_access_grants_v1 to authenticated;

-- ---------------------------------------------------------
-- 5) App RPCs — invitations and membership
-- ---------------------------------------------------------

create or replace function contract_registry.app_invite_org_member_v1(
  p_organization_id uuid,
  p_email text,
  p_role text
)
returns contract_registry.organization_invitations
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_row contract_registry.organization_invitations;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_manage_members_billed_v1(p_organization_id) then
    raise exception 'ORG_MEMBER_MANAGE_NOT_ALLOWED';
  end if;

  if not exists (
    select 1
    from contract_registry.role_definitions rd
    where rd.role_key = trim(p_role)
      and rd.is_active = true
  ) then
    raise exception 'ROLE_NOT_FOUND';
  end if;

  insert into contract_registry.organization_invitations (
    organization_id,
    email,
    role,
    status,
    created_by
  )
  values (
    p_organization_id,
    lower(trim(p_email)),
    trim(p_role),
    'pending',
    v_actor
  )
  returning *
  into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_invite_org_member_v1(uuid, text, text) from public;
grant execute on function contract_registry.app_invite_org_member_v1(uuid, text, text) to authenticated;

create or replace function contract_registry.app_revoke_org_invitation_v1(
  p_invitation_id uuid
)
returns contract_registry.organization_invitations
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_org_id uuid;
  v_row contract_registry.organization_invitations;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  select oi.organization_id
    into v_org_id
  from contract_registry.organization_invitations oi
  where oi.id = p_invitation_id;

  if v_org_id is null then
    raise exception 'INVITATION_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_members_billed_v1(v_org_id) then
    raise exception 'ORG_MEMBER_MANAGE_NOT_ALLOWED';
  end if;

  update contract_registry.organization_invitations
  set status = 'revoked'
  where id = p_invitation_id
  returning *
  into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_revoke_org_invitation_v1(uuid) from public;
grant execute on function contract_registry.app_revoke_org_invitation_v1(uuid) to authenticated;

create or replace function contract_registry.app_change_org_member_role_v1(
  p_organization_id uuid,
  p_user_id uuid,
  p_role text
)
returns contract_registry.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_row contract_registry.organization_members;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_manage_members_billed_v1(p_organization_id) then
    raise exception 'ORG_MEMBER_MANAGE_NOT_ALLOWED';
  end if;

  if not exists (
    select 1
    from contract_registry.role_definitions rd
    where rd.role_key = trim(p_role)
      and rd.is_active = true
  ) then
    raise exception 'ROLE_NOT_FOUND';
  end if;

  update contract_registry.organization_members
  set role = trim(p_role)
  where organization_id = p_organization_id
    and user_id = p_user_id
  returning *
  into v_row;

  if v_row.id is null then
    raise exception 'ORG_MEMBER_NOT_FOUND';
  end if;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_change_org_member_role_v1(uuid, uuid, text) from public;
grant execute on function contract_registry.app_change_org_member_role_v1(uuid, uuid, text) to authenticated;

create or replace function contract_registry.app_set_org_member_status_v1(
  p_organization_id uuid,
  p_user_id uuid,
  p_status text
)
returns contract_registry.organization_members
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_row contract_registry.organization_members;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_manage_members_billed_v1(p_organization_id) then
    raise exception 'ORG_MEMBER_MANAGE_NOT_ALLOWED';
  end if;

  if trim(p_status) not in ('active','inactive') then
    raise exception 'ORG_MEMBER_STATUS_INVALID';
  end if;

  update contract_registry.organization_members
  set status = trim(p_status)
  where organization_id = p_organization_id
    and user_id = p_user_id
  returning *
  into v_row;

  if v_row.id is null then
    raise exception 'ORG_MEMBER_NOT_FOUND';
  end if;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_set_org_member_status_v1(uuid, uuid, text) from public;
grant execute on function contract_registry.app_set_org_member_status_v1(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------
-- 6) App RPCs — support readonly grants
-- ---------------------------------------------------------

create or replace function contract_registry.app_grant_support_readonly_v1(
  p_organization_id uuid,
  p_granted_user_id uuid,
  p_reason text,
  p_expires_at timestamptz default null
)
returns contract_registry.support_access_grants
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_row contract_registry.support_access_grants;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  if not contract_registry.user_can_manage_org_billed_v1(p_organization_id) then
    raise exception 'ORG_ADMIN_NOT_ALLOWED';
  end if;

  insert into contract_registry.support_access_grants (
    organization_id,
    granted_user_id,
    granted_role,
    access_status,
    reason,
    expires_at,
    created_by
  )
  values (
    p_organization_id,
    p_granted_user_id,
    'support_readonly',
    'active',
    p_reason,
    p_expires_at,
    v_actor
  )
  returning *
  into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_grant_support_readonly_v1(uuid, uuid, text, timestamptz) from public;
grant execute on function contract_registry.app_grant_support_readonly_v1(uuid, uuid, text, timestamptz) to authenticated;

create or replace function contract_registry.app_revoke_support_readonly_v1(
  p_support_access_grant_id uuid
)
returns contract_registry.support_access_grants
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry
as $$
declare
  v_actor uuid;
  v_org_id uuid;
  v_row contract_registry.support_access_grants;
begin
  v_actor := contract_registry.auth_uid_required_v1();

  select sag.organization_id
    into v_org_id
  from contract_registry.support_access_grants sag
  where sag.id = p_support_access_grant_id;

  if v_org_id is null then
    raise exception 'SUPPORT_ACCESS_GRANT_NOT_FOUND';
  end if;

  if not contract_registry.user_can_manage_org_billed_v1(v_org_id) then
    raise exception 'ORG_ADMIN_NOT_ALLOWED';
  end if;

  update contract_registry.support_access_grants
  set
    access_status = 'revoked',
    revoked_at = now(),
    revoked_by = v_actor
  where id = p_support_access_grant_id
  returning *
  into v_row;

  return v_row;
end;
$$;

revoke all on function contract_registry.app_revoke_support_readonly_v1(uuid) from public;
grant execute on function contract_registry.app_revoke_support_readonly_v1(uuid) to authenticated;

commit;