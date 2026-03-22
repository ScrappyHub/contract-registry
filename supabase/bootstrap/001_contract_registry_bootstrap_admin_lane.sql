-- =========================================================
-- CONTRACT REGISTRY — BOOTSTRAP 001A
-- SQL Editor / admin bootstrap
-- Uses explicit bootstrap user id
-- =========================================================

begin;

do $$
declare
  v_bootstrap_user uuid := 'df749a8a-618d-46a2-9c16-e201743d4532';
  v_org_id uuid;
  v_contract_id uuid;
  v_account_id uuid;
begin
  if not exists (
    select 1
    from auth.users
    where id = v_bootstrap_user
  ) then
    raise exception 'BOOTSTRAP_USER_NOT_FOUND';
  end if;

  select o.id
    into v_org_id
  from contract_registry.organizations o
  where o.slug = 'contract-registry-test-org';

  if v_org_id is null then
    insert into contract_registry.organizations (
      id,
      slug,
      name,
      created_by,
      is_active
    )
    values (
      gen_random_uuid(),
      'contract-registry-test-org',
      'Contract Registry Test Org',
      v_bootstrap_user,
      true
    )
    returning id into v_org_id;
  end if;

  insert into contract_registry.organization_members (
    organization_id,
    user_id,
    role,
    status,
    created_by
  )
  values (
    v_org_id,
    v_bootstrap_user,
    'owner',
    'active',
    v_bootstrap_user
  )
  on conflict (organization_id, user_id) do update
    set role = excluded.role,
        status = excluded.status;

  select a.id
    into v_account_id
  from billing.accounts a
  where a.organization_id = v_org_id;

  if v_account_id is null then
    insert into billing.accounts (
      id,
      organization_id,
      billing_state
    )
    values (
      gen_random_uuid(),
      v_org_id,
      'trial'
    )
    returning id into v_account_id;
  end if;

  insert into billing.entitlements (
    account_id,
    entitlement_key,
    is_enabled,
    limit_int
  )
  values
    (v_account_id, 'contract_registry.write', true, null),
    (v_account_id, 'contract_registry.release', true, null),
    (v_account_id, 'contract_registry.overlay.manage', true, null),
    (v_account_id, 'contract_registry.api.access', true, null)
  on conflict (account_id, entitlement_key) do update
    set is_enabled = excluded.is_enabled,
        limit_int = excluded.limit_int,
        updated_at = now();

  select c.id
    into v_contract_id
  from contract_registry.contracts c
  where c.organization_id = v_org_id
    and c.contract_key = 'example.contract.v1';

  if v_contract_id is null then
    insert into contract_registry.contracts (
      id,
      organization_id,
      contract_key,
      title,
      description,
      status,
      created_by,
      updated_by
    )
    values (
      gen_random_uuid(),
      v_org_id,
      'example.contract.v1',
      'Example Contract',
      'Bootstrap validation contract',
      'draft',
      v_bootstrap_user,
      v_bootstrap_user
    )
    returning id into v_contract_id;
  end if;

  if not exists (
    select 1
    from contract_registry.contract_versions cv
    where cv.contract_id = v_contract_id
      and cv.version_no = 1
  ) then
    insert into contract_registry.contract_versions (
      id,
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
      gen_random_uuid(),
      v_contract_id,
      1,
      'v1',
      'draft',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'contracts/example.contract.v1/source.json',
      'Bootstrap initial version',
      v_bootstrap_user,
      v_bootstrap_user
    );
  end if;
end
$$;

commit;