-- ربط 100000000 (9 أرقام) بـ 1000000000 (10) في حسابات الاختبار.
-- lpad(...,10,'0') يعطي 0100000000 ولا يطابق 1000000000.

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
          CASE WHEN length(b.base) = 9 THEN b.base || '0' END,
          CASE
            WHEN length(b.base) = 10 AND right(b.base, 1) = '0'
            THEN left(b.base, 9)
          END
        ]
      END
    ) AS v
  ) x;
$$;

CREATE OR REPLACE FUNCTION public.dev_grant_marketing_test_subscription(p_digits text DEFAULT '100000000')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_variants text[];
  v_uid uuid;
  v_at text;
  v_plan_type text;
  v_plan_id uuid;
  v_org_id uuid;
  v_end date;
  v_ends timestamptz;
  v_matched int := 0;
  v_granted int := 0;
BEGIN
  v_variants := public.dev_test_identity_digit_variants(p_digits);
  IF coalesce(array_length(v_variants, 1), 0) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_digits');
  END IF;

  v_end := current_date + 365;
  v_ends := now() + interval '365 days';

  FOR v_uid, v_at IN
    SELECT up.user_id, coalesce(nullif(trim(up.account_type), ''), 'marketer')
    FROM public.users_profiles up
    WHERE up.user_id IS NOT NULL
      AND regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g') = ANY (v_variants)
  LOOP
    v_matched := v_matched + 1;

    v_plan_type := CASE trim(lower(v_at))
      WHEN 'marketer' THEN 'marketer'
      WHEN 'office' THEN 'office'
      WHEN 'company' THEN 'office'
      WHEN 'institution' THEN 'office'
      WHEN 'agency' THEN 'office'
      ELSE 'marketer'
    END;

    SELECT id INTO v_plan_id
    FROM public.subscription_plans
    WHERE is_active = true AND user_type = v_plan_type
    ORDER BY sort_order ASC
    LIMIT 1;

    IF v_plan_id IS NULL THEN
      SELECT id INTO v_plan_id
      FROM public.subscription_plans
      WHERE is_active = true AND user_type = 'marketer'
      ORDER BY sort_order ASC
      LIMIT 1;
    END IF;

    IF v_plan_id IS NULL THEN
      CONTINUE;
    END IF;

    PERFORM public.dev_upsert_test_subscription_row(
      v_uid, NULL, v_plan_id, v_end, v_ends
    );
    v_granted := v_granted + 1;

    v_org_id := NULL;
    SELECT o.id INTO v_org_id
    FROM public.org_units o
    WHERE o.owner_user_id = v_uid
    ORDER BY o.created_at DESC NULLS LAST
    LIMIT 1;

    IF v_org_id IS NULL THEN
      SELECT m.org_id INTO v_org_id
      FROM public.org_memberships m
      WHERE m.user_id = v_uid AND m.status = 'active'
      ORDER BY m.created_at DESC NULLS LAST
      LIMIT 1;
    END IF;

    IF v_org_id IS NOT NULL THEN
      PERFORM public.dev_upsert_test_subscription_row(
        v_uid, v_org_id, v_plan_id, v_end, v_ends
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'digits', v_variants[1],
    'variants', to_jsonb(v_variants),
    'profiles_matched', v_matched,
    'subscriptions_touched', v_granted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dev_test_identity_digit_variants(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_grant_marketing_test_subscription(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_grant_marketing_test_subscription(text) TO service_role;
