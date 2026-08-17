-- =============================================================================
-- 2026-06-02 — صلاحية قراءة الباقة لكل مَن اشترك بها (حتى لو عُطّلت لاحقاً)
-- =============================================================================
-- المشكلة: السياسة subscription_plans_select_active تسمح بقراءة الصفوف
-- النشطة فقط. بعد ترحيل الكانون v5 (20260602040000) أصبحت أغلب الصفوف
-- معطّلة (is_active=false) لأنّ كل دور له باقة واحدة فقط مرئية، لكنّها لا تزال
-- مرتبطة عبر FK من user_subscriptions.plan_id (لمشتركي الماضي).
--
-- بدون هذا التحديث: getPlanById لمستخدم له اشتراك على باقة معطّلة سيُعيد
-- null → الواجهة لا تستطيع عرض اسم/سعر باقته.
--
-- الحل: أضف سياسة SELECT ثانية تسمح بقراءة الصفوف الـ inactive للمستخدم
-- الذي يَملك اشتراكاً عليها.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS subscription_plans_select_subscribed
  ON public.subscription_plans;

CREATE POLICY subscription_plans_select_subscribed
  ON public.subscription_plans
  FOR SELECT
  TO authenticated
  USING (
    is_active = true
    OR EXISTS (
      SELECT 1 FROM public.user_subscriptions us
      WHERE us.plan_id = subscription_plans.id
        AND us.user_id = auth.uid()
    )
  );

-- نُبقي السياسة القديمة لـanon (يَرى الباقات النشطة فقط).
-- لا حاجة لتغيير سياسة anon.

COMMIT;
