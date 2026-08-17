BEGIN;

ALTER TABLE public.in_app_notifications
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_in_app_notifications_user_type_created
  ON public.in_app_notifications (user_id, type, created_at DESC);

DROP FUNCTION IF EXISTS public.request_inapp_otp(text);
DROP FUNCTION IF EXISTS public.verify_inapp_otp(text, text);

CREATE OR REPLACE FUNCTION public._resolve_inapp_otp_profile(p_username text)
RETURNS TABLE(profile_user_id uuid, profile_username text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_username, '')), '\D', '', 'g');
  uid uuid := auth.uid();
BEGIN
  IF length(v) != 10 THEN
    RETURN;
  END IF;

  IF uid IS NOT NULL THEN
    RETURN QUERY
    SELECT
      up.user_id,
      coalesce(nullif(regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g'), ''), v)
    FROM public.users_profiles up
    WHERE up.user_id = uid
      AND (
        regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = v
        OR regexp_replace(coalesce(up.license_no::text, ''), '\D', '', 'g') = v
        OR regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g') = v
      )
    LIMIT 1;

    IF FOUND THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    up.user_id,
    coalesce(nullif(regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g'), ''), v)
  FROM public.users_profiles up
  WHERE regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = v
     OR regexp_replace(coalesce(up.license_no::text, ''), '\D', '', 'g') = v
     OR regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g') = v
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public._resolve_inapp_otp_profile(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.request_inapp_otp(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prof record;
  code text;
  expires_at timestamptz := timezone('utc', now()) + interval '60 seconds';
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prof
  FROM public._resolve_inapp_otp_profile(p_username)
  LIMIT 1;

  IF prof.profile_user_id IS NULL OR prof.profile_user_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'username_not_current_user';
  END IF;

  code := lpad(floor(random() * 10000)::int::text, 4, '0');

  INSERT INTO public.in_app_notifications (
    username,
    user_id,
    type,
    title,
    body,
    data,
    created_at,
    is_read
  ) VALUES (
    prof.profile_username,
    uid,
    'otp',
    'رمز التحقق',
    'رمز التحقق: ' || code,
    jsonb_build_object(
      'code', code,
      'purpose', 'login_or_device_management',
      'expiresAt', to_char(expires_at, 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    ),
    timezone('utc', now()),
    false
  );

  RETURN jsonb_build_object('ok', true, 'expiresAt', expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_inapp_otp(
  p_username text,
  p_code text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prof record;
  digits text := regexp_replace(trim(coalesce(p_code, '')), '\D', '', 'g');
  notif_id uuid;
BEGIN
  IF uid IS NULL OR length(digits) != 4 THEN
    RETURN false;
  END IF;

  SELECT * INTO prof
  FROM public._resolve_inapp_otp_profile(p_username)
  LIMIT 1;

  IF prof.profile_user_id IS NULL OR prof.profile_user_id IS DISTINCT FROM uid THEN
    RETURN false;
  END IF;

  SELECT n.id INTO notif_id
  FROM public.in_app_notifications n
  WHERE n.user_id = uid
    AND n.username = prof.profile_username
    AND lower(trim(coalesce(n.type, ''))) = 'otp'
    AND coalesce(n.data->>'code', '') = digits
    AND coalesce(lower(n.data->>'used') = 'true', false) IS NOT TRUE
    AND coalesce((n.data->>'expiresAt')::timestamptz, timezone('utc', now()) - interval '1 second')
        >= timezone('utc', now())
  ORDER BY n.created_at DESC
  LIMIT 1;

  IF notif_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE public.in_app_notifications
  SET
    is_read = true,
    data = coalesce(data, '{}'::jsonb) ||
      jsonb_build_object(
        'used', true,
        'verifiedAt', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
  WHERE id = notif_id;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.request_inapp_otp(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_inapp_otp(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.request_inapp_otp(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_inapp_otp(text, text) TO authenticated;

COMMIT;
