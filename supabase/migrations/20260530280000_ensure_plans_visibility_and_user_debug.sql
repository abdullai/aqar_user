-- =============================================================================
-- 2026-05-30 — تأكيد ظهور الباقات لكل دور
-- =============================================================================
-- الهدف:
--   1) ضمان وجود الباقات الأساسية (sort_order = 1) لكل دور تسويقي ولكل
--      «individual» في حال حُذِفت أو عُطِّلت بطريق الخطأ.
--   2) إعادة تفعيل الباقات حسب سياسة الدور (1 للمسوّق · 2 للمكتب/المؤسسة ·
--      3 للشركة · 1 + 11/12/13 للفرد).
--   3) تنظيف أي صفوف `is_trial_plan = true` متكررة وإبقاء واحد فقط لكل دور.
--   4) تشخيص مرتبط للمستخدم 1000000000:
--        أ) RPC اختياري [debug_user_subscription_state(p_username text)]
--           يُعيد JSON تفصيلي عن الفترة التجريبية / الاشتراك / صلاحية النشر.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (1) إعادة تفعيل الأساسية (sort_order=1) لكل أدوار التسويق + individual
--     (لا تتأثر القيم الأخرى — التحديث على is_active فقط).
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans
   SET is_active = true
 WHERE sort_order = 1
   AND coalesce(is_trial_plan, false) = false
   AND user_type IN ('marketer','office','institution','company','individual');

-- الاحترافية: للمكاتب/المؤسسات/المسوقين/الشركات (مسموح ضمن سياسة الدور)
UPDATE public.subscription_plans
   SET is_active = true
 WHERE sort_order = 2
   AND coalesce(is_trial_plan, false) = false
   AND user_type IN ('marketer','office','institution','company');

-- المميزة: للشركات فقط (تبقى معطّلة للبقية وفق v4)
UPDATE public.subscription_plans
   SET is_active = true
 WHERE sort_order = 3
   AND coalesce(is_trial_plan, false) = false
   AND user_type = 'company';

UPDATE public.subscription_plans
   SET is_active = false
 WHERE sort_order = 3
   AND coalesce(is_trial_plan, false) = false
   AND user_type IN ('marketer','office','institution');

-- باقات عروض السوق للفرد (11/12/13)
UPDATE public.subscription_plans
   SET is_active = true
 WHERE coalesce(is_trial_plan, false) = false
   AND user_type = 'individual'
   AND sort_order IN (11, 12, 13);

-- ---------------------------------------------------------------------------
-- (2) ضمان وجود الباقة الأساسية للمسوقين عند فقدها (إصلاح ذاتي).
--     لا نلمس الصفوف الموجودة — INSERT آمن فقط للحالات الفارغة.
-- ---------------------------------------------------------------------------
INSERT INTO public.subscription_plans (
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active, is_trial_plan, plan_program
)
SELECT * FROM (VALUES
  (N'الأساسية', 'Basic', 'marketer', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'office', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'institution', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly'),
  (N'الأساسية', 'Basic', 'company', 99::numeric, round((99*12*0.80)::numeric,2),
   3, NULL::int, 60::int, NULL::int, 49::int,
   true, false, false, false, 1, true, false, 'monthly')
) AS v(
  name_ar, name_en, user_type,
  price_monthly, price_yearly,
  max_members, max_properties, max_ads_per_month,
  max_listing_requests, max_market_offers,
  has_fal_license, has_analytics, has_api_access, has_priority_support,
  sort_order, is_active, is_trial_plan, plan_program
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.subscription_plans sp
   WHERE sp.user_type = v.user_type
     AND sp.sort_order = v.sort_order
     AND coalesce(sp.is_trial_plan, false) = false
);

-- ---------------------------------------------------------------------------
-- (3) RPC تشخيصية للمستخدم 1000000000 (وغيره):
--     debug_user_subscription_state(p_username text)
--     ترجع JSON موثَّق: profile / trial / active / can_publish_listing /
--     reasons[].
--     Security: SECURITY DEFINER + RAISE NOTICE فقط — لا تكشف بيانات حساسة.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.debug_user_subscription_state(
  p_username text
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_account text;
  v_fal_expiry timestamptz;
  v_fal_hold boolean := false;
  v_fal_status text := 'ok';
  v_active jsonb;
  v_trial  jsonb;
  v_trial_active boolean := false;
  v_reasons jsonb := '[]'::jsonb;
  v_can_publish boolean := false;
BEGIN
  SELECT user_id,
         lower(trim(coalesce(account_type::text, ''))),
         fal_license_expires_at,
         coalesce(fal_compliance_hold, false)
    INTO v_uid, v_account, v_fal_expiry, v_fal_hold
  FROM public.users_profiles
  WHERE username = trim(p_username)
  LIMIT 1;

  IF v_uid IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false, 'error', 'user_not_found',
      'username', p_username
    );
  END IF;

  IF v_account IN ('marketer','office','institution','company','agency') THEN
    IF v_fal_hold THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expiry IS NOT NULL AND v_fal_expiry <= timezone('utc', now()) THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expiry IS NOT NULL
      AND v_fal_expiry <= timezone('utc', now()) + interval '7 days' THEN
      v_fal_status := 'warn';
    END IF;
  END IF;

  SELECT to_jsonb(s.*) INTO v_active
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.is_trial, false) = false
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

  SELECT to_jsonb(s.*) INTO v_trial
  FROM public.user_subscriptions s
  WHERE s.user_id = v_uid
    AND coalesce(s.is_trial, false) = true
  ORDER BY s.created_at DESC
  LIMIT 1;

  v_trial_active := v_trial IS NOT NULL
    AND coalesce(
          (v_trial->>'ends_at')::timestamptz,
          (v_trial->>'end_date')::timestamptz,
          'epoch'::timestamptz
        ) > timezone('utc', now());

  IF v_account IN ('marketer','office','institution','company','agency') THEN
    IF v_active IS NULL AND NOT v_trial_active THEN
      v_reasons := v_reasons || to_jsonb('no_active_subscription_or_trial'::text);
    END IF;

    IF v_fal_status = 'blocked' THEN
      IF v_fal_hold THEN
        v_reasons := v_reasons || to_jsonb('fal_compliance_hold'::text);
      ELSIF v_fal_expiry IS NOT NULL AND v_fal_expiry <= timezone('utc', now()) THEN
        v_reasons := v_reasons || to_jsonb('fal_expired'::text);
      ELSE
        v_reasons := v_reasons || to_jsonb('fal_blocked'::text);
      END IF;
    END IF;

    v_can_publish := jsonb_array_length(v_reasons) = 0;
  ELSE
    v_reasons := v_reasons || to_jsonb('account_type_not_marketing'::text);
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'username', p_username,
    'user_id', v_uid,
    'account_type', v_account,
    'fal_status', v_fal_status,
    'fal_compliance_hold', v_fal_hold,
    'fal_license_expires_at', v_fal_expiry,
    'trial_active', v_trial_active,
    'active_subscription', v_active,
    'trial_subscription', v_trial,
    'can_publish_listing_marketer', v_can_publish,
    'block_reasons', v_reasons
  );
END;
$$;

REVOKE ALL ON FUNCTION public.debug_user_subscription_state(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debug_user_subscription_state(text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.debug_user_subscription_state(text) IS
  'تشخيص شامل لحالة الاشتراك/التجربة/فال للنشر. مثال: SELECT debug_user_subscription_state(''1000000000'');';

COMMIT;

-- =============================================================================
-- استخدام مثال:
--   SELECT debug_user_subscription_state('1000000000');
--
--   إن كان can_publish_listing_marketer = false، فحص block_reasons:
--     fal_not_verified  → استكمال الربط مع الهيئة
--     fal_expired       → تجديد رخصة فال
--     no_active_subscription_or_trial → تفعيل التجربة أو شراء باقة
--     account_type_not_marketing → تغيير نوع الحساب أو ليس مسموح للنشر
-- =============================================================================
