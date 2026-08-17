-- أجهزة مسجّلة (حدّ 2 لكل مستخدم) + تلميحات آخر دخول في user_session_state.
-- ADMIN_HOOK: ربط لوحة الإدارة بسجلات الجلسات الحية وإجبار الخروج عن بُعد يتطلّب Edge Function + service_role.
--
-- ملاحظة نشر: إن وُجد جدول public.user_devices قديماً بلا عمود user_id، فإن
-- CREATE TABLE IF NOT EXISTS لا يُعيد إنشاءه فيفشل الفهرس على user_id (42703).
-- نُسقط الجدول القديم ثم نُنشئ البنية الصحيحة (بيانات الأجهزة تُبنى من التطبيق).

BEGIN;

-- يضمن وجود الجدول إن لم تُنفَّذ 20260335_user_session_and_audit.sql بعد.
CREATE TABLE IF NOT EXISTS public.user_session_state (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  session_epoch bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.user_session_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_session_state_own_all ON public.user_session_state;
CREATE POLICY user_session_state_own_all ON public.user_session_state
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

ALTER TABLE public.user_session_state
  ADD COLUMN IF NOT EXISTS last_signin_city text,
  ADD COLUMN IF NOT EXISTS last_signin_device text;

-- استبدال التوقيع السابق (بدون بارامترات) بتوقيع واحد يقبل تلميحات اختيارية.
DROP FUNCTION IF EXISTS public.bump_user_session_epoch();

CREATE OR REPLACE FUNCTION public.bump_user_session_epoch(
  p_city text DEFAULT NULL,
  p_device_label text DEFAULT NULL
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
    last_signin_device
  )
  VALUES (
    u,
    1,
    NULLIF(TRIM(p_city), ''),
    NULLIF(TRIM(p_device_label), '')
  )
  ON CONFLICT (user_id) DO UPDATE
  SET
    session_epoch = public.user_session_state.session_epoch + 1,
    last_signin_city = COALESCE(NULLIF(TRIM(p_city), ''), public.user_session_state.last_signin_city),
    last_signin_device = COALESCE(NULLIF(TRIM(p_device_label), ''), public.user_session_state.last_signin_device),
    updated_at = timezone('utc', now())
  RETURNING session_epoch INTO e;

  RETURN e;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_user_session_epoch(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bump_user_session_epoch(text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- user_devices — حدّ جهازين نشطين لكل مستخدم
-- ---------------------------------------------------------------------------
-- إن وُجد جدول بنفس الاسم من مشروع/نسخة قديمة بلا user_id نُسقطه فقط.
DO $$
BEGIN
  IF to_regclass('public.user_devices') IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'user_devices'
         AND column_name = 'user_id'
     ) THEN
    DROP TABLE public.user_devices CASCADE;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.user_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_fingerprint text NOT NULL,
  device_label text,
  city text,
  platform text,
  last_seen timestamptz NOT NULL DEFAULT timezone('utc', now()),
  created_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT user_devices_user_fingerprint_unique UNIQUE (user_id, device_fingerprint)
);

CREATE INDEX IF NOT EXISTS user_devices_user_id_idx ON public.user_devices (user_id);

ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_devices_select_own ON public.user_devices;
CREATE POLICY user_devices_select_own ON public.user_devices
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS user_devices_delete_own ON public.user_devices;
CREATE POLICY user_devices_delete_own ON public.user_devices
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.register_user_device_slot(
  p_device text,
  p_city text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  j json;
  fp text;
  lbl text;
  plat text;
  cnt int;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  BEGIN
    j := p_device::json;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_device_json');
  END;

  fp := nullif(trim(coalesce(j->>'install_id', '')), '');
  IF fp IS NULL OR length(fp) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_install_id');
  END IF;

  lbl := nullif(trim(coalesce(j->>'label', '')), '');
  plat := nullif(trim(lower(coalesce(j->>'platform', ''))), '');

  SELECT count(*)::int INTO cnt FROM public.user_devices d WHERE d.user_id = uid;

  IF EXISTS (
    SELECT 1 FROM public.user_devices d
    WHERE d.user_id = uid AND d.device_fingerprint = fp
  ) THEN
    UPDATE public.user_devices
    SET
      last_seen = timezone('utc', now()),
      device_label = coalesce(lbl, device_label),
      city = coalesce(nullif(trim(p_city), ''), city),
      platform = coalesce(plat, platform)
    WHERE user_id = uid AND device_fingerprint = fp;

    RETURN jsonb_build_object('ok', true, 'action', 'touched');
  END IF;

  IF cnt >= 2 THEN
    RETURN jsonb_build_object(
      'ok', false,
      'code', 'device_limit',
      'max', 2
    );
  END IF;

  INSERT INTO public.user_devices (
    user_id,
    device_fingerprint,
    device_label,
    city,
    platform
  )
  VALUES (
    uid,
    fp,
    lbl,
    nullif(trim(p_city), ''),
    plat
  );

  RETURN jsonb_build_object('ok', true, 'action', 'inserted');
END;
$$;

REVOKE ALL ON FUNCTION public.register_user_device_slot(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_user_device_slot(text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.clear_user_devices_except_current(p_device text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  j json;
  fp text;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  BEGIN
    j := p_device::json;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_device_json');
  END;

  fp := nullif(trim(coalesce(j->>'install_id', '')), '');
  IF fp IS NULL OR length(fp) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_install_id');
  END IF;

  DELETE FROM public.user_devices d
  WHERE d.user_id = uid AND d.device_fingerprint IS DISTINCT FROM fp;

  PERFORM public.bump_user_session_epoch();

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.clear_user_devices_except_current(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_user_devices_except_current(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_user_device_slot(p_device text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  j json;
  fp text;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  BEGIN
    j := p_device::json;
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_device_json');
  END;

  fp := nullif(trim(coalesce(j->>'install_id', '')), '');
  IF fp IS NULL OR length(fp) < 8 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_install_id');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_devices d
    WHERE d.user_id = uid AND d.device_fingerprint = fp
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'device_not_registered');
  END IF;

  UPDATE public.user_devices
  SET last_seen = timezone('utc', now())
  WHERE user_id = uid AND device_fingerprint = fp;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.reconcile_user_device_slot(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_user_device_slot(text) TO authenticated;

COMMIT;
