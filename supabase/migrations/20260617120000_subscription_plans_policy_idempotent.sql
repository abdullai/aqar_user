-- إصلاح idempotent: إعادة إنشاء سياسات subscription_plans إن وُجدت مسبقاً
-- (آمن للتشغيل اليدوي في SQL Editor أو إعادة push)

BEGIN;

DROP POLICY IF EXISTS subscription_plans_select_active ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_subscribed ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_catalog ON public.subscription_plans;
DROP POLICY IF EXISTS subscription_plans_select_owned_inactive ON public.subscription_plans;

CREATE POLICY subscription_plans_select_catalog ON public.subscription_plans
  FOR SELECT TO authenticated, anon
  USING (is_active = true);

CREATE POLICY subscription_plans_select_owned_inactive ON public.subscription_plans
  FOR SELECT TO authenticated
  USING (
    NOT is_active
    AND public.rls_user_owns_plan(id)
  );

COMMIT;
