-- =============================================================================
-- إصلاح عمود verification_request_id إن وُجد كـ uuid + دخول برقم فال/هوية + فريدية بيانات + فال/توقيع
-- نفّذ بعد 20260338_fal_verification_team_join.sql
--
-- الدوال get_login_email / get_login_account_status تطابق أولاً users_profiles.username
-- (عادة رقم الهوية 10 أرقام) ثم license_no (رخصة فال). لا يشترط عمود national_id.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) إصلاح نوع verification_request_id إن أُنشئ خطأً كـ uuid
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'org_join_requests'
      AND column_name = 'verification_request_id'
      AND udt_name = 'uuid'
  ) THEN
    ALTER TABLE public.org_join_requests
      DROP CONSTRAINT IF EXISTS org_join_requests_verification_request_id_fkey;
    ALTER TABLE public.org_join_requests DROP COLUMN verification_request_id;
    ALTER TABLE public.org_join_requests
      ADD COLUMN verification_request_id bigint REFERENCES public.verification_requests (id) ON DELETE SET NULL;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2) أعمدة إضافية (فال / تجميد / توقيع / سجل تجاري موحّد)
-- ---------------------------------------------------------------------------
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fal_license_expires_at timestamptz;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS fal_compliance_hold boolean NOT NULL DEFAULT false;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS signature_storage_path text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS unified_commercial_reg_no text;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS commercial_reg_snapshot jsonb;

COMMENT ON COLUMN public.users_profiles.fal_compliance_hold IS
  'عند true يمنع استخدام التطبيق حتى يُجدَّد رقم فال ساري (واجهة التجديد).';

COMMENT ON COLUMN public.users_profiles.signature_storage_path IS
  'مسار ملف التوقيع في التخزين (مثلاً bucket kyc).';

-- ---------------------------------------------------------------------------
-- 3) تسجيل الدخول: نفس 10 أرقام = هوية/إقامة أو رقم رخصة فال (license_no)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_login_email(p_digits text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  v_uid uuid;
  em text;
BEGIN
  IF length(v) != 10 THEN
    RETURN NULL;
  END IF;

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
    RETURN NULL;
  END IF;

  SELECT u.email INTO em FROM auth.users u WHERE u.id = v_uid LIMIT 1;
  RETURN em;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_login_account_status(p_digits text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  v_uid uuid;
  st text;
BEGIN
  IF length(v) != 10 THEN
    RETURN NULL;
  END IF;

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
    RETURN NULL;
  END IF;

  SELECT COALESCE(nullif(trim(up.status::text), ''), 'active') INTO st
  FROM public.users_profiles up
  WHERE up.user_id = v_uid
  LIMIT 1;

  RETURN st;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_login_email(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_login_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_login_account_status(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_login_account_status(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 4) فريدية (بعد تنظيف أي تكرارات يدوياً إن فشل الإنشاء)
--    البريد: مقارنة case-insensitive | الجوال والرخصة والهوية: أرقام فقط
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_contact_email_norm
  ON public.users_profiles (lower(trim(contact_email)))
  WHERE contact_email IS NOT NULL AND length(trim(contact_email)) > 3;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_contact_phone_digits
  ON public.users_profiles (regexp_replace(coalesce(contact_phone, ''), '\D', '', 'g'))
  WHERE contact_phone IS NOT NULL
    AND length(regexp_replace(coalesce(contact_phone, ''), '\D', '', 'g')) >= 9;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_license_no_digits
  ON public.users_profiles (regexp_replace(coalesce(license_no, ''), '\D', '', 'g'))
  WHERE license_no IS NOT NULL
    AND length(regexp_replace(coalesce(license_no, ''), '\D', '', 'g')) = 10;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users_profiles'
      AND column_name = 'national_id'
  ) THEN
    CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_national_id_digits
      ON public.users_profiles (regexp_replace(coalesce(national_id, ''), '\D', '', 'g'))
      WHERE national_id IS NOT NULL
        AND length(regexp_replace(coalesce(national_id, ''), '\D', '', 'g')) = 10;
  END IF;
END $$;
