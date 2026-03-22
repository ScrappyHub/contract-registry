-- =========================================================
-- CONTRACT REGISTRY — BOOTSTRAP 001B
-- SQL Editor bootstrap with seeded auth context
-- Requires:
--   select set_config('request.jwt.claim.sub','<user-uuid>', true);
--   select auth.uid();
-- =========================================================

begin;

do $$
declare
  v_org_id uuid;
  v_contract_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_CONTEXT_MISSING_SUB';
  end if;

  -- -------------------------------------------------------
  -- 1) Create org via canonical helper if missing
  -- -------------------------------------------------------
  select o.id
    into v_org_id
  from contract_registry.organizations o
  where o.slug = 'contract-registry-test-org';

  if v_org_id is null then
    select x.id
      into v_org_id
    from contract_registry.create_organization_v1(
      'contract-registry-test-org',
      'Contract Registry Test Org'
    ) as x;
  end if;

  if v_org_id is null then
    raise exception 'BOOTSTRAP_ORG_CREATE_FAILED';
  end if;

  -- -------------------------------------------------------
  -- 2) Billing account if missing
  -- -------------------------------------------------------
  if not exists (
    select 1
    from billing.accounts a
    where a.organization_id = v_org_id
  ) then
    perform billing.create_account_v1(v_org_id, 'trial');
  end if;

  -- -------------------------------------------------------
  -- 3) Baseline entitlements
  -- -------------------------------------------------------
  perform billing.upsert_entitlement_v1(
    v_org_id,
    'contract_registry.write',
    true,
    null
  );

  perform billing.upsert_entitlement_v1(
    v_org_id,
    'contract_registry.release',
    true,
    null
  );

  perform billing.upsert_entitlement_v1(
    v_org_id,
    'contract_registry.overlay.manage',
    true,
    null
  );

  perform billing.upsert_entitlement_v1(
    v_org_id,
    'contract_registry.api.access',
    true,
    null
  );

  -- -------------------------------------------------------
  -- 4) Contract if missing
  -- -------------------------------------------------------
  select c.id
    into v_contract_id
  from contract_registry.contracts c
  where c.organization_id = v_org_id
    and c.contract_key = 'example.contract.v1';

  if v_contract_id is null then
    select x.id
      into v_contract_id
    from contract_registry.create_contract_v1(
      v_org_id,
      'example.contract.v1',
      'Example Contract',
      'Bootstrap validation contract'
    ) as x;
  end if;

  if v_contract_id is null then
    raise exception 'BOOTSTRAP_CONTRACT_CREATE_FAILED';
  end if;

  -- -------------------------------------------------------
  -- 5) Initial version if missing
  -- -------------------------------------------------------
  if not exists (
    select 1
    from contract_registry.contract_versions cv
    where cv.contract_id = v_contract_id
      and cv.version_no = 1
  ) then
    perform contract_registry.create_contract_version_v1(
      v_contract_id,
      'v1',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'contracts/example.contract.v1/source.json',
      'Bootstrap initial version'
    );
  end if;
end
$$;

commit;