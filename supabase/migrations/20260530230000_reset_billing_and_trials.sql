-- =============================================================================
-- إعادة ضبط شاملة لطبقة الفوترة + التجارب (طلب المستخدم 2026-05-30)
-- =============================================================================
-- السبب:
--   • الفواتير الحالية في billing_transactions لا تعكس اشتراكاً فعلياً
--     (مزيج من اختبارات mock + اشتراكات لم تكتمل).
--   • بعض المستخدمين عُلِّموا «التجربة مستنفذة» مع كونهم لم يستخدموها.
--   • نريد بداية نظيفة قبل إطلاق سياسة الباقات v4 الجديدة.
--
-- ما يُحذف:
--   1) جميع سجلات billing_transactions.
--   2) جميع user_subscriptions (تنتفي صلاحيتها بانعدام الفواتير المقابلة).
--   3) جميع user_trial_subscriptions_used (لإعادة فتح التجربة لجميع المستخدمين).
--   4) جميع market_request_offer_quotas + market_request_offer_user_withdrawals
--      (لأن مرجعها user_subscription لن يعود موجوداً).
--   5) جميع subscription_lifecycle_events (سجل قديم لا يلزم بعد التنظيف).
--
-- ما يُبقَى:
--   • subscription_plans (تعريفات الباقات — لا تُمَس).
--   • saved_cards         (البطاقات المحفوظة للمستخدمين).
--   • extra_seats_requests (شراء مقاعد إضافية — مرتبط بالمنشأة).
--
-- ملاحظة أمان: نستخدم TRUNCATE … RESTART IDENTITY CASCADE لضمان
-- التنظيف الكامل دون ترك أيتام.
-- =============================================================================

BEGIN;

-- (1) عدّادات حصص العروض والسحوبات أولاً (مرجعها user_subscriptions)
DO $$
BEGIN
  IF to_regclass('public.market_request_offer_quotas') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.market_request_offer_quotas RESTART IDENTITY CASCADE';
  END IF;
END $$;

DO $$
BEGIN
  IF to_regclass('public.market_request_offer_user_withdrawals') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.market_request_offer_user_withdrawals RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- (2) سجلات الأحداث (lifecycle)
DO $$
BEGIN
  IF to_regclass('public.subscription_lifecycle_events') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.subscription_lifecycle_events RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- (3) الفواتير: حذف الكل
DO $$
BEGIN
  IF to_regclass('public.billing_transactions') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.billing_transactions RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- (4) الاشتراكات: حذف الكل (تشمل التجارب القديمة)
DO $$
BEGIN
  IF to_regclass('public.user_subscriptions') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.user_subscriptions RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- (5) سجل من استخدم التجربة: حذف الكل لإعادة فتح الباب
DO $$
BEGIN
  IF to_regclass('public.user_trial_subscriptions_used') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.user_trial_subscriptions_used RESTART IDENTITY CASCADE';
  END IF;
END $$;

-- (6) عروض إعادة الاحتفاظ (cancellation retention) إن وجدت
DO $$
BEGIN
  IF to_regclass('public.subscription_retention_prompts') IS NOT NULL THEN
    EXECUTE 'TRUNCATE TABLE public.subscription_retention_prompts RESTART IDENTITY CASCADE';
  END IF;
END $$;

COMMIT;

-- =============================================================================
-- تحقّق سريع:
-- SELECT
--   (SELECT count(*) FROM public.billing_transactions)                 AS billing,
--   (SELECT count(*) FROM public.user_subscriptions)                   AS subs,
--   (SELECT count(*) FROM public.user_trial_subscriptions_used)        AS trials_used,
--   (SELECT count(*) FROM public.market_request_offer_quotas)          AS quotas,
--   (SELECT count(*) FROM public.market_request_offer_user_withdrawals) AS withdraws;
-- =============================================================================
