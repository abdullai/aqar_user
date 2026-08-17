-- جسر للعميل: is_device_known / register_device (p_username + p_device_id نص)
-- كانت الاستدعاءات تُرجع 400 لعدم وجود الدوال في قاعدة الإنتاج.
-- تربط بنفس منطق get_security_username_for_login وجدول user_devices (حدّ جهازين).

BEGIN;

CREATE OR REPLACE FUNCTION public._resolve_user_id_from_login_digits(p_digits text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  v_uid uuid;
BEGIN
  IF length(v) != 10 THEN
    RETURN NULL;
  END IF;

  IF v ~ '^700' THEN
    SELECT up.user_id INTO v_uid
    FROM public.users_profiles up
    WHERE regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g') = v
    LIMIT 1;

    IF v_uid IS NULL THEN
      SELECT up.user_id INTO v_uid
      FROM public.users_profiles up
      WHERE regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = v
      LIMIT 1;
    END IF;

    IF v_uid IS NULL THEN
      SELECT up.user_id INTO v_uid
      FROM public.users_profiles up
      WHERE regexp_replace(coalesce(up.license_no::text, ''), '\D', '', 'g') = v
      LIMIT 1;
    END IF;
  ELSE
    SELECT up.user_id INTO v_uid
    FROM public.users_profiles up
    WHERE regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = v
    LIMIT 1;

    IF v_uid IS NULL THEN
      SELECT up.user_id INTO v_uid
      FROM public.users_profiles up
      WHERE regexp_replace(coalesce(up.license_no::text, ''), '\D', '', 'g') = v
      LIMIT 1;
    END IF;

    IF v_uid IS NULL THEN
      SELECT up.user_id INTO v_uid
      FROM public.users_profiles up
      WHERE regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g') = v
      LIMIT 1;
    END IF;
  END IF;

  RETURN v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public._resolve_user_id_from_login_digits(text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.is_device_known(
  p_username text,
  p_device_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sess uuid := auth.uid();
  canon text := regexp_replace(trim(coalesce(p_username, '')), '\D', '', 'g');
  fp text := nullif(trim(coalesce(p_device_id, '')), '');
  resolved uuid;
BEGIN
  IF sess IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF fp IS NULL OR length(fp) < 4 THEN
    RETURN false;
  END IF;

  resolved := public._resolve_user_id_from_login_digits(canon);
  IF resolved IS NULL OR resolved IS DISTINCT FROM sess THEN
    RETURN false;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.user_devices d
    WHERE d.user_id = resolved
      AND d.device_fingerprint = fp
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.register_device(
  p_username text,
  p_device_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  sess uuid := auth.uid();
  canon text := regexp_replace(trim(coalesce(p_username, '')), '\D', '', 'g');
  fp text := nullif(trim(coalesce(p_device_id, '')), '');
  resolved uuid;
  cnt int;
BEGIN
  IF sess IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF fp IS NULL OR length(fp) < 4 THEN
    RETURN;
  END IF;

  resolved := public._resolve_user_id_from_login_digits(canon);
  IF resolved IS NULL OR resolved IS DISTINCT FROM sess THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_devices d
    WHERE d.user_id = resolved AND d.device_fingerprint = fp
  ) THEN
    UPDATE public.user_devices
    SET last_seen = timezone('utc', now())
    WHERE user_id = resolved AND device_fingerprint = fp;
    RETURN;
  END IF;

  SELECT count(*)::int INTO cnt FROM public.user_devices d WHERE d.user_id = resolved;
  IF cnt >= 2 THEN
    RETURN;
  END IF;

  INSERT INTO public.user_devices (
    user_id,
    device_fingerprint,
    device_label,
    city,
    platform
  )
  VALUES (
    resolved,
    fp,
    null,
    null,
    null
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_device_known(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_device(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_device_known(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_device(text, text) TO authenticated;

COMMIT;
