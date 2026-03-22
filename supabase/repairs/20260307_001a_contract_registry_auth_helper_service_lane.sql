-- =========================================================
-- CONTRACT REGISTRY — REPAIR 001A
-- Allow SQL-editor / service-lane bootstrap when auth.uid() is null
-- Rooted rule:
--   prefer auth.uid()
--   allow explicit created_by / updated_by fallback
--   fail only if neither exists
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) organizations helper
-- ---------------------------------------------------------

create or replace function contract_registry_private.set_created_by_from_auth_uid_v1()
returns trigger
language plpgsql
security invoker
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();

  if tg_op = 'INSERT' then
    if v_uid is not null then
      if new.created_by is null then
        new.created_by := v_uid;
      end if;
    else
      if new.created_by is null then
        raise exception 'AUTH_CONTEXT_MISSING_SUB_AND_CREATED_BY_MISSING';
      end if;
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------
-- 2) contracts / versions / overlays helper
-- ---------------------------------------------------------

create or replace function contract_registry_private.set_created_by_updated_by_from_auth_uid_v1()
returns trigger
language plpgsql
security invoker
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();

  if tg_op = 'INSERT' then
    if v_uid is not null then
      if new.created_by is null then
        new.created_by := v_uid;
      end if;
      if new.updated_by is null then
        new.updated_by := v_uid;
      end if;
    else
      if new.created_by is null then
        raise exception 'AUTH_CONTEXT_MISSING_SUB_AND_CREATED_BY_MISSING';
      end if;
      if new.updated_by is null then
        new.updated_by := new.created_by;
      end if;
    end if;

  elsif tg_op = 'UPDATE' then
    if v_uid is not null then
      new.updated_by := v_uid;
    else
      if new.updated_by is null then
        if old.updated_by is not null then
          new.updated_by := old.updated_by;
        elsif old.created_by is not null then
          new.updated_by := old.created_by;
        else
          raise exception 'AUTH_CONTEXT_MISSING_SUB_AND_UPDATED_BY_MISSING';
        end if;
      end if;
    end if;
  end if;

  return new;
end;
$$;

commit;