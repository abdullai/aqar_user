-- =============================================================================
-- كتالوج الباقات حسب نوع الحساب (صلاحيات الدور) — لا تُعرض باقة دور آخر.
-- نفّذ في SQL Editor بعد نجاح ترحيلات الاشتراك السابقة.
-- =============================================================================

BEGIN;

-- أسماء كانونية للباقات الرئيسية (إن وُسمت خطأً باسم دور آخر مثل «مصور عقاري»).
UPDATE public.subscription_plans SET
  name_ar = N'الأساسي',
  name_en = 'Basic'
WHERE user_type = 'marketer'
  AND sort_order = 1
  AND coalesce(is_trial_plan, false) = false
  AND is_active = true;

UPDATE public.subscription_plans SET
  name_ar = N'الاحترافية',
  name_en = 'Professional'
WHERE user_type IN ('office', 'institution', 'agency')
  AND sort_order = 2
  AND coalesce(is_trial_plan, false) = false
  AND is_active = true;

UPDATE public.subscription_plans SET
  name_ar = N'باقة التميز',
  name_en = 'Excellence Plan'
WHERE user_type = 'company'
  AND sort_order = 3
  AND coalesce(is_trial_plan, false) = false
  AND is_active = true;

UPDATE public.subscription_plans SET
  name_ar = N'الشامل',
  name_en = 'Comprehensive'
WHERE user_type IN ('marketer', 'office', 'institution', 'agency', 'company')
  AND sort_order = 4
  AND coalesce(is_trial_plan, false) = false
  AND is_active = true;

UPDATE public.subscription_plans SET
  name_ar = N'مصور عقاري – أساسي',
  name_en = 'Photographer – Basic'
WHERE user_type = 'photographer'
  AND sort_order = 1
  AND coalesce(is_trial_plan, false) = false
  AND is_active = true;

DROP FUNCTION IF EXISTS public.list_subscription_catalog_plans();
DROP FUNCTION IF EXISTS public.list_subscription_catalog_plans(text);

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans(
  p_account_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_allowed int[];
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required', 'plans', '[]'::jsonb);
  END IF;

  v_at := nullif(lower(trim(coalesce(p_account_type, ''))), '');
  IF v_at IS NULL THEN
    SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
    INTO v_at
    FROM public.users_profiles up
    WHERE up.user_id = v_uid;
  END IF;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_at := lower(trim(v_at));

  v_plan_type := CASE v_at
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'photographer' THEN 'photographer'
    WHEN 'individual_seller' THEN 'individual'
    WHEN 'owner_individual' THEN 'individual'
    WHEN 'individual' THEN 'individual'
    WHEN 'public_user' THEN 'individual'
    WHEN 'user' THEN 'individual'
    ELSE 'individual'
  END;

  v_allowed := CASE v_plan_type
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[1]
    ELSE ARRAY[]::int[]
  END;

  IF coalesce(array_length(v_allowed, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'account_type', v_at,
      'plan_user_type', v_plan_type,
      'plans', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
  INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND lower(trim(sp.user_type)) = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans(text)
  TO authenticated, service_role;

COMMIT;
