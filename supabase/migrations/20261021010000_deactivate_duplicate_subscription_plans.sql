-- Deactivates duplicate active, non-trial subscription plans that share the
-- same (user_type, sort_order). Rows are never deleted so existing
-- subscriptions and billing history keep valid references.
-- Kept row per group: most references (subscriptions + transactions), then newest.
-- Review the preview query in the accompanying notes before applying manually.

WITH ranked AS (
  SELECT
    p.id,
    row_number() OVER (
      PARTITION BY p.user_type, p.sort_order
      ORDER BY
        (
          (SELECT count(*) FROM public.user_subscriptions s WHERE s.plan_id = p.id)
          + (SELECT count(*) FROM public.billing_transactions b WHERE b.plan_id = p.id)
        ) DESC,
        p.created_at DESC,
        p.id
    ) AS rn
  FROM public.subscription_plans p
  WHERE p.is_active AND NOT p.is_trial_plan
    AND p.user_type <> 'individual'
)
UPDATE public.subscription_plans p
   SET is_active = false
  FROM ranked r
 WHERE p.id = r.id
   AND r.rn > 1;
