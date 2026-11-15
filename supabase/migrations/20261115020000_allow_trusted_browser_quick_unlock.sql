BEGIN;

CREATE OR REPLACE FUNCTION public.eval_login_trust(
  p_platform text,
  p_device_fingerprint text,
  p_login_method text DEFAULT 'password'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  plat text := lower(trim(coalesce(p_platform, 'unknown')));
  method text := lower(trim(coalesce(p_login_method, 'password')));
  native_mobile boolean;
  trusted boolean;
  skip_nafath boolean;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  native_mobile := public.auth_platform_is_native_mobile(plat);
  trusted := public._auth_device_trusted(uid, p_device_fingerprint);

  IF method = 'fast_unlock' AND NOT trusted THEN
    RETURN jsonb_build_object(
      'ok', false,
      'otp_required', true,
      'trusted', false,
      'fully_authenticated', false,
      'error', 'device_not_trusted'
    );
  END IF;

  IF NOT native_mobile THEN
    skip_nafath := public.auth_cfg_bool('nafath_skip_otp_web', false);
    RETURN jsonb_build_object(
      'ok', true,
      'otp_required', true,
      'trusted', trusted,
      'fully_authenticated', false,
      'native_mobile', false,
      'nafath_can_skip', (method = 'nafath' AND skip_nafath)
    );
  END IF;

  skip_nafath := public.auth_cfg_bool('nafath_skip_otp_native', true);

  IF method = 'nafath' AND skip_nafath THEN
    RETURN jsonb_build_object(
      'ok', true,
      'otp_required', false,
      'trusted', trusted,
      'fully_authenticated', false,
      'native_mobile', true,
      'nafath_can_skip', true
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'otp_required', NOT trusted,
    'trusted', trusted,
    'fully_authenticated', false,
    'native_mobile', true,
    'nafath_can_skip', false
  );
END;
$$;

COMMIT;
