-- =========================================================
-- CONTRACT REGISTRY — BOOTSTRAP 002
-- Release orchestration validation (admin lane)
-- Uses direct inserts for proofing hosted layer
-- =========================================================

begin;

-- ---------------------------------------------------------
-- 1) Create release job if missing
-- ---------------------------------------------------------
insert into contract_registry.release_jobs (
  id,
  organization_id,
  contract_version_id,
  job_type,
  job_status,
  requested_by,
  started_at,
  finished_at,
  runner_ref,
  error_code,
  error_detail
)
values (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  '44444444-4444-4444-4444-444444444444',
  'release',
  'succeeded',
  'df749a8a-618d-46a2-9c16-e201743d4532',
  now(),
  now(),
  'admin-lane-bootstrap',
  null,
  null
)
on conflict (id) do update
set
  job_status = excluded.job_status,
  started_at = excluded.started_at,
  finished_at = excluded.finished_at,
  runner_ref = excluded.runner_ref,
  error_code = excluded.error_code,
  error_detail = excluded.error_detail;

-- ---------------------------------------------------------
-- 2) Append deterministic job events
-- ---------------------------------------------------------
insert into contract_registry.job_events (
  job_id,
  event_type,
  message,
  event_json
)
values
(
  '55555555-5555-5555-5555-555555555555',
  'job.created',
  'Release job created',
  jsonb_build_object('source','admin-lane-bootstrap')
),
(
  '55555555-5555-5555-5555-555555555555',
  'job.running',
  'Release job marked running',
  jsonb_build_object('runner_ref','admin-lane-bootstrap')
),
(
  '55555555-5555-5555-5555-555555555555',
  'job.succeeded',
  'Release job marked succeeded',
  jsonb_build_object('result','ok')
);

-- ---------------------------------------------------------
-- 3) Create contract release if missing
-- ---------------------------------------------------------
insert into contract_registry.contract_releases (
  id,
  contract_version_id,
  organization_id,
  release_status,
  release_kind,
  released_at,
  released_by,
  packet_id,
  packet_root_storage_path,
  release_receipt_storage_path,
  release_receipt_sha256,
  effective_sets_receipt_storage_path,
  effective_sets_receipt_sha256,
  verification_receipt_storage_path,
  verification_receipt_sha256
)
values (
  '66666666-6666-6666-6666-666666666666',
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111111',
  'succeeded',
  'manual',
  now(),
  'df749a8a-618d-46a2-9c16-e201743d4532',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'releases/example.contract.v1/packet_root',
  'releases/example.contract.v1/release_receipt.txt',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  'releases/example.contract.v1/effective_sets_receipt.txt',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  'releases/example.contract.v1/verification_receipt.txt',
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
)
on conflict (id) do update
set
  release_status = excluded.release_status,
  release_kind = excluded.release_kind,
  released_at = excluded.released_at,
  released_by = excluded.released_by,
  packet_id = excluded.packet_id,
  packet_root_storage_path = excluded.packet_root_storage_path,
  release_receipt_storage_path = excluded.release_receipt_storage_path,
  release_receipt_sha256 = excluded.release_receipt_sha256,
  effective_sets_receipt_storage_path = excluded.effective_sets_receipt_storage_path,
  effective_sets_receipt_sha256 = excluded.effective_sets_receipt_sha256,
  verification_receipt_storage_path = excluded.verification_receipt_storage_path,
  verification_receipt_sha256 = excluded.verification_receipt_sha256;

-- ---------------------------------------------------------
-- 4) Create release packet row
-- ---------------------------------------------------------
insert into contract_registry.release_packets (
  release_id,
  packet_id,
  packet_root_storage_path,
  manifest_sha256,
  packet_dir_sha256,
  packet_created_utc,
  signing_state
)
values (
  '66666666-6666-6666-6666-666666666666',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'releases/example.contract.v1/packet_root',
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  '1212121212121212121212121212121212121212121212121212121212121212',
  now(),
  'verified'
)
on conflict (release_id) do update
set
  packet_id = excluded.packet_id,
  packet_root_storage_path = excluded.packet_root_storage_path,
  manifest_sha256 = excluded.manifest_sha256,
  packet_dir_sha256 = excluded.packet_dir_sha256,
  packet_created_utc = excluded.packet_created_utc,
  signing_state = excluded.signing_state;

-- ---------------------------------------------------------
-- 5) Create release receipts row
-- ---------------------------------------------------------
insert into contract_registry.release_receipts (
  release_id,
  tier0_receipt_storage_path,
  tier0_receipt_sha256,
  golden_receipt_storage_path,
  golden_receipt_sha256,
  verification_receipt_storage_path,
  verification_receipt_sha256
)
values (
  '66666666-6666-6666-6666-666666666666',
  'releases/example.contract.v1/tier0_receipt.txt',
  '1313131313131313131313131313131313131313131313131313131313131313',
  'releases/example.contract.v1/golden_receipt.txt',
  '1414141414141414141414141414141414141414141414141414141414141414',
  'releases/example.contract.v1/verification_receipt.txt',
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
)
on conflict (release_id) do update
set
  tier0_receipt_storage_path = excluded.tier0_receipt_storage_path,
  tier0_receipt_sha256 = excluded.tier0_receipt_sha256,
  golden_receipt_storage_path = excluded.golden_receipt_storage_path,
  golden_receipt_sha256 = excluded.golden_receipt_sha256,
  verification_receipt_storage_path = excluded.verification_receipt_storage_path,
  verification_receipt_sha256 = excluded.verification_receipt_sha256;

-- ---------------------------------------------------------
-- 6) Create effective sets row
-- ---------------------------------------------------------
insert into contract_registry.effective_sets (
  release_id,
  policy_effective_hash,
  schema_effective_hash,
  effective_sets_receipt_storage_path,
  effective_sets_receipt_sha256,
  allow_overrides
)
values (
  '66666666-6666-6666-6666-666666666666',
  '1515151515151515151515151515151515151515151515151515151515151515',
  '1616161616161616161616161616161616161616161616161616161616161616',
  'releases/example.contract.v1/effective_sets_receipt.txt',
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  false
)
on conflict (release_id) do update
set
  policy_effective_hash = excluded.policy_effective_hash,
  schema_effective_hash = excluded.schema_effective_hash,
  effective_sets_receipt_storage_path = excluded.effective_sets_receipt_storage_path,
  effective_sets_receipt_sha256 = excluded.effective_sets_receipt_sha256,
  allow_overrides = excluded.allow_overrides;

commit;