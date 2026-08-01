-- خطة تجريبية مخصصة لكل نوع حساب تسويقي + إعادة تشكيل activate_marketing_trial_subscription
-- لكي يستخدم خطة بحدود التجربة:
--   • max_members           = 0 (لا فريق)
--   • max_ads_per_month     = 1 (إعلان عقاري واحد فقط)
--   • max_properties        = 1
--   • max_listing_requests  = NULL (طلبات عقارية غير محدودة)
--   • has_fal_license       = true (لتمرير سير العمل الكامل: عقد/تصريح)
--
-- + إخفاء خطط Trial من قائمة الباقات العادية عبر العلم is_trial_plan.

-- 1) عمود is_trial_plan على subscription_plans
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS is_trial_plan boolean NOT NULL DEFAULT false;

-- 2) إدراج خطط التجربة (مخفية من الباقات العادية)
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active, is_trial_plan
)
SELECT * FROM (VALUES
  (N'تجريبي ٣ أيام', 'Trial', 'marketer',    0::numeric, 0::numeric, 0, 1, 1, NULL::int, true, true, false, false, 0::numeric(5,2), 0, true, true),
  (N'تجريبي ٣ أيام', 'Trial', 'office',      0::numeric, 0::numeric, 0, 1, 1, NULL::int, true, true, false, false, 0::numeric(5,2), 0, true, true),
  (N'تجريبي ٣ أيام', 'Trial', 'institution', 0::numeric, 0::numeric, 0, 1, 1, NULL::int, true, true, false, false, 0::numeric(5,2), 0, true, true),
  (N'تجريبي ٣ أيام', 'Trial', 'company',     0::numeric, 0::numeric, 0, 1, 1, NULL::int, true, true, false, false, 0::numeric(5,2), 0, true, true)
) AS v(
  name_ar, name_en, user_type, price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, sort_order, is_active, is_trial_plan
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans p
  WHERE p.user_type = v.user_type AND p.is_trial_plan = true
);

-- 3) إعادة تعريف activate_marketing_trial_subscription لتختار خطة Trial المناسبة
CREATE OR REPLACE FUNCTION public.activate_marketing_trial_subscription()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_plan_id uuid;
  v_sub_id uuid;
  v_end date := current_date + 3;
  v_ends timestamptz := now() + interval '3 days';
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'trial_already_used');
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'marketer')
  INTO v_at
  FROM public.users_profiles
  WHERE user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  IF lower(trim(v_at)) NOT IN ('marketer','office','institution','company','agency') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'role_not_eligible_for_trial');
  END IF;

  -- إذا كان هناك اشتراك مدفوع فعّال — لا تجربة
  IF EXISTS (
    SELECT 1 FROM public.user_subscriptions
    WHERE user_id = v_uid
      AND coalesce(is_trial, false) = false
      AND status IN ('active','cancelled')
      AND coalesce(ends_at, end_date::timestamptz) > now()
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'paid_subscription_active');
  END IF;

  v_plan_type := CASE trim(lower(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'agency' THEN 'office'
    ELSE 'marketer'
  END;

  -- ابحث عن خطة Trial المخصصة لنوع الحساب
  SELECT id INTO v_plan_id
  FROM public.subscription_plans
  WHERE is_active = true
    AND is_trial_plan = true
    AND user_type = v_plan_type
  ORDER BY sort_order ASC
  LIMIT 1;

  -- إن لم توجد، استخدم الأساسية
  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true
      AND coalesce(is_trial_plan, false) = false
      AND user_type = v_plan_type AND sort_order = 1
    LIMIT 1;
  END IF;

  IF v_plan_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_plan_available');
  END IF;

  INSERT INTO public.user_subscriptions (
    user_id, organization_id, plan_id, status, period,
    start_date, end_date, auto_renew, starts_at, ends_at,
    is_trial
  )
  VALUES (
    v_uid, NULL, v_plan_id, 'active', 'monthly',
    current_date, v_end, false, now(), v_ends,
    true
  )
  RETURNING id INTO v_sub_id;

  INSERT INTO public.user_trial_subscriptions_used (user_id, subscription_id)
  VALUES (v_uid, v_sub_id);

  RETURN jsonb_build_object(
    'ok', true,
    'subscription_id', v_sub_id,
    'plan_id', v_plan_id,
    'plan_type', v_plan_type,
    'is_trial', true,
    'is_trial_plan', true,
    'ends_at', v_ends,
    'days', 3,
    'limits', jsonb_build_object(
      'max_members', 0,
      'max_ads_per_month', 1,
      'max_listing_requests', null,
      'has_fal_license', true
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_marketing_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_marketing_trial_subscription()
  TO authenticated, service_role;

-- 4) فهرس لتسريع الاستعلام عن «اشتراك تجريبي مستخدم»
CREATE INDEX IF NOT EXISTS idx_subscription_plans_trial
  ON public.subscription_plans (user_type, is_trial_plan, is_active);

-- 5) ضمان أن طلبات السوق لا تحسب على max_listing_requests عند التجربة
--    (السياسة الحالية لـ market_property_requests لا تستخدم max_listing_requests كحد صلب،
--     ولكننا نسجّل الملاحظة هنا للمراجعة المستقبلية).
COMMENT ON COLUMN public.subscription_plans.is_trial_plan IS
  'خطط Trial مخفية من قائمة الباقات العامة — تُسجَّل فقط عبر activate_marketing_trial_subscription.';
