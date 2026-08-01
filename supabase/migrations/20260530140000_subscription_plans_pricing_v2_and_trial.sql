-- (1) أسعار الباقات الجديدة + نسبة الخصم السنوية (~20% تقليدية)
-- (2) عمود is_trial على user_subscriptions + RPC لتفعيل تجربة 3 أيام لمرة واحدة
-- (3) عمود team_member_discount_percent (50%) للإشارة في الواجهة

-- ============================================================
-- 1) تحديث الأسعار: 99 / 149 / 499 (شهري) + خصم 50% لكل عضو فريق
--    السنوي = 12 × الشهري × 0.80 (خصم 20%)
-- ============================================================

-- إضافة عمود الخصم لكل عضو فريق (اختياري — للعرض)
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS team_member_discount_percent numeric(5,2) DEFAULT 0;

-- تعطيل الباقات القديمة
UPDATE public.subscription_plans SET is_active = false WHERE is_active = true;

-- إعادة إدراج الباقات بالأسعار الجديدة
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent,
  sort_order, is_active
)
VALUES
  -- معلن فردي (يبقى كما هو في الأسعار القديمة — لا تغيير منك له)
  (N'أساسي', 'Basic', 'individual', 49::numeric, (49*12*0.80)::numeric, 1, NULL, 40, 15, true, false, false, false, 0, 1, true),

  -- مسوّق عقاري فردي → 99 / 149 / 499
  (N'الأساسي', 'Basic', 'marketer',        99::numeric,  (99*12*0.80)::numeric,  0, NULL,  80,  35, true, false, false, false, 50, 1, true),
  (N'الاحترافي', 'Professional', 'marketer', 149::numeric, (149*12*0.80)::numeric, 0, NULL, 450, 180, true, true,  false, true,  50, 2, true),
  (N'المميزة', 'Premium', 'marketer',       499::numeric, (499*12*0.80)::numeric, 0, NULL, NULL, NULL, true, true,  true,  true,  50, 3, true),

  -- مكتب عقاري (3 مقاعد)
  (N'الأساسي', 'Basic', 'office',          99::numeric,  (99*12*0.80)::numeric,  3, NULL,  80,  35, true, false, false, false, 50, 1, true),
  (N'الاحترافي', 'Professional', 'office',  149::numeric, (149*12*0.80)::numeric, 3, NULL, 600, 250, true, true,  false, true,  50, 2, true),
  (N'المميزة', 'Premium', 'office',         499::numeric, (499*12*0.80)::numeric, 3, NULL, NULL, NULL, true, true,  true,  true,  50, 3, true),

  -- مؤسسة (6 مقاعد)
  (N'الأساسي', 'Basic', 'institution',     99::numeric,  (99*12*0.80)::numeric,  6, NULL,  80,  35, true, false, false, false, 50, 1, true),
  (N'الاحترافي', 'Professional', 'institution', 149::numeric, (149*12*0.80)::numeric, 6, NULL, 900, 400, true, true,  false, true,  50, 2, true),
  (N'المميزة', 'Premium', 'institution',    499::numeric, (499*12*0.80)::numeric, 6, NULL, NULL, NULL, true, true,  true,  true,  50, 3, true),

  -- شركة عقارية (9 مقاعد)
  (N'الأساسي', 'Basic', 'company',         99::numeric,  (99*12*0.80)::numeric,  9, NULL,  80,  35, true, false, false, false, 50, 1, true),
  (N'الاحترافي', 'Professional', 'company', 149::numeric, (149*12*0.80)::numeric, 9, NULL, 1200, 500, true, true,  false, true,  50, 2, true),
  (N'المميزة', 'Premium', 'company',        499::numeric, (499*12*0.80)::numeric, 9, NULL, NULL, NULL, true, true,  true,  true,  50, 3, true)
;

-- ============================================================
-- 2) نظام التجربة 3 أيام لمرة واحدة
-- ============================================================

-- خاصية على الجدول
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS is_trial boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_trial
  ON public.user_subscriptions (user_id, is_trial);

-- سجل التجارب المستخدمة (إدراج لمرة واحدة لكل مستخدم)
CREATE TABLE IF NOT EXISTS public.user_trial_subscriptions_used (
  user_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  used_at timestamptz NOT NULL DEFAULT now(),
  subscription_id uuid REFERENCES public.user_subscriptions (id) ON DELETE SET NULL
);

ALTER TABLE public.user_trial_subscriptions_used ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_trial_used_select_own ON public.user_trial_subscriptions_used;
CREATE POLICY user_trial_used_select_own ON public.user_trial_subscriptions_used
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- RPC: هل استخدم المستخدم التجربة من قبل؟
CREATE OR REPLACE FUNCTION public.has_user_used_trial()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used
    WHERE user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.has_user_used_trial() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_user_used_trial() TO authenticated, service_role;

-- RPC: تفعيل التجربة لمدة 3 أيام (مرة واحدة)
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

  -- التجربة متاحة لكل أدوار التسويق (مسوّق + مكتب + مؤسسة + شركة + وكالة)
  IF lower(trim(v_at)) NOT IN ('marketer','office','institution','company','agency') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'role_not_eligible_for_trial');
  END IF;

  -- إذا كان هناك اشتراك مدفوع فعّال — لا تجربة
  IF EXISTS (
    SELECT 1 FROM public.user_subscriptions
    WHERE user_id = v_uid
      AND is_trial = false
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

  -- ابحث عن الباقة الأساسية لنوع الحساب (sort_order = 1)
  SELECT id INTO v_plan_id
  FROM public.subscription_plans
  WHERE is_active = true AND user_type = v_plan_type AND sort_order = 1
  LIMIT 1;

  IF v_plan_id IS NULL THEN
    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true AND user_type = v_plan_type
    ORDER BY sort_order ASC
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
    'ends_at', v_ends,
    'days', 3
  );
END;
$$;

REVOKE ALL ON FUNCTION public.activate_marketing_trial_subscription() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.activate_marketing_trial_subscription()
  TO authenticated, service_role;
