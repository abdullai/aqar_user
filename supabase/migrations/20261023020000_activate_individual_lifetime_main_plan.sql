-- Activates the individual one-time main plan (sort_order 15) that was left
-- inactive, so it appears in the catalog. Rows are updated, never deleted.
BEGIN;

UPDATE public.subscription_plans
   SET is_active = true,
       plan_program = 'lifetime_one_time'
 WHERE user_type = 'individual'
   AND sort_order = 15
   AND coalesce(is_trial_plan, false) = false;

COMMIT;
