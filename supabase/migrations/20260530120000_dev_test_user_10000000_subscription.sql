-- دعم حساب الاختبار 10000000 (8 أرقام) كمرادف لـ 100000000 / 1000000000
--   SELECT public.dev_grant_marketing_test_subscription('10000000');

CREATE OR REPLACE FUNCTION public.dev_test_identity_digit_variants(p_digits text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_remove(array_agg(DISTINCT v), NULL)
  FROM (
    SELECT nullif(regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g'), '') AS base
  ) b,
  LATERAL (
    SELECT unnest(
      CASE
        WHEN b.base IS NULL THEN ARRAY[]::text[]
        ELSE ARRAY[
          b.base,
          lpad(b.base, 10, '0'),
          CASE WHEN length(b.base) = 8 THEN b.base || '00' END,
          CASE WHEN length(b.base) = 9 THEN b.base || '0' END,
          CASE
            WHEN length(b.base) = 10 AND right(b.base, 1) = '0'
            THEN left(b.base, 9)
          END,
          CASE
            WHEN length(b.base) = 10 AND right(b.base, 2) = '00'
            THEN left(b.base, 8)
          END
        ]
      END
    ) AS v
  ) x;
$$;

-- فهرس تسريع «طلباتي» — طلبات السوق حسب مقدّم الطلب
CREATE INDEX IF NOT EXISTS idx_market_property_requests_requester_created
  ON public.market_property_requests (requester_id, created_at DESC)
  WHERE requester_id IS NOT NULL;

-- منح اشتراك تجريبي لحسابات الاختبار المعروفة (إن وُجدت)
DO $$
BEGIN
  PERFORM public.dev_grant_marketing_test_subscription('10000000');
  PERFORM public.dev_grant_marketing_test_subscription('100000000');
  PERFORM public.dev_grant_marketing_test_subscription('1000000000');
EXCEPTION
  WHEN undefined_function THEN NULL;
  WHEN insufficient_privilege THEN NULL;
END $$;
