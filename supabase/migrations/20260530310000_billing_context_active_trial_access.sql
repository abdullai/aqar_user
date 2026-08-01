-- إضافة has_active_trial و has_marketing_feature_access إلى resolve_subscription_billing_context
-- حتى يتعرّف التطبيق على التجربة الفعّالة حتى لو فشل جلب user_subscriptions من العميل.

CREATE OR REPLACE FUNCTION public.resolve_subscription_billing_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_at text;
  v_org_id uuid;
  v_owner_uid uuid;
  v_is_team_member boolean := false;
  v_is_org_owner boolean := false;
  v_member_role text;
  v_trial_self boolean := false;
  v_trial_owner boolean := false;
  v_has_paid_sub boolean := false;
  v_has_active_trial boolean := false;
  v_fal_expires timestamptz;
  v_fal_hold boolean := false;
  v_fal_status text := 'ok';
  v_disc numeric(5,2) := 50;
  v_seat_price numeric(10,2);
  v_plan_max_members int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT
    coalesce(nullif(trim(up.account_type::text), ''), 'marketer'),
    up.org_id,
    up.fal_license_expires_at,
    coalesce(up.fal_compliance_hold, false)
  INTO v_at, v_org_id, v_fal_expires, v_fal_hold
  FROM public.users_profiles up
  WHERE up.user_id = v_uid;

  IF v_at IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'profile_not_found');
  END IF;

  SELECT o.owner_user_id, o.id, o.fal_license_expires_at
  INTO v_owner_uid, v_org_id, v_fal_expires
  FROM public.org_units o
  WHERE o.owner_user_id = v_uid
  LIMIT 1;

  IF FOUND THEN
    v_is_org_owner := true;
    v_owner_uid := v_uid;
  ELSE
    SELECT
      m.member_role,
      o.owner_user_id,
      o.id,
      o.fal_license_expires_at
    INTO v_member_role, v_owner_uid, v_org_id, v_fal_expires
    FROM public.org_memberships m
    JOIN public.org_units o ON o.id = m.org_id
    WHERE m.user_id = v_uid
      AND m.status = 'active'
    ORDER BY m.created_at DESC
    LIMIT 1;

    IF FOUND AND coalesce(v_member_role, '') <> 'owner' THEN
      v_is_team_member := true;
    END IF;
  END IF;

  v_trial_self := EXISTS (
    SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_uid
  );

  IF v_owner_uid IS NOT NULL AND v_owner_uid <> v_uid THEN
    v_trial_owner := EXISTS (
      SELECT 1 FROM public.user_trial_subscriptions_used WHERE user_id = v_owner_uid
    );
  END IF;

  v_has_paid_sub := EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = false
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  );

  IF v_is_team_member AND v_owner_uid IS NOT NULL THEN
    v_has_paid_sub := v_has_paid_sub OR EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner_uid
        AND coalesce(s.is_trial, false) = false
        AND s.status IN ('active', 'cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    );
  END IF;

  v_has_active_trial := EXISTS (
    SELECT 1 FROM public.user_subscriptions s
    WHERE s.user_id = v_uid
      AND coalesce(s.is_trial, false) = true
      AND s.status IN ('active', 'cancelled')
      AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  );

  IF v_is_team_member AND v_owner_uid IS NOT NULL AND NOT v_has_active_trial THEN
    v_has_active_trial := EXISTS (
      SELECT 1 FROM public.user_subscriptions s
      WHERE s.user_id = v_owner_uid
        AND coalesce(s.is_trial, false) = true
        AND s.status IN ('active', 'cancelled')
        AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
    );
  END IF;

  SELECT
    coalesce(p.team_member_discount_percent, 50),
    coalesce(p.seat_unit_price_sar, round(p.price_monthly * 0.5, 2)),
    p.max_members
  INTO v_disc, v_seat_price, v_plan_max_members
  FROM public.user_subscriptions s
  JOIN public.subscription_plans p ON p.id = s.plan_id
  WHERE s.user_id = coalesce(v_owner_uid, v_uid)
    AND s.status IN ('active', 'cancelled')
    AND coalesce(s.ends_at, s.end_date::timestamptz) > timezone('utc', now())
  ORDER BY s.created_at DESC
  LIMIT 1;

  IF lower(trim(v_at)) IN ('marketer','office','institution','company','agency') THEN
    IF v_fal_hold THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expires IS NOT NULL AND v_fal_expires <= timezone('utc', now()) THEN
      v_fal_status := 'blocked';
    ELSIF v_fal_expires IS NOT NULL
      AND v_fal_expires <= timezone('utc', now()) + interval '7 days' THEN
      v_fal_status := 'warn';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'account_type', v_at,
    'billing_mode', CASE
      WHEN v_is_team_member THEN 'team_member'
      WHEN v_is_org_owner THEN 'org_owner'
      ELSE 'solo'
    END,
    'is_team_member', v_is_team_member,
    'is_org_owner', v_is_org_owner,
    'is_org_entity', lower(trim(v_at)) IN ('office','institution','company','agency'),
    'is_marketing_role', lower(trim(v_at)) IN ('marketer','office','institution','company','agency'),
    'org_id', v_org_id,
    'org_owner_user_id', v_owner_uid,
    'member_role', v_member_role,
    'trial_used_by_self', v_trial_self,
    'trial_used_by_org_owner', v_trial_owner,
    'can_show_trial_tab', (
      lower(trim(v_at)) IN ('marketer','office','institution','company','agency')
      AND NOT v_is_team_member
      AND NOT v_trial_self
      AND NOT v_has_paid_sub
      AND NOT v_has_active_trial
    ),
    'show_team_member_note', v_is_team_member,
    'team_member_discount_percent', v_disc,
    'seat_unit_price_sar', v_seat_price,
    'plan_max_members', v_plan_max_members,
    'has_active_paid_subscription', v_has_paid_sub,
    'has_active_trial', v_has_active_trial,
    'has_marketing_feature_access', (v_has_paid_sub OR v_has_active_trial),
    'fal_status', v_fal_status,
    'fal_license_expires_at', v_fal_expires,
    'fal_compliance_hold', v_fal_hold,
    'payment_blocked_fal', (v_fal_status = 'blocked')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_subscription_billing_context() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_subscription_billing_context()
  TO authenticated, service_role;
