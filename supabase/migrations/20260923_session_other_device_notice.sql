-- تنبيه الجلسة: يظهر فقط عند دخول نفس الحساب من تثبيت/جهاز آخر.
-- يُحفظ معرّف التثبيت وطريقة الدخول والمنصة ووقت الدخول مع كل bump.

BEGIN;

ALTER TABLE public.user_session_state
  ADD COLUMN IF NOT EXISTS last_signin_install_id text,
  ADD COLUMN IF NOT EXISTS last_signin_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_signin_method text,
  ADD COLUMN IF NOT EXISTS last_signin_platform text;

DROP FUNCTION IF EXISTS public.bump_user_session_epoch();
DROP FUNCTION IF EXISTS public.bump_user_session_epoch(text, text);
DROP FUNCTION IF EXISTS public.bump_user_session_epoch(text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.bump_user_session_epoch(
  p_city text DEFAULT NULL,
  p_device_label text DEFAULT NULL,
  p_install_id text DEFAULT NULL,
  p_login_method text DEFAULT NULL,
  p_platform text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  u uuid := auth.uid();
  e bigint;
BEGIN
  IF u IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO public.user_session_state (
    user_id,
    session_epoch,
    last_signin_city,
    last_signin_device,
    last_signin_install_id,
    last_signin_at,
    last_signin_method,
    last_signin_platform
  )
  VALUES (
    u,
    1,
    NULLIF(TRIM(p_city), ''),
    NULLIF(TRIM(p_device_label), ''),
    NULLIF(TRIM(p_install_id), ''),
    timezone('utc', now()),
    NULLIF(TRIM(p_login_method), ''),
    NULLIF(TRIM(p_platform), '')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    session_epoch = public.user_session_state.session_epoch + 1,
    last_signin_city = COALESCE(
      NULLIF(TRIM(p_city), ''),
      public.user_session_state.last_signin_city
    ),
    last_signin_device = COALESCE(
      NULLIF(TRIM(p_device_label), ''),
      public.user_session_state.last_signin_device
    ),
    last_signin_install_id = COALESCE(
      NULLIF(TRIM(p_install_id), ''),
      public.user_session_state.last_signin_install_id
    ),
    last_signin_at = timezone('utc', now()),
    last_signin_method = COALESCE(
      NULLIF(TRIM(p_login_method), ''),
      public.user_session_state.last_signin_method
    ),
    last_signin_platform = COALESCE(
      NULLIF(TRIM(p_platform), ''),
      public.user_session_state.last_signin_platform
    ),
    updated_at = timezone('utc', now())
  RETURNING session_epoch INTO e;

  RETURN e;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_user_session_epoch(text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bump_user_session_epoch(text, text, text, text, text) TO authenticated;

COMMIT;
