-- =============================================================================
-- تجاوب 42P17 عند التسجيل: فحص الهوية/الجوال/الرقم الموحّد بدون SELECT مباشر
-- على users_profiles تحت سياسات قد تعيد تقييم نفسها (تكرار لا نهائي).
--
-- نفّذ في Supabase → SQL Editor (مرة واحدة).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.signup_username_taken(p_username text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE nullif(trim(both from up.username::text), '') IS NOT NULL
      AND trim(both from up.username::text) = trim(both from p_username::text)
  );
$$;

CREATE OR REPLACE FUNCTION public.signup_phone_taken(p_phone text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.phone IS NOT NULL
      AND trim(both from up.phone::text) = trim(both from p_phone::text)
  );
$$;

CREATE OR REPLACE FUNCTION public.signup_unified_national_taken(p_digits text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users_profiles up
    WHERE up.unified_national_number IS NOT NULL
      AND regexp_replace(coalesce(up.unified_national_number::text, ''), '\D', '', 'g')
          = nullif(regexp_replace(coalesce(p_digits::text, ''), '\D', '', 'g'), '')
  );
$$;

-- تحديث الرقم الموحّد بعد upsert_my_profile (بدلاً من UPDATE مباشر من العميل).
CREATE OR REPLACE FUNCTION public.signup_set_unified_national(p_user_id uuid, p_digits text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_clean text;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_clean := nullif(regexp_replace(coalesce(p_digits, ''), '\D', '', 'g'), '');

  UPDATE public.users_profiles
  SET unified_national_number = v_clean
  WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.signup_username_taken(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.signup_phone_taken(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.signup_unified_national_taken(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.signup_set_unified_national(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.signup_username_taken(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signup_phone_taken(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signup_unified_national_taken(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signup_set_unified_national(uuid, text) TO authenticated;

COMMIT;

-- =============================================================================
-- ملاحظة: إن استمر 42P17 داخل upsert_my_profile نفسه، راجع سياسات RLS على
-- users_profiles: أي USING / WITH CHECK يحتوي EXISTS (SELECT … FROM users_profiles …)
-- على نفس الجدول يسبب تكراراً — استبدله بدالة SECURITY DEFINER منفصلة أو
-- auth.uid() = user_id فقط حيث يناسب.
-- لا تستخدم app_rls_my_profile_username() داخل سياسة ON users_profiles.
-- =============================================================================
