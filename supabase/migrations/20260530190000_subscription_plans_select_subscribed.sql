-- السماح بقراءة باقة مرتبطة باشتراك المستخدم حتى لو أُوقفت is_active
-- (تجنّب 500/فشل embed plan:subscription_plans(*) للاشتراكات القديمة).

DROP POLICY IF EXISTS subscription_plans_select_active ON public.subscription_plans;

CREATE POLICY subscription_plans_select_active ON public.subscription_plans
  FOR SELECT TO authenticated, anon
  USING (
    is_active = true
    OR EXISTS (
      SELECT 1
      FROM public.user_subscriptions us
      WHERE us.plan_id = subscription_plans.id
        AND (
          us.user_id = auth.uid()
          OR (
            us.organization_id IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.org_units o
              WHERE o.id = us.organization_id
                AND o.owner_user_id = auth.uid()
            )
          )
        )
    )
  );

COMMENT ON POLICY subscription_plans_select_active ON public.subscription_plans IS
  'Active plans for catalog + any plan tied to the caller''s subscription rows.';
