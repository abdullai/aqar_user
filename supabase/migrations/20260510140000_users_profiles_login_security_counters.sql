-- Login / security counters on users_profiles + RPCs for OTP completion and failed password.
-- last_verified_login_at: updated only after successful in-app OTP — shown on verify as "previous login".
-- Per-device history: prefer existing public.user_devices (user_id + device_fingerprint); this migration
-- only adds profile-level aggregates.
--
-- Flutter (استدعاءات وأعمدة موحّدة):
--   lib/core/auth/login_security_db.dart
--   lib/screens/verify_screen.dart  → recordVerifiedLoginAfterOtp + usersProfilesSelectForVerifyGreeting
--   lib/services/auth_service.dart  → recordFailedPasswordLogin
--   lib/core/utils/profile_greeting_from_row.dart → lastLoginAt() يفضّل last_verified_login_at
--
-- SQL تشغيل / تدقيق بعد النشر:
--   supabase/sql/20260510_profile_login_security_sample_queries.sql

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS last_verified_login_at timestamptz;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS successful_login_count integer NOT NULL DEFAULT 0;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS failed_password_login_count integer NOT NULL DEFAULT 0;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS last_failed_password_at timestamptz;

COMMENT ON COLUMN public.users_profiles.last_verified_login_at IS
  'Last time the user completed in-app OTP after password login; UI shows this as previous successful session.';
COMMENT ON COLUMN public.users_profiles.successful_login_count IS
  'Incremented once per successful OTP completion (full app sign-in).';
COMMENT ON COLUMN public.users_profiles.failed_password_login_count IS
  'Incremented on wrong password (identifier resolved to a profile).';
COMMENT ON COLUMN public.users_profiles.last_failed_password_at IS
  'Timestamp of the most recent failed password attempt.';

-- Optional legacy column: backfill from last_login_at if present (one-time best effort).
DO $mig$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users_profiles'
      AND column_name = 'last_login_at'
  ) THEN
    UPDATE public.users_profiles up
    SET last_verified_login_at = COALESCE(up.last_verified_login_at, up.last_login_at)
    WHERE up.last_verified_login_at IS NULL
      AND up.last_login_at IS NOT NULL;
  END IF;
END
$mig$;

CREATE OR REPLACE FUNCTION public.record_verified_login_after_otp()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.users_profiles up
  SET
    last_verified_login_at = timezone('utc', now()),
    successful_login_count = COALESCE(up.successful_login_count, 0) + 1
  WHERE up.user_id = v_uid;
END;
$fn$;

REVOKE ALL ON FUNCTION public.record_verified_login_after_otp() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_verified_login_after_otp() TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_verified_login_after_otp() TO service_role;

CREATE OR REPLACE FUNCTION public.record_failed_password_login(p_digits text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn2$
DECLARE
  v text := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  v_uid uuid;
BEGIN
  IF v IS NULL OR length(v) <> 10 THEN
    RETURN;
  END IF;

  -- Match canonical username digits (same idea as get_security_username / device RPCs).
  SELECT up.user_id
  INTO v_uid
  FROM public.users_profiles up
  WHERE regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = v
  LIMIT 1;

  IF v_uid IS NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'users_profiles'
         AND column_name = 'unified_national_number'
     ) THEN
    SELECT up.user_id
    INTO v_uid
    FROM public.users_profiles up
    WHERE regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g') = v
    LIMIT 1;
  END IF;

  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  UPDATE public.users_profiles up
  SET
    failed_password_login_count = COALESCE(up.failed_password_login_count, 0) + 1,
    last_failed_password_at = timezone('utc', now())
  WHERE up.user_id = v_uid;
END;
$fn2$;

REVOKE ALL ON FUNCTION public.record_failed_password_login(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_failed_password_login(text) TO anon;
GRANT EXECUTE ON FUNCTION public.record_failed_password_login(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_failed_password_login(text) TO service_role;

COMMIT;
