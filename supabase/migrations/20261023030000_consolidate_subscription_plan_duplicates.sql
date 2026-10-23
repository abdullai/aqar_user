-- Keeps exactly one row per (user_type, sort_order, plan_program) for
-- non-trial plans. Preference: active, then most references, then oldest.
-- References in subscriptions, billing, payment audit and promotions are moved
-- to the kept row before the duplicates are deleted, so no history is lost.

BEGIN;

LOCK TABLE public.subscription_plans,
           public.user_subscriptions,
           public.billing_transactions,
           public.payment_security_audit,
           public.subscription_promotions
  IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  v_group record;
  v_keep_id uuid;
  v_dup record;
BEGIN
  FOR v_group IN
    SELECT user_type, sort_order, coalesce(plan_program, '') AS plan_program
    FROM public.subscription_plans
    WHERE NOT coalesce(is_trial_plan, false)
    GROUP BY user_type, sort_order, coalesce(plan_program, '')
    HAVING count(*) > 1
  LOOP
    SELECT p.id INTO v_keep_id
    FROM public.subscription_plans p
    WHERE p.user_type = v_group.user_type
      AND p.sort_order = v_group.sort_order
      AND coalesce(p.plan_program, '') = v_group.plan_program
      AND NOT coalesce(p.is_trial_plan, false)
    ORDER BY
      p.is_active DESC,
      (SELECT count(*) FROM public.user_subscriptions s WHERE s.plan_id = p.id)
        + (SELECT count(*) FROM public.billing_transactions b WHERE b.plan_id = p.id)
        + (SELECT count(*) FROM public.payment_security_audit a WHERE a.plan_id = p.id) DESC,
      p.created_at ASC,
      p.id ASC
    LIMIT 1;

    FOR v_dup IN
      SELECT p.id
      FROM public.subscription_plans p
      WHERE p.user_type = v_group.user_type
        AND p.sort_order = v_group.sort_order
        AND coalesce(p.plan_program, '') = v_group.plan_program
        AND NOT coalesce(p.is_trial_plan, false)
        AND p.id <> v_keep_id
    LOOP
      UPDATE public.user_subscriptions
         SET plan_id = v_keep_id WHERE plan_id = v_dup.id;

      UPDATE public.billing_transactions
         SET plan_id = v_keep_id WHERE plan_id = v_dup.id;

      UPDATE public.billing_transactions
         SET gateway_response = replace(
               gateway_response::text, v_dup.id::text, v_keep_id::text
             )::jsonb
       WHERE gateway_response IS NOT NULL
         AND position(v_dup.id::text IN gateway_response::text) > 0;

      UPDATE public.payment_security_audit
         SET plan_id = v_keep_id WHERE plan_id = v_dup.id;

      UPDATE public.subscription_promotions
         SET applies_plan_ids = (
           SELECT array_agg(DISTINCT CASE WHEN c = v_dup.id THEN v_keep_id ELSE c END)
           FROM unnest(applies_plan_ids) AS u(c)
         )
       WHERE applies_plan_ids IS NOT NULL
         AND v_dup.id = ANY (applies_plan_ids);

      DELETE FROM public.subscription_plans WHERE id = v_dup.id;
    END LOOP;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_subscription_plans_catalog_identity
  ON public.subscription_plans (user_type, sort_order, (coalesce(plan_program, '')))
  WHERE NOT coalesce(is_trial_plan, false);

COMMIT;
