-- =============================================================================
-- 2026-06-02 — ربط دورة حياة Top-up + حصة الطلبات العقارية + تفعيل تجريبية
-- =============================================================================
-- v7 يُغلق ثلاث ثغرات في v6:
--   (A) الفهرس الفريد user_subscriptions_one_active_paid_per_user كان يَمنع
--       شراء أي top-up (11/12/13/21/22/23) إلى جانب الباقة الرئيسية.
--   (B) لا توجد دالة موحَّدة لحساب حصة «الطلبات العقارية» مع توب-أب 21/22/23.
--   (C) الباقات التجريبية للأدوار التسويقية كانت غير ظاهرة في الجدول النشط
--       (is_active=false) رغم وجودها في DB.
-- =============================================================================

BEGIN;

-- =============================================================================
-- (A) عمود is_topup + Trigger لضبطه + إعادة بناء الفهرس الفريد
-- =============================================================================
ALTER TABLE public.user_subscriptions
  ADD COLUMN IF NOT EXISTS is_topup boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public._set_user_subscription_is_topup()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE v_sort int;
BEGIN
  SELECT sort_order INTO v_sort
    FROM public.subscription_plans
   WHERE id = NEW.plan_id;
  -- 11/12/13: عروض السوق (فردي)
  -- 21/22/23: طلبات إضافية (تسويقي)
  NEW.is_topup := coalesce(v_sort IN (11, 12, 13, 21, 22, 23), false);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_user_subs_set_is_topup
  ON public.user_subscriptions;

CREATE TRIGGER tr_user_subs_set_is_topup
  BEFORE INSERT OR UPDATE OF plan_id
  ON public.user_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION public._set_user_subscription_is_topup();

-- تحديث الصفوف القائمة لتعكس القيمة الصحيحة
UPDATE public.user_subscriptions s
   SET is_topup = (p.sort_order IN (11, 12, 13, 21, 22, 23))
  FROM public.subscription_plans p
 WHERE s.plan_id = p.id
   AND s.is_topup IS DISTINCT FROM (p.sort_order IN (11, 12, 13, 21, 22, 23));

-- إعادة بناء الفهرس الفريد ليَستثني top-ups
DROP INDEX IF EXISTS public.user_subscriptions_one_active_paid_per_user;
DROP INDEX IF EXISTS public.user_subscriptions_one_main_paid_per_user;

CREATE UNIQUE INDEX user_subscriptions_one_main_paid_per_user
  ON public.user_subscriptions (user_id)
  WHERE status = 'active'
    AND coalesce(is_trial, false) = false
    AND is_topup = false;

-- =============================================================================
-- (B) تحديث subscription_can_subscribe — السماح بـ Top-ups في وجود اشتراك رئيسي
-- =============================================================================
CREATE OR REPLACE FUNCTION public.subscription_can_subscribe(
  p_target_plan_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_owner_active boolean := false;
  v_self_active record;
  v_is_team_member boolean := false;
  v_member_role text;
  v_target_sort int;
  v_target_is_topup boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- (1) حدّد ما إذا كانت الباقة المختارة Top-up
  IF p_target_plan_id IS NOT NULL THEN
    SELECT sort_order INTO v_target_sort
      FROM public.subscription_plans
     WHERE id = p_target_plan_id;
    v_target_is_topup := coalesce(v_target_sort IN (11,12,13,21,22,23), false);
  END IF;

  -- (2) عضو فريق
  SELECT m.member_role, o.owner_user_id
    INTO v_member_role, v_owner
  FROM public.org_memberships m
  JOIN public.org_units o ON o.id = m.org_id
  WHERE m.user_id = v_uid
    AND m.status = 'active'
  ORDER BY m.created_at DESC
  LIMIT 1;

  IF FOUND AND v_owner IS NOT NULL AND v_owner <> v_uid
     AND coalesce(v_member_role,'') <> 'owner' THEN
    v_is_team_member := true;
  END IF;

  IF v_is_team_member THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner
        AND coalesce(s.is_trial, false) = false
        AND coalesce(s.is_topup, false) = false
        AND s.status IN ('active','cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    ) INTO v_owner_active;

    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', false,
      'reason', 'team_member_uses_owner_subscription',
      'owner_user_id', v_owner,
      'owner_has_active_subscription', v_owner_active
    );
  END IF;

  -- (3) فحص اشتراك مدفوع رئيسي فعّال
  SELECT s.id, s.plan_id, s.period, s.starts_at, s.ends_at, s.status
    INTO v_self_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = false
    AND coalesce(s.is_topup, false) = false
    AND s.status = 'active'
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

  -- (4) إن كانت الباقة المختارة Top-up: السماح إن كان للمستخدم رئيسية فعّالة
  IF v_target_is_topup THEN
    IF v_self_active.id IS NULL THEN
      RETURN jsonb_build_object(
        'ok', true,
        'can_subscribe', false,
        'reason', 'topup_requires_main_subscription'
      );
    END IF;
    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', true,
      'topup_purchase', true,
      'main_subscription_id', v_self_active.id
    );
  END IF;

  -- (5) باقة رئيسية + لديه اشتراك رئيسي → الترقية فقط
  IF v_self_active.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'can_subscribe', false,
      'reason', 'already_active_subscription',
      'subscription_id', v_self_active.id,
      'plan_id', v_self_active.plan_id,
      'period', v_self_active.period,
      'starts_at', v_self_active.starts_at,
      'ends_at', v_self_active.ends_at,
      'upgrade_only', true
    );
  END IF;

  RETURN jsonb_build_object('ok', true, 'can_subscribe', true);
END;
$$;

REVOKE ALL ON FUNCTION public.subscription_can_subscribe(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_can_subscribe(uuid)
  TO authenticated, service_role;

-- نُحافظ على نسخة بدون مَعامل للتوافق العكسي
DROP FUNCTION IF EXISTS public.subscription_can_subscribe();
CREATE OR REPLACE FUNCTION public.subscription_can_subscribe()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.subscription_can_subscribe(NULL);
$$;

REVOKE ALL ON FUNCTION public.subscription_can_subscribe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.subscription_can_subscribe()
  TO authenticated, service_role;

-- =============================================================================
-- (C) RPC: _listing_requests_topup_plans_for_uid — توب-أب الطلبات لمستخدم
-- =============================================================================
CREATE OR REPLACE FUNCTION public._listing_requests_topup_plans_for_uid(p_uid uuid)
RETURNS TABLE (
  subscription_id uuid,
  plan_id uuid,
  plan_program text,
  max_count integer,
  starts_at timestamptz,
  ends_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    s.id,
    p.id,
    coalesce(p.plan_program, 'monthly'),
    coalesce(p.max_listing_requests, 0),
    coalesce(s.starts_at, s.start_date::timestamptz),
    coalesce(s.ends_at, s.end_date::timestamptz)
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = p_uid
    AND s.status IN ('active','cancelled')
    AND p.user_type IN ('marketer','office','institution','company','agency')
    AND p.sort_order IN (21, 22, 23)
    AND coalesce(p.max_listing_requests, 0) > 0
    AND (
      coalesce(p.plan_program, 'monthly') = 'lifetime_one_time'
      OR coalesce(s.ends_at, s.end_date::timestamptz) > now()
    )
  ORDER BY s.created_at DESC;
$$;

REVOKE ALL ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._listing_requests_topup_plans_for_uid(uuid)
  TO authenticated, service_role;

-- =============================================================================
-- (D) RPC: listing_requests_unified_allowance — الحصة الموحَّدة (main + topups)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.listing_requests_unified_allowance(
  p_organization_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bill_uid uuid;
  v_at text;
  v_main record;
  v_main_max int := 0;
  v_main_unlimited boolean := false;
  v_topup record;
  v_topup_max int := 0;
  v_topup_records jsonb := '[]'::jsonb;
  v_total_max int := 0;
  v_used int := 0;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true, 'authenticated', false,
      'audience', 'guest', 'has_subscription', false,
      'unlimited', false, 'total_max', 0, 'total_used', 0,
      'total_remaining', 0, 'needs_paywall', true,
      'note', 'auth_required'
    );
  END IF;

  SELECT coalesce(nullif(trim(account_type::text), ''), 'user')
    INTO v_at FROM public.users_profiles WHERE user_id = v_uid;

  v_bill_uid := v_uid;
  IF lower(coalesce(v_at,'')) IN ('marketer','office','institution','company','agency') THEN
    IF p_organization_id IS NOT NULL THEN
      SELECT o.owner_user_id INTO v_bill_uid
        FROM public.org_units o WHERE o.id = p_organization_id LIMIT 1;
      IF v_bill_uid IS NULL THEN v_bill_uid := v_uid; END IF;
    ELSE
      SELECT o.owner_user_id INTO v_bill_uid
        FROM public.org_memberships m
        JOIN public.org_units o ON o.id = m.org_id
       WHERE m.user_id = v_uid AND m.status = 'active'
       ORDER BY m.created_at DESC LIMIT 1;
      IF v_bill_uid IS NULL THEN v_bill_uid := v_uid; END IF;
    END IF;
  END IF;

  -- (أ) الباقة الرئيسية — حصة max_listing_requests
  SELECT s.id AS subscription_id, p.id AS plan_id, p.max_listing_requests,
         s.starts_at, s.ends_at, coalesce(s.is_trial, false) AS is_trial
    INTO v_main
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = v_bill_uid
    AND s.status IN ('active','cancelled')
    AND coalesce(s.is_topup, false) = false
    AND coalesce(s.ends_at, s.end_date::timestamptz) > now()
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF v_main.subscription_id IS NOT NULL THEN
    IF v_main.is_trial OR v_main.max_listing_requests IS NULL THEN
      v_main_unlimited := true;
      v_main_max := 999999;
    ELSE
      v_main_max := coalesce(v_main.max_listing_requests, 0);
    END IF;
  END IF;

  -- (ب) Top-ups
  FOR v_topup IN
    SELECT * FROM public._listing_requests_topup_plans_for_uid(v_uid)
  LOOP
    v_topup_max := v_topup_max + coalesce(v_topup.max_count, 0);
    v_topup_records := v_topup_records || jsonb_build_object(
      'subscription_id', v_topup.subscription_id,
      'plan_id', v_topup.plan_id,
      'plan_program', v_topup.plan_program,
      'max', v_topup.max_count,
      'starts_at', v_topup.starts_at,
      'ends_at', v_topup.ends_at
    );
  END LOOP;

  IF v_main_unlimited THEN
    v_total_max := 999999;
  ELSE
    v_total_max := v_main_max + v_topup_max;
  END IF;

  -- (ج) العداد: عدد الطلبات العقارية التي أنشأها bill_uid (المالك).
  -- نَحسب فقط طلبات السوق المنشورة/المسودّات (نَستثني المغلقة).
  SELECT count(*) INTO v_used
    FROM public.market_property_requests
   WHERE requester_id = v_bill_uid
     AND status IN ('published', 'draft');

  RETURN jsonb_build_object(
    'ok', true,
    'authenticated', true,
    'audience', CASE WHEN lower(coalesce(v_at,'')) IN
                      ('marketer','office','institution','company','agency')
                THEN 'marketing' ELSE 'individual' END,
    'has_subscription', (v_main.subscription_id IS NOT NULL OR v_topup_max > 0),
    'has_main_plan', v_main.subscription_id IS NOT NULL,
    'main', CASE
      WHEN v_main.subscription_id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'subscription_id', v_main.subscription_id,
        'plan_id', v_main.plan_id,
        'is_trial', v_main.is_trial,
        'unlimited', v_main_unlimited,
        'max', CASE WHEN v_main_unlimited THEN NULL ELSE v_main_max END,
        'starts_at', v_main.starts_at,
        'ends_at', v_main.ends_at
      )
    END,
    'topups', v_topup_records,
    'total_used', v_used,
    'total_max', CASE WHEN v_main_unlimited THEN NULL ELSE v_total_max END,
    'total_remaining', CASE
      WHEN v_main_unlimited THEN NULL
      ELSE greatest(0, v_total_max - v_used)
    END,
    'unlimited', v_main_unlimited,
    'needs_paywall', (NOT v_main_unlimited AND v_used >= v_total_max),
    'billing_user_id', v_bill_uid
  );
END;
$$;

REVOKE ALL ON FUNCTION public.listing_requests_unified_allowance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listing_requests_unified_allowance(uuid)
  TO authenticated, service_role, anon;

-- =============================================================================
-- (E) تفعيل التجريبية لجميع الأدوار التسويقية + الفرد
-- =============================================================================
UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = true
   AND user_type IN ('marketer','office','institution','company','individual');

-- إنشاء أي تجريبية ناقصة لدور تسويقي
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  (N'تجريبي ٣ أيام', 'Trial 3 days', 'marketer',
     0::numeric, 0::numeric,
     0::int, 1::int, 1::int, NULL::int, NULL::int,
     true, true, false, false,
     0::numeric, 0::numeric, 0::numeric, 0::numeric,
     0, true, true, 'monthly'),
  (N'تجريبي ٣ أيام', 'Trial 3 days', 'office',
     0::numeric, 0::numeric,
     0::int, 1::int, 1::int, NULL::int, NULL::int,
     true, true, false, false,
     0::numeric, 0::numeric, 0::numeric, 0::numeric,
     0, true, true, 'monthly'),
  (N'تجريبي ٣ أيام', 'Trial 3 days', 'institution',
     0::numeric, 0::numeric,
     0::int, 1::int, 1::int, NULL::int, NULL::int,
     true, true, false, false,
     0::numeric, 0::numeric, 0::numeric, 0::numeric,
     0, true, true, 'monthly'),
  (N'تجريبي ٣ أيام', 'Trial 3 days', 'company',
     0::numeric, 0::numeric,
     0::int, 1::int, 1::int, NULL::int, NULL::int,
     true, true, false, false,
     0::numeric, 0::numeric, 0::numeric, 0::numeric,
     0, true, true, 'monthly')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month, max_listing_requests,
  max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  team_member_discount_percent, seat_unit_price_sar,
  auto_pay_discount_percent, cancellation_retention_offer_pct,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type = v.user_type
     AND coalesce(sp.is_trial_plan, false) = true
);

-- =============================================================================
-- (F) تشخيص نهائي — يجب أن يَعرض 22 صفاً نشطاً (8 رئيسية + 5 تجريبية + 9 توب-أب)
-- =============================================================================
DO $$
DECLARE r record; v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM public.subscription_plans
   WHERE is_active = true;
  RAISE NOTICE '== مجموع الصفوف النشطة بعد v7: %', v_n;

  RAISE NOTICE '-- التجريبية لكل دور --';
  FOR r IN
    SELECT user_type, sort_order, name_ar, is_active
      FROM public.subscription_plans
     WHERE is_trial_plan = true
     ORDER BY user_type
  LOOP
    RAISE NOTICE '  %/% %: %', r.user_type, r.sort_order, r.name_ar,
      CASE WHEN r.is_active THEN 'نشط' ELSE 'معطّل' END;
  END LOOP;
END $$;

COMMIT;

-- =============================================================================
-- تحقق نهائي بعد التشغيل:
--
-- SELECT user_type, sort_order, is_trial_plan, name_ar, is_active
--   FROM public.subscription_plans
--  WHERE is_active = true
--  ORDER BY user_type, is_trial_plan DESC, sort_order;
--
-- يجب أن ترى 22 صفاً موزّعة:
--   marketer:    تجريبية + 1 + 21/22/23 = 5
--   office:      تجريبية + 2 + 21/22/23 = 5
--   institution: تجريبية + 2 + 21/22/23 = 5
--   company:     تجريبية + 3 = 2
--   individual:  تجريبية + 1 + 11/12/13 = 5
-- =============================================================================
