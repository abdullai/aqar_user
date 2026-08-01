-- اشتراك تجريبي لحسابات الاختبار (username 100000000 / 1000000000).
-- إعادة التشغيل من SQL Editor:
--   SELECT public.dev_grant_marketing_test_subscription('100000000');

CREATE OR REPLACE FUNCTION public.dev_upsert_test_subscription_row(
  p_uid uuid,
  p_org_id uuid,
  p_plan_id uuid,
  p_end date,
  p_ends timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub_id uuid;
BEGIN
  SELECT s.id INTO v_sub_id
  FROM public.user_subscriptions s
  WHERE s.user_id = p_uid
    AND (
      (p_org_id IS NULL AND s.organization_id IS NULL)
      OR s.organization_id = p_org_id
    )
  ORDER BY s.end_date DESC NULLS LAST, s.created_at DESC
  LIMIT 1;

  IF v_sub_id IS NOT NULL THEN
    UPDATE public.user_subscriptions
    SET
      plan_id = p_plan_id,
      status = 'active',
      period = 'yearly',
      start_date = current_date,
      end_date = p_end,
      starts_at = coalesce(starts_at, now()),
      ends_at = p_ends,
      auto_renew = false,
      updated_at = now()
    WHERE id = v_sub_id;
  ELSE
    INSERT INTO public.user_subscriptions (
      user_id, organization_id, plan_id, status, period,
      start_date, end_date, auto_renew, starts_at, ends_at
    )
    VALUES (
      p_uid, p_org_id, p_plan_id, 'active', 'yearly',
      current_date, p_end, false, now(), p_ends
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dev_grant_marketing_test_subscription(p_digits text DEFAULT '100000000')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm text;
  v_norm10 text;
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
  v_norm := nullif(regexp_replace(trim(coalesce(p_digits, '')), '\D', '', 'g'), '');
  IF v_norm IS NULL OR length(v_norm) < 9 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_digits');
  END IF;
  v_norm10 := lpad(v_norm, 10, '0');
  v_end := current_date + 365;
  v_ends := now() + interval '365 days';

  FOR v_uid, v_at IN
    SELECT up.user_id, coalesce(nullif(trim(up.account_type), ''), 'marketer')
    FROM public.users_profiles up
    WHERE up.user_id IS NOT NULL
      AND regexp_replace(coalesce(up.username::text, ''), '\D', '', 'g')
          IN (v_norm, v_norm10, lpad(v_norm, 9, '0'))
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
    'digits', v_norm,
    'digits10', v_norm10,
    'profiles_matched', v_matched,
    'subscriptions_touched', v_granted
  );
END;
$$;

REVOKE ALL ON FUNCTION public.dev_upsert_test_subscription_row(uuid, uuid, uuid, date, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dev_grant_marketing_test_subscription(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dev_grant_marketing_test_subscription(text) TO service_role;

SELECT public.dev_grant_marketing_test_subscription('100000000');
SELECT public.dev_grant_marketing_test_subscription('1000000000');
