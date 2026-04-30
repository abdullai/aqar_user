-- =============================================================================
-- 20260346: الرقم الوطني الموحّد (700…) + ترتيب بحث تسجيل الدخول + رمز إعلان 10 أرقام
--          + listing_guidance + جدول وثائق الامتثال + حذف عميق للعقار (مالك)
-- نفّذ على Supabase بعد النسخ الاحتياطي. آمن على البيانات: إضافة أعمدة وتحديث دوال.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) users_profiles.unified_national_number (10 أرقام تبدأ 700)
-- ---------------------------------------------------------------------------
ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS unified_national_number text;

COMMENT ON COLUMN public.users_profiles.unified_national_number IS
  'الرقم الوطني الموحّد — 10 أرقام إنجليزية تبدأ بـ 700';

ALTER TABLE public.users_profiles
  DROP CONSTRAINT IF EXISTS chk_users_profiles_unified_national_number;

ALTER TABLE public.users_profiles
  ADD CONSTRAINT chk_users_profiles_unified_national_number CHECK (
    unified_national_number IS NULL
    OR (
      length(regexp_replace(unified_national_number, '\D', '', 'g')) = 10
      AND regexp_replace(unified_national_number, '\D', '', 'g') ~ '^700[0-9]{7}$'
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_profiles_unified_national_digits
  ON public.users_profiles (regexp_replace(coalesce(unified_national_number, ''), '\D', '', 'g'))
  WHERE unified_national_number IS NOT NULL
    AND length(regexp_replace(coalesce(unified_national_number, ''), '\D', '', 'g')) = 10;

-- ---------------------------------------------------------------------------
-- 2) تسجيل الدخول: ترتيب البحث حسب شكل المفتاح (700 أولاً إن وُجد)
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

-- مفتاح موحّد لـ OTP / الجهاز: يفضّل username المخزّن (10 أرقام) إن وُجد
CREATE OR REPLACE FUNCTION public.get_security_username_for_login(p_digits text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  v_uid uuid;
  un text;
  ud text;
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

  IF v_uid IS NULL THEN
    RETURN v;
  END IF;

  SELECT up.username::text INTO un
  FROM public.users_profiles up
  WHERE up.user_id = v_uid
  LIMIT 1;

  ud := regexp_replace(coalesce(un, ''), '\D', '', 'g');
  IF length(ud) = 10 THEN
    RETURN ud;
  END IF;

  RETURN v;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_security_username_for_login(text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_security_username_for_login(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) properties.listing_public_code — 10 أرقام إنجليزية فقط
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.properties_assign_listing_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
BEGIN
  IF NEW.listing_public_code IS NOT NULL AND length(trim(NEW.listing_public_code)) > 0 THEN
    IF NEW.listing_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'listing_public_code must be 10 digits';
    END IF;
    RETURN NEW;
  END IF;

  LOOP
    candidate := lpad((floor(random() * 10000000000::double precision))::bigint::text, 10, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.listing_public_code = candidate
    );
  END LOOP;

  NEW.listing_public_code := candidate;
  RETURN NEW;
END;
$$;

-- إعادة تعيين الأكواد القديمة (مثل AQ…) إلى 10 أرقام
DO $$
DECLARE
  r record;
  candidate text;
BEGIN
  FOR r IN SELECT id FROM public.properties
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.id = r.id
        AND (p.listing_public_code IS NULL
          OR length(trim(p.listing_public_code)) = 0
          OR p.listing_public_code !~ '^[0-9]{10}$')
    ) THEN
      LOOP
        candidate := lpad((floor(random() * 10000000000::double precision))::bigint::text, 10, '0');
        EXIT WHEN NOT EXISTS (
          SELECT 1 FROM public.properties p2
          WHERE p2.listing_public_code = candidate
        );
      END LOOP;
      UPDATE public.properties
      SET listing_public_code = candidate
      WHERE id = r.id;
    END IF;
  END LOOP;
END $$;

ALTER TABLE public.properties
  DROP CONSTRAINT IF EXISTS chk_properties_listing_public_code_numeric;

ALTER TABLE public.properties
  ADD CONSTRAINT chk_properties_listing_public_code_numeric CHECK (
    listing_public_code IS NULL
    OR listing_public_code ~ '^[0-9]{10}$'
  );

COMMENT ON COLUMN public.properties.listing_public_code IS
  'رقم تعريف الإعلان العام — 10 أرقام إنجليزية فقط، فريد.';

-- ---------------------------------------------------------------------------
-- 4) دلائلية العقار (JSON منظّم)
-- ---------------------------------------------------------------------------
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS listing_guidance jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.properties.listing_guidance IS
  'بيانات دلائلية/إرشادية للعقار: مثلاً {"items":[{"key":"...","label_ar":"...","value_ar":"..."}]}';

-- ---------------------------------------------------------------------------
-- 5) وثائق الامتثال للمستخدم (مصدر موحّد للحالات مستقبلاً)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_compliance_documents (
  id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  doc_type text NOT NULL,
  identifier text,
  issued_at date,
  expires_at date,
  status text NOT NULL DEFAULT 'missing',
  last_verified_at timestamptz,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT uq_user_compliance_documents_user_type UNIQUE (user_id, doc_type)
);

CREATE INDEX IF NOT EXISTS idx_user_compliance_documents_user
  ON public.user_compliance_documents (user_id);

ALTER TABLE public.user_compliance_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ucd_select_own ON public.user_compliance_documents;
CREATE POLICY ucd_select_own ON public.user_compliance_documents
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS ucd_modify_own ON public.user_compliance_documents;
CREATE POLICY ucd_modify_own ON public.user_compliance_documents
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

COMMENT ON TABLE public.user_compliance_documents IS
  'حالات الوثائق: valid, expiring_soon, expired, missing, pending_verification, rejected, suspended_due_to_expiry';

-- ---------------------------------------------------------------------------
-- 6) حذف عميق لعقار المالك (صور + أحداث مشاهدة؛ ثم العقار)
--    تعديل حسب مخططك إن وُجدت جداول إضافية تشير إلى property_id
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_delete_property_cascade(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  oid uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT owner_id INTO oid FROM public.properties WHERE id = p_property_id LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;
  IF oid IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF to_regclass('public.property_images') IS NOT NULL THEN
    DELETE FROM public.property_images WHERE property_id = p_property_id;
  END IF;

  IF to_regclass('public.property_listing_view_events') IS NOT NULL THEN
    DELETE FROM public.property_listing_view_events WHERE property_id = p_property_id;
  END IF;

  IF to_regclass('public.reservations') IS NOT NULL THEN
    DELETE FROM public.reservations WHERE property_id = p_property_id;
  END IF;

  DELETE FROM public.properties WHERE id = p_property_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.owner_delete_property_cascade(uuid) TO authenticated;
