-- نسخة v3 من حدود الباقات + سعر العضو الإضافي بخصم 50%.
--
-- 1) الأساسية: 3 أعضاء كحد أقصى · 60 إعلان/شهر · طلبات غير محدودة.
-- 2) الاحترافية: 450 إعلان · طلبات غير محدودة. أعضاء حسب نوع الحساب.
-- 3) المميزة: إعلانات غير محدودة · طلبات غير محدودة. أعضاء حسب نوع الحساب.
-- 4) الأعضاء (طاقم العمل): مكتب=6 · مؤسسة=9 · شركة=12 (في الباقات الاحترافية والمميزة).
-- 5) التجريبية (Trial): إعلانات وطلبات غير محدودة.
-- 6) سعر مقعد إضافي = price_monthly × 50% (خصم 50% تلقائي).

-- ============================================================
-- (أ) عمود seat_unit_price_sar (محسوب تلقائياً = 50% من السعر الشهري)
-- ============================================================
ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS seat_unit_price_sar numeric(10,2);

-- ============================================================
-- (ب) تحديث حدود الباقات لكل نوع حساب
-- ============================================================

-- الأساسية لكل الأدوار: 3 أعضاء · 60 إعلان · طلبات غير محدودة.
UPDATE public.subscription_plans
SET
  max_members          = 3,
  max_ads_per_month    = 60,
  max_listing_requests = NULL,
  max_properties       = NULL,
  team_member_discount_percent = 50,
  seat_unit_price_sar  = round(price_monthly * 0.5, 2)
WHERE is_active = true
  AND coalesce(is_trial_plan, false) = false
  AND sort_order = 1
  AND user_type IN ('marketer','office','institution','company');

-- الاحترافية: 450 إعلان · طلبات غير محدودة. أعضاء حسب نوع الحساب.
UPDATE public.subscription_plans SET
  max_members = 6, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'office';

UPDATE public.subscription_plans SET
  max_members = 9, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'institution';

UPDATE public.subscription_plans SET
  max_members = 12, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'company';

UPDATE public.subscription_plans SET
  max_members = 0, max_ads_per_month = 450, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 2 AND user_type = 'marketer';

-- المميزة: إعلانات + طلبات غير محدودة. أعضاء حسب نوع الحساب.
UPDATE public.subscription_plans SET
  max_members = 6, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'office';

UPDATE public.subscription_plans SET
  max_members = 9, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'institution';

UPDATE public.subscription_plans SET
  max_members = 12, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'company';

UPDATE public.subscription_plans SET
  max_members = 0, max_ads_per_month = NULL, max_listing_requests = NULL,
  max_properties = NULL, team_member_discount_percent = 50,
  seat_unit_price_sar = round(price_monthly * 0.5, 2)WHERE is_active = true AND coalesce(is_trial_plan, false) = false
  AND sort_order = 3 AND user_type = 'marketer';

-- الباقات التجريبية: إعلانات + طلبات غير محدودة.
UPDATE public.subscription_plans SET
  max_ads_per_month = NULL,
  max_properties    = NULL,
  max_listing_requests = NULL
WHERE coalesce(is_trial_plan, false) = true;

-- ============================================================
-- (ج) RPC جديد: org_seat_unit_price — يُرجع سعر العضو الإضافي + باقي الحد
-- ============================================================
CREATE OR REPLACE FUNCTION public.org_seat_unit_price()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_plan record;
  v_member_count int := 0;
  v_remaining int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT o.id INTO v_org
  FROM public.org_units o
  WHERE o.owner_user_id = v_uid LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_org');
  END IF;

  SELECT p.*
  INTO v_plan
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_uid
    AND s.status IN ('active','cancelled')
    AND coalesce(s.ends_at, s.end_date::timestamptz) > now()
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_plan.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_active_subscription');
  END IF;

  SELECT count(*) INTO v_member_count
  FROM public.org_memberships m
  WHERE m.org_id = v_org AND m.status = 'active';

  v_remaining := greatest(0, coalesce(v_plan.max_members, 0) - v_member_count);

  RETURN jsonb_build_object(
    'ok', true,
    'plan_id', v_plan.id,
    'plan_name_ar', v_plan.name_ar,
    'plan_name_en', v_plan.name_en,
    'plan_price_monthly', v_plan.price_monthly,
    'seat_unit_price_sar', coalesce(v_plan.seat_unit_price_sar, round(v_plan.price_monthly * 0.5, 2)),
    'team_member_discount_percent', coalesce(v_plan.team_member_discount_percent, 50),
    'plan_max_members', v_plan.max_members,
    'current_members', v_member_count,
    'remaining_slots_in_plan', v_remaining,
    'is_trial', coalesce(v_plan.is_trial_plan, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.org_seat_unit_price() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.org_seat_unit_price() TO authenticated, service_role;

-- ============================================================
-- (د) org_purchase_extra_seats_priced — يحسب السعر + يسجّل billing transaction
-- ============================================================
CREATE OR REPLACE FUNCTION public.org_purchase_extra_seats_priced(
  p_extra int,
  p_billing_transaction_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_seat_price numeric(10,2);
  v_total numeric(10,2);
  v_n int := greatest(0, least(coalesce(p_extra, 0), 50));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  IF v_n <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_count');
  END IF;

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_org');
  END IF;

  SELECT coalesce(p.seat_unit_price_sar, round(p.price_monthly * 0.5, 2))
  INTO v_seat_price
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_uid
    AND s.status IN ('active','cancelled')
    AND coalesce(s.ends_at, s.end_date::timestamptz) > now()
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_seat_price IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_active_subscription');
  END IF;

  v_total := v_seat_price * v_n;

  UPDATE public.org_units SET
    purchased_extra_seats = coalesce(purchased_extra_seats, 0) + v_n,
    extra_seats_expires_at = now() + interval '365 days'
  WHERE id = v_org;

  INSERT INTO public.extra_seats_requests (
    organization_id, seats_requested, amount, status, transaction_id
  )
  VALUES (
    v_org, v_n, v_total,
    CASE WHEN p_billing_transaction_id IS NOT NULL THEN 'paid' ELSE 'pending' END,
    p_billing_transaction_id
  );

  RETURN jsonb_build_object(
    'ok', true,
    'seats_added', v_n,
    'seat_unit_price_sar', v_seat_price,
    'discount_percent', 50,
    'total_charged_sar', v_total
  );
END;
$$;

REVOKE ALL ON FUNCTION public.org_purchase_extra_seats_priced(int, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.org_purchase_extra_seats_priced(int, uuid)
  TO authenticated, service_role;

COMMENT ON COLUMN public.subscription_plans.seat_unit_price_sar IS
  'سعر العضو الإضافي = price_monthly × 50% (خصم تلقائي). يُحسب لحظياً في org_seat_unit_price.';
