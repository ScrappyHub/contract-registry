-- =========================================================
-- CONTRACT REGISTRY — MIGRATION 011C
-- Align billing.accounts.billing_state to hosted plan law
-- Depends on:
--   001..011B
-- Purpose:
--   - allow billing_state values that match hosted plan keys
--   - preserve deterministic hosted tier law
-- =========================================================

begin;

alter table billing.accounts
  drop constraint if exists billing_accounts_state_chk;

alter table billing.accounts
  add constraint billing_accounts_state_chk
  check (
    billing_state in (
      'trial',
      'starter',
      'pro',
      'business',
      'enterprise',
      'suspended',
      'canceled'
    )
  );

commit;