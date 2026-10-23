-- Keep the individual lifetime main plan in the authenticated plan catalog.
-- This is a separate migration so databases that already applied the
-- role-aware catalog migration receive the correction as well.
BEGIN;

CREATE OR REPLACE FUNCTION public.subscription_allowed_sorts_for_audience(
  p_audience text
)
RETURNS int[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE lower(trim(coalesce(p_audience, '')))
    WHEN 'marketer' THEN ARRAY[1, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'office' THEN ARRAY[2, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'institution' THEN ARRAY[2, 4, 11, 12, 16, 21, 22, 24]
    WHEN 'company' THEN ARRAY[3, 4, 11, 12, 16, 24]
    WHEN 'photographer' THEN ARRAY[31, 32, 33]
    WHEN 'individual' THEN ARRAY[1, 14, 11, 12, 15, 16, 23]
    ELSE ARRAY[]::int[]
  END;
$$;

COMMIT;
