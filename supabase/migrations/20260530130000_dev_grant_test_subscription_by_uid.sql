-- دوال اختبار مرنة: منح اشتراك تجريبي لأي مستخدم بواسطة معرّفه أو هاتفه أو اسمه،
-- وعرض تشخيصي للحسابات المشابهة. مفيدة عندما 10000000 لا يطابق أي username.

-- ============================================================
-- (1) تشخيص: ابحث عن ملفات المستخدمين بأسماء/هواتف مشابهة
--     SELECT * FROM public.dev_find_profile_like_digits('10000000');
-- ============================================================
CREATE OR REPLACE FUNCTION public.dev_find_profile_like_digits(p_digits text)
RETURNS TABLE (
  user_id uuid,
  username text,
  phone text,
  account_type text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH q AS (
    SELECT regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g') AS digits
  )
  SELECT
    up.user_id,
    up.username::text,
    up.phone::text,
    up.account_type::text,
    up.created_at
  FROM public.users_profiles up, q
  WHERE up.user_id IS NOT NULL
    AND q.digits IS NOT NULL
    AND q.digits <> ''
    AND (
      regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') LIKE '%' || q.digits || '%'
      OR regexp_replace(coalesce(up.phone::text, ''),    '\D', '', 'g') LIKE '%' || q.digits || '%'
    )
  ORDER BY up.created_at DESC NULLS LAST
  LIMIT 25;
$$;

REVOKE ALL ON FUNCTION public.dev_find_profile_like_digits(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_find_profile_like_digits(text) TO service_role;


-- ============================================================
-- (2) منح اشتراك تجريبي لمستخدم محدّد بـ user_id
--     SELECT public.dev_grant_test_subscription_for_uid('96bad4d0-8463-46b5-9525-575f477b7c88');
-- ============================================================
CREATE OR REPLACE FUNCTION public.dev_grant_test_subscription_for_uid(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_at text;
  v_plan_type text;
  v_plan_id uuid;
  v_org_id uuid;
  v_end date;
  v_ends timestamptz;
BEGIN
  IF p_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_uid');
  END IF;

  SELECT coalesce(nullif(trim(up.account_type), ''), 'marketer')
  INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = p_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  v_plan_type := CASE trim(lower(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'company' THEN 'office'
    WHEN 'institution' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual_seller' THEN 'individual'
    ELSE 'marketer'
  END;

  v_end := current_date + 365;
  v_ends := now() + interval '365 days';

  SELECT id INTO v_plan_id
  FROM public.subscription_plans
  WHERE is_active = true AND user_type = v_plan_type
  ORDER BY sort_order ASC
  LIMIT 1;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true
    ORDER BY sort_order ASC
    LIMIT 1;
  END IF;

  IF v_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_plan_available');
  END IF;

  PERFORM public.dev_upsert_test_subscription_row(p_uid, NULL, v_plan_id, v_end, v_ends);

  v_org_id := NULL;
  SELECT o.id INTO v_org_id
  FROM public.org_units o
  WHERE o.owner_user_id = p_uid
  ORDER BY o.created_at DESC NULLS LAST
  LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT m.org_id INTO v_org_id
    FROM public.org_memberships m
    WHERE m.user_id = p_uid AND m.status = 'active'
    ORDER BY m.created_at DESC NULLS LAST
    LIMIT 1;
  END IF;

  IF v_org_id IS NOT NULL THEN
    PERFORM public.dev_upsert_test_subscription_row(p_uid, v_org_id, v_plan_id, v_end, v_ends);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'user_id', p_uid,
    'account_type', v_at,
    'plan_id', v_plan_id,
    'plan_type', v_plan_type,
    'end_date', v_end,
    'organization_id', v_org_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dev_grant_test_subscription_for_uid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_grant_test_subscription_for_uid(uuid) TO service_role;


-- ============================================================
-- (3) منح اشتراك تجريبي للمستخدم الحالي (المسجّل دخوله الآن)
--     يستدعى من Flutter:
--       supabase.rpc('dev_grant_test_subscription_for_me')
--     مفيد للمطوّرين/الاختبار في الإنتاج عبر زر «تفعيل تجريبي».
-- ============================================================
CREATE OR REPLACE FUNCTION public.dev_grant_test_subscription_for_me()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  RETURN public.dev_grant_test_subscription_for_uid(v_uid);
END;
$$;

REVOKE ALL ON FUNCTION public.dev_grant_test_subscription_for_me() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_grant_test_subscription_for_me() TO authenticated, service_role;


-- ============================================================
-- (4) منح اشتراك تجريبي لأي مستخدم يطابق هاتف/رقم/اسم (مرن)
--     SELECT public.dev_grant_test_subscription_by_match('10000000');
-- ============================================================
CREATE OR REPLACE FUNCTION public.dev_grant_test_subscription_by_match(p_digits text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_digits text;
  v_uid uuid;
  v_results jsonb := '[]'::jsonb;
  v_count int := 0;
  v_one jsonb;
BEGIN
  v_digits := regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g');
  IF v_digits = '' OR length(v_digits) < 5 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_digits');
  END IF;

  FOR v_uid IN
    SELECT DISTINCT up.user_id
    FROM public.users_profiles up
    WHERE up.user_id IS NOT NULL
      AND (
        regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') LIKE '%' || v_digits || '%'
        OR regexp_replace(coalesce(up.phone::text, ''), '\D', '', 'g') LIKE '%' || v_digits || '%'
      )
    LIMIT 10
  LOOP
    v_one := public.dev_grant_test_subscription_for_uid(v_uid);
    v_results := v_results || jsonb_build_array(v_one);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'digits', v_digits,
    'matched', v_count,
    'results', v_results
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dev_grant_test_subscription_by_match(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_grant_test_subscription_by_match(text) TO service_role;
