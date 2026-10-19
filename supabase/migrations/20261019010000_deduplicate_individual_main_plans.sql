-- Consolidate duplicate individual main plans after catalog repairs.
-- Keeps the row referenced by the most subscriptions and billing records.
-- Apply manually after 20261018010000_individual_main_lifetime_plan_and_quotas.sql.

BEGIN;

LOCK TABLE public.subscription_plans,
           public.user_subscriptions,
           public.billing_transactions,
           public.subscription_promotions
  IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
  v_sort integer;
  v_keep_id uuid;
  v_duplicate record;
BEGIN
  FOR v_sort IN SELECT unnest(ARRAY[1, 14, 15]) LOOP
    SELECT p.id
      INTO v_keep_id
    FROM public.subscription_plans p
    WHERE p.user_type = 'individual'
      AND p.sort_order = v_sort
      AND coalesce(p.is_trial_plan, false) = false
    ORDER BY
      (SELECT count(*) FROM public.user_subscriptions s
        WHERE s.plan_id = p.id)
      +
      (SELECT count(*) FROM public.billing_transactions b
        WHERE b.plan_id = p.id) DESC,
      p.created_at ASC,
      p.id ASC
    LIMIT 1;

    IF v_keep_id IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_duplicate IN
      SELECT p.id
      FROM public.subscription_plans p
      WHERE p.user_type = 'individual'
        AND p.sort_order = v_sort
        AND coalesce(p.is_trial_plan, false) = false
        AND p.id <> v_keep_id
    LOOP
      UPDATE public.user_subscriptions
      SET plan_id = v_keep_id
      WHERE plan_id = v_duplicate.id;

      UPDATE public.billing_transactions
      SET plan_id = v_keep_id
      WHERE plan_id = v_duplicate.id;

      UPDATE public.subscription_promotions
      SET applies_plan_ids = (
        SELECT array_agg(DISTINCT CASE
          WHEN candidate_id = v_duplicate.id THEN v_keep_id
          ELSE candidate_id
        END)
        FROM unnest(applies_plan_ids) AS candidates(candidate_id)
      )
      WHERE applies_plan_ids IS NOT NULL
        AND v_duplicate.id = ANY(applies_plan_ids);

      DELETE FROM public.subscription_plans
      WHERE id = v_duplicate.id;
    END LOOP;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_individual_main_plan_sort_order
  ON public.subscription_plans (user_type, sort_order)
  WHERE user_type = 'individual'
    AND sort_order IN (1, 14, 15)
    AND coalesce(is_trial_plan, false) = false;

COMMIT;