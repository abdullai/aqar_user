-- Restores the canonical subscription catalog RPC. The catalog depends only on
-- the account type and active plan rows, never on the user's history, so old
-- and new accounts see the same plans for their role.
BEGIN;

CREATE OR REPLACE FUNCTION public.list_subscription_catalog_plans(
  p_account_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_plan_type text;
  v_allowed int[];
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required', 'plans', '[]'::jsonb);
  END IF;

  v_at := nullif(lower(trim(coalesce(p_account_type, ''))), '');
  IF v_at IS NULL THEN
    SELECT coalesce(nullif(trim(up.account_type::text), ''), 'user')
      INTO v_at
    FROM public.users_profiles up
    WHERE up.user_id = v_uid;
  END IF;
  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found', 'plans', '[]'::jsonb);
  END IF;

  v_plan_type := CASE lower(trim(v_at))
    WHEN 'marketer' THEN 'marketer'
    WHEN 'office' THEN 'office'
    WHEN 'agency' THEN 'office'
    WHEN 'company' THEN 'company'
    WHEN 'institution' THEN 'institution'
    WHEN 'photographer' THEN 'photographer'
    ELSE 'individual'
  END;

  v_allowed := public.subscription_allowed_sorts_for_audience(v_plan_type);
  IF coalesce(array_length(v_allowed, 1), 0) = 0 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'account_type', v_at,
      'plan_user_type', v_plan_type,
      'plans', '[]'::jsonb
    );
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(sp) ORDER BY sp.sort_order ASC), '[]'::jsonb)
    INTO v_rows
  FROM public.subscription_plans sp
  WHERE sp.is_active = true
    AND coalesce(sp.is_trial_plan, false) = false
    AND lower(trim(sp.user_type)) = v_plan_type
    AND sp.sort_order = ANY (v_allowed);

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'plan_user_type', v_plan_type,
    'plans', coalesce(v_rows, '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.list_subscription_catalog_plans(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_subscription_catalog_plans(text)
  TO authenticated, service_role;

COMMIT;
