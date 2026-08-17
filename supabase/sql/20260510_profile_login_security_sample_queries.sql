-- =============================================================================
-- Login security: sample queries (run in Supabase SQL Editor on the SAME project
-- where migration 20260510140000_users_profiles_login_security_counters.sql ran).
-- =============================================================================
--
-- Schema source:
--   supabase/migrations/20260510140000_users_profiles_login_security_counters.sql
--
-- App wiring (single entry for RPC names + profile select fragment):
--   lib/core/auth/login_security_db.dart
--   lib/screens/verify_screen.dart   → OTP success + profile fetch for greeting
--   lib/services/auth_service.dart   → wrong password → recordFailedPasswordLogin
--   lib/core/utils/profile_greeting_from_row.dart → last_verified_login_at preferred
--
-- Device detail (not replaced by profile counters): public.user_devices
--
-- If query (0) returns zero rows, this database never got the migration (wrong project/branch).

-- 0) Verify columns exist on this connection (expect 4 rows after migration)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users_profiles'
  AND column_name IN (
    'last_verified_login_at',
    'successful_login_count',
    'failed_password_login_count',
    'last_failed_password_at'
  )
ORDER BY column_name;

-- 1) Registered users: last verified OTP login + counters
--    (run only after query 0 shows the four columns)
SELECT
  user_id,
  username,
  last_verified_login_at,
  successful_login_count,
  failed_password_login_count,
  last_failed_password_at
FROM public.users_profiles
ORDER BY last_verified_login_at DESC NULLS LAST
LIMIT 50;

-- 2) Devices per user (schema uses last_seen, not last_seen_at)
SELECT user_id, device_fingerprint, device_label, last_seen, created_at
FROM public.user_devices
ORDER BY last_seen DESC NULLS LAST
LIMIT 50;

-- 3) Recommended ops view: profile counters + each user's most recently active device
--    (one row per user — best default for dashboards; drill into user_devices for full history)
--
--    How to read results:
--    • last_verified_login_at NULL + successful_login_count 0 → user has not completed OTP
--      since record_verified_login_after_otp shipped (or never on this build).
--    • A non-null last_verified with count still 0 can happen if the column was backfilled from
--      legacy last_login_at; the next successful OTP increments successful_login_count.
--    • NULL device_* columns → no row in user_devices for that user_id yet.
SELECT
  up.user_id,
  up.username,
  up.last_verified_login_at,
  up.successful_login_count,
  up.failed_password_login_count,
  up.last_failed_password_at,
  d.device_fingerprint,
  d.device_label,
  d.last_seen AS device_last_seen,
  d.created_at AS device_first_registered
FROM public.users_profiles up
LEFT JOIN LATERAL (
  SELECT
    ud.device_fingerprint,
    ud.device_label,
    ud.last_seen,
    ud.created_at
  FROM public.user_devices ud
  WHERE ud.user_id = up.user_id
  ORDER BY ud.last_seen DESC NULLS LAST
  LIMIT 1
) d ON true
ORDER BY up.last_verified_login_at DESC NULLS LAST
LIMIT 100;

-- 4) Security hint: same device_fingerprint tied to more than one user (unusual — review if non‑empty)
SELECT
  device_fingerprint,
  COUNT(DISTINCT user_id) AS distinct_users
FROM public.user_devices
GROUP BY device_fingerprint
HAVING COUNT(DISTINCT user_id) > 1
ORDER BY distinct_users DESC, device_fingerprint
LIMIT 50;
