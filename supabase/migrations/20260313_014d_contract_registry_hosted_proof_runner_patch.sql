begin;

create or replace function contract_registry.run_hosted_stress_proof_pack_v1(
  p_bootstrap_user_id uuid,
  p_organization_id uuid
)
returns table (
  proof_run_id uuid,
  proof_key text,
  proof_status text,
  total_events bigint,
  pass_events bigint,
  fail_events bigint
)
language plpgsql
security definer
set search_path = pg_catalog, public, contract_registry, billing
as $$
declare
  v_run_id uuid := gen_random_uuid();
  v_proof_key text := 'contract_registry_hosted_proof_' || to_char(now() at time zone 'utc', 'YYYYMMDD_HH24MISS');
  v_plan_before text;
  v_owner_role text;
  v_owner_status text;
  v_member_found boolean := false;
  v_trial_workbench boolean;
  v_starter_workbench boolean;
  v_support_grant_id uuid;
  v_fail_count bigint;
  v_total_count bigint;
  v_pass_count bigint;
begin
  insert into contract_registry.hosted_proof_runs (
    id, proof_key, proof_status, started_at, note
  )
  values (
    v_run_id,
    v_proof_key,
    'running',
    now(),
    'Hosted auth/billing/admin/download proof pack'
  );

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,'proof.start','info','RUN_CREATED','Hosted proof run created',
    jsonb_build_object('bootstrap_user_id', p_bootstrap_user_id, 'organization_id', p_organization_id)
  );

  if not exists (select 1 from auth.users where id = p_bootstrap_user_id) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','fail','BOOTSTRAP_USER_MISSING','Bootstrap user does not exist in auth.users',
      jsonb_build_object('bootstrap_user_id', p_bootstrap_user_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','pass','BOOTSTRAP_USER_EXISTS','Bootstrap user exists',
      jsonb_build_object('bootstrap_user_id', p_bootstrap_user_id)
    );
  end if;

  if not exists (
    select 1 from contract_registry.organizations o
    where o.id = p_organization_id and o.is_active = true
  ) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','fail','ORG_MISSING_OR_INACTIVE','Organization missing or inactive',
      jsonb_build_object('organization_id', p_organization_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','pass','ORG_EXISTS_ACTIVE','Organization exists and is active',
      jsonb_build_object('organization_id', p_organization_id)
    );
  end if;

  select true, om.role, om.status
  into v_member_found, v_owner_role, v_owner_status
  from contract_registry.organization_members om
  where om.organization_id = p_organization_id
    and om.user_id = p_bootstrap_user_id
    and om.status = 'active'
  limit 1;

  if not coalesce(v_member_found, false) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','fail','BOOTSTRAP_MEMBER_MISSING','Bootstrap user is not an active org member',
      jsonb_build_object('organization_id', p_organization_id, 'bootstrap_user_id', p_bootstrap_user_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'proof.precondition','pass','BOOTSTRAP_MEMBER_EXISTS','Bootstrap user is active org member',
      jsonb_build_object('role', v_owner_role, 'status', v_owner_status)
    );
  end if;

  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'contract.read') then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','pass','OWNER_HAS_CONTRACT_READ','Bootstrap member has contract.read','{}'::jsonb);
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','fail','OWNER_MISSING_CONTRACT_READ','Bootstrap member missing contract.read','{}'::jsonb);
  end if;

  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'release.finalize') then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','pass','OWNER_HAS_RELEASE_FINALIZE','Bootstrap member has release.finalize','{}'::jsonb);
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','fail','OWNER_MISSING_RELEASE_FINALIZE','Bootstrap member missing release.finalize','{}'::jsonb);
  end if;

  if contract_registry_private.user_has_capability_in_org_as_user_v1(p_organization_id, p_bootstrap_user_id, 'admin.members.manage') then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','pass','OWNER_HAS_MEMBER_MANAGE','Bootstrap member has admin.members.manage','{}'::jsonb);
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'role.capability','fail','OWNER_MISSING_MEMBER_MANAGE','Bootstrap member missing admin.members.manage','{}'::jsonb);
  end if;

  v_plan_before := billing.organization_plan_key_v1(p_organization_id);

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,'billing.plan','info','PLAN_BEFORE','Plan before proof transition captured',
    jsonb_build_object('plan_key', v_plan_before)
  );

  v_trial_workbench := contract_registry_private.user_can_view_workbench_portal_as_user_v1(p_organization_id, p_bootstrap_user_id);

  if v_plan_before = 'trial' and v_trial_workbench = false then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'billing.gate','pass','TRIAL_BLOCKS_WORKBENCH','Trial plan correctly blocks workbench portal',jsonb_build_object('plan_key', v_plan_before));
  elsif v_plan_before = 'trial' and v_trial_workbench = true then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'billing.gate','fail','TRIAL_UNEXPECTEDLY_ALLOWS_WORKBENCH','Trial plan unexpectedly allows workbench portal',jsonb_build_object('plan_key', v_plan_before));
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'billing.gate','info','TRIAL_PROOF_SKIPPED','Org was not on trial at proof start',jsonb_build_object('plan_key', v_plan_before));
  end if;

  update billing.accounts
  set billing_state = 'starter'
  where organization_id = p_organization_id;

  perform billing.apply_plan_presets_to_account_v1(p_organization_id);

  v_starter_workbench := contract_registry_private.user_can_view_workbench_portal_as_user_v1(p_organization_id, p_bootstrap_user_id);

  if v_starter_workbench then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'billing.gate','pass','STARTER_ALLOWS_WORKBENCH','Starter plan enables workbench portal',jsonb_build_object('plan_key', 'starter'));
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'billing.gate','fail','STARTER_DOES_NOT_ALLOW_WORKBENCH','Starter plan failed to enable workbench portal',jsonb_build_object('plan_key', 'starter'));
  end if;

  insert into contract_registry.support_access_grants (
    organization_id, granted_user_id, granted_role, access_status, reason, created_by
  )
  values (
    p_organization_id, p_bootstrap_user_id, 'support_readonly', 'active',
    'Proof pack self-grant for lifecycle check', p_bootstrap_user_id
  )
  returning id into v_support_grant_id;

  if contract_registry_private.user_has_active_support_grant_as_user_v1(p_organization_id, p_bootstrap_user_id) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'support.grant','pass','SUPPORT_GRANT_ACTIVE','Support readonly grant recognized as active',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'support.grant','fail','SUPPORT_GRANT_NOT_ACTIVE','Support readonly grant not recognized',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  end if;

  update contract_registry.support_access_grants
  set access_status = 'revoked', revoked_at = now(), revoked_by = p_bootstrap_user_id
  where id = v_support_grant_id;

  if not contract_registry_private.user_has_active_support_grant_as_user_v1(p_organization_id, p_bootstrap_user_id) then
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'support.grant','pass','SUPPORT_GRANT_REVOKED','Support readonly grant revoked successfully',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  else
    perform contract_registry_private.append_hosted_proof_event_v1(
      v_run_id,'support.grant','fail','SUPPORT_GRANT_REVOKE_FAILED','Support readonly grant remained active after revoke',
      jsonb_build_object('support_access_grant_id', v_support_grant_id)
    );
  end if;

  if exists (
    select 1
    from contract_registry.v_workbench_release_catalog_v1
    where release_key = 'contract-registry-workbench-v0.1.0'
      and workbench_release_artifact_id = '88888888-8888-8888-8888-888888888888'::uuid
  ) then
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'workbench.catalog','pass','SEEDED_WORKBENCH_VISIBLE','Seeded published workbench release is visible in catalog view','{}'::jsonb);
  else
    perform contract_registry_private.append_hosted_proof_event_v1(v_run_id,'workbench.catalog','fail','SEEDED_WORKBENCH_NOT_VISIBLE','Seeded published workbench release missing from catalog view','{}'::jsonb);
  end if;

  update billing.accounts
  set billing_state = v_plan_before
  where organization_id = p_organization_id;

  perform billing.apply_plan_presets_to_account_v1(p_organization_id);

  perform contract_registry_private.append_hosted_proof_event_v1(
    v_run_id,'billing.plan','info','PLAN_RESTORED','Organization plan restored after proof run',
    jsonb_build_object('plan_key', v_plan_before)
  );

  select count(*) into v_fail_count from contract_registry.hosted_proof_events e where e.proof_run_id = v_run_id and e.event_status = 'fail';
  select count(*) into v_pass_count from contract_registry.hosted_proof_events e where e.proof_run_id = v_run_id and e.event_status = 'pass';
  select count(*) into v_total_count from contract_registry.hosted_proof_events e where e.proof_run_id = v_run_id;

  update contract_registry.hosted_proof_runs
  set proof_status = case when v_fail_count = 0 then 'passed' else 'failed' end,
      finished_at = now()
  where id = v_run_id;

  return query
  select r.id, r.proof_key, r.proof_status, v_total_count, v_pass_count, v_fail_count
  from contract_registry.hosted_proof_runs r
  where r.id = v_run_id;
end;
$$;

commit;