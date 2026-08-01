-- =============================================================================
-- v9.1: إلغاء باقة الشريك (49 ر.س) للمالك/المستخدم العادي — خدمات مجانية
--       + إخفاء باقات الاشتراك من كتالوج individual (الطلب الفوري 30 ر.س منفصل)
-- =============================================================================

BEGIN;

UPDATE public.subscription_plans
SET is_active = false,
    name_ar = N'باقة الشريك (متوقفة)',
    name_en = 'Partner Plan (discontinued)'
WHERE user_type = 'individual'
  AND sort_order = 1
  AND coalesce(is_trial_plan, false) = false;

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans()
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

  SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
  INTO v_at
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
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
    AND sp.user_type = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans()
  TO authenticated, service_role;

COMMIT;
