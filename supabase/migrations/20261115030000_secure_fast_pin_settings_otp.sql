BEGIN;

CREATE OR REPLACE FUNCTION public.request_fast_pin_settings_otp(
  p_username text,
  p_platform text,
  p_device_fingerprint text,
  p_action text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  action text := lower(trim(coalesce(p_action, '')));
  fingerprint text := trim(coalesce(p_device_fingerprint, ''));
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF action NOT IN ('enable', 'change', 'disable') THEN
    RAISE EXCEPTION 'invalid_action';
  END IF;
  IF length(fingerprint) < 8 OR NOT public._auth_device_trusted(uid, fingerprint) THEN
    RAISE EXCEPTION 'device_not_trusted';
  END IF;

  RETURN public._auth_issue_otp_challenge(
    p_username,
    lower(trim(coalesce(p_platform, 'unknown'))),
    fingerprint,
    'fast_pin_settings_' || action,
    'security_settings'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_fast_pin_settings_otp(
  p_challenge_id uuid,
  p_code text,
  p_device_fingerprint text,
  p_action text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  action text := lower(trim(coalesce(p_action, '')));
  fingerprint text := trim(coalesce(p_device_fingerprint, ''));
  challenge public.auth_login_challenges%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  IF action NOT IN ('enable', 'change', 'disable') OR p_challenge_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_challenge');
  END IF;

  SELECT * INTO challenge
  FROM public.auth_login_challenges
  WHERE id = p_challenge_id
    AND user_id = uid
  FOR UPDATE;

  IF challenge.id IS NULL
     OR challenge.purpose <> 'fast_pin_settings_' || action
     OR challenge.device_fingerprint IS DISTINCT FROM fingerprint
     OR NOT public._auth_device_trusted(uid, fingerprint) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'challenge_not_found');
  END IF;
  IF challenge.status <> 'pending'
     OR challenge.otp_expires_at IS NULL
     OR challenge.otp_expires_at <= timezone('utc', now()) THEN
    IF challenge.status = 'pending' THEN
      UPDATE public.auth_login_challenges
      SET status = 'expired',
          otp_dev_plain = NULL
      WHERE id = challenge.id;
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  RETURN public.verify_login_otp(p_challenge_id, p_code);
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_inactive_auth_dev_otp()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cleared integer;
BEGIN
  UPDATE public.auth_login_challenges
  SET otp_dev_plain = NULL
  WHERE otp_dev_plain IS NOT NULL
    AND (
      status <> 'pending'
      OR otp_expires_at IS NULL
      OR otp_expires_at <= timezone('utc', now())
    );
  GET DIAGNOSTICS cleared = ROW_COUNT;
  RETURN cleared;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_inactive_auth_dev_otp_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status <> 'pending'
     OR NEW.otp_expires_at IS NULL
     OR NEW.otp_expires_at <= timezone('utc', now()) THEN
    NEW.otp_dev_plain := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS auth_login_challenges_clear_dev_otp
  ON public.auth_login_challenges;
CREATE TRIGGER auth_login_challenges_clear_dev_otp
BEFORE INSERT OR UPDATE ON public.auth_login_challenges
FOR EACH ROW
EXECUTE FUNCTION public.clear_inactive_auth_dev_otp_trigger();

UPDATE public.auth_login_challenges
SET otp_dev_plain = NULL
WHERE otp_dev_plain IS NOT NULL
  AND (
    status <> 'pending'
    OR otp_expires_at IS NULL
    OR otp_expires_at <= timezone('utc', now())
  );

CREATE OR REPLACE FUNCTION public.peek_dev_login_otp(p_challenge_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  challenge public.auth_login_challenges%ROWTYPE;
  provider text := public.auth_otp_provider();
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  IF provider NOT IN ('internal', 'internal_dev') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_internal');
  END IF;

  SELECT * INTO challenge
  FROM public.auth_login_challenges
  WHERE id = p_challenge_id
    AND user_id = uid
  LIMIT 1;

  IF challenge.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'challenge_not_found');
  END IF;
  IF challenge.status <> 'pending'
     OR challenge.otp_expires_at IS NULL
     OR challenge.otp_expires_at <= timezone('utc', now()) THEN
    UPDATE public.auth_login_challenges
    SET status = CASE
          WHEN status = 'pending' THEN 'expired'
          ELSE status
        END,
        otp_dev_plain = NULL
    WHERE id = challenge.id;
    RETURN jsonb_build_object('ok', false, 'error', 'unavailable');
  END IF;
  IF challenge.otp_dev_plain IS NULL OR length(challenge.otp_dev_plain) <> 6 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_dev_code');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'code', challenge.otp_dev_plain,
    'challenge_id', challenge.id,
    'expires_at', challenge.otp_expires_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.request_fast_pin_settings_otp(text, text, text, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_fast_pin_settings_otp(uuid, text, text, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.clear_inactive_auth_dev_otp() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clear_inactive_auth_dev_otp_trigger()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.peek_dev_login_otp(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.request_fast_pin_settings_otp(text, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_fast_pin_settings_otp(uuid, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.peek_dev_login_otp(uuid) TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (
      SELECT 1 FROM cron.job
      WHERE jobname = 'clear_inactive_auth_dev_otp'
        AND username = current_user
    ) THEN
      PERFORM cron.unschedule('clear_inactive_auth_dev_otp');
    END IF;
    PERFORM cron.schedule(
      'clear_inactive_auth_dev_otp',
      '*/5 * * * *',
      'SELECT public.clear_inactive_auth_dev_otp();'
    );
  ELSE
    RAISE NOTICE 'pg_cron is not installed; expired development OTP cleanup is not scheduled';
  END IF;
END;
$$;

COMMIT;
