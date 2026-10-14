-- One-shot Supabase SQL Editor repair matching migration
-- 20261014010000_individual_deal_plan_catalog_visibility.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_audience, '')))
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 13, 21, 22, 23]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 13]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    WHEN 'individual' THEN ARRAY[1, 14, 11, 12, 13]
    ELSE ARRAY[]::int[]
  END;
$$;

COMMIT;