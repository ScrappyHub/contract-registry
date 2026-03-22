-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 011D
-- Align billing.account_is_in_good_standing_v1 to hosted plan law
-- Purpose:
--   - hosted plans starter/pro/business/enterprise must count as good standing
--   - preserves trial as good standing
--   - suspended/canceled remain not good standing
-- =========================================================

begin;

create or replace function billing.account_is_in_good_standing_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, billing
as $$
  select exists (
    select 1
    from billing.accounts a
    where a.organization_id = p_organization_id
      and a.billing_state in (
        'trial',
        'starter',
        'pro',
        'business',
        'enterprise'
      )
  )
$$;

revoke all on function billing.account_is_in_good_standing_v1(uuid) from public;
grant execute on function billing.account_is_in_good_standing_v1(uuid) to authenticated;

commit;