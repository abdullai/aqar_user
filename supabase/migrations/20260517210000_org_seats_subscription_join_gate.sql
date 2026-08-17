-- حدود مقاعد: مكتب 3، مؤسسة 6، شركة 9 + بوابة اشتراك قبل قبول عضو.

CREATE OR REPLACE FUNCTION public.org_owner_has_active_subscription(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.org_units ou
    JOIN public.user_subscriptions us ON us.user_id = ou.owner_user_id
    WHERE ou.id = p_org_id
      AND us.status IN ('active', 'cancelled')
      AND (
        us.ends_at IS NULL
        OR us.ends_at > timezone('utc', now())
      )
      AND (
        us.organization_id IS NULL
        OR us.organization_id = p_org_id
      )
  );
$$;

GRANT EXECUTE ON FUNCTION public.org_owner_has_active_subscription(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ensure_my_org_unit()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_type text;
  v_org uuid;
  v_limit int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT lower(trim(account_type::text)) INTO v_type
  FROM public.users_profiles
  WHERE user_id = v_uid;

  IF v_type IS NULL OR v_type NOT IN ('office', 'institution', 'company') THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NOT NULL THEN
    v_limit := CASE v_type
      WHEN 'office' THEN 3
      WHEN 'institution' THEN 6
      WHEN 'company' THEN 9
      ELSE 3
    END;
    UPDATE public.org_units
    SET
      account_type = v_type,
      base_seat_limit = v_limit,
      updated_at = now()
    WHERE id = v_org
      AND (base_seat_limit IS DISTINCT FROM v_limit OR account_type IS DISTINCT FROM v_type);
    UPDATE public.users_profiles SET org_id = v_org WHERE user_id = v_uid AND (org_id IS DISTINCT FROM v_org);
    RETURN v_org;
  END IF;

  v_limit := CASE v_type
    WHEN 'office' THEN 3
    WHEN 'institution' THEN 6
    WHEN 'company' THEN 9
    ELSE 3
  END;

  INSERT INTO public.org_units (owner_user_id, account_type, base_seat_limit)
  VALUES (v_uid, v_type, v_limit)
  RETURNING id INTO v_org;

  INSERT INTO public.org_memberships (org_id, user_id, member_role, permissions, status)
  VALUES (
    v_org,
    v_uid,
    'owner',
    '{"manage_team": true, "add_properties": true, "add_ads": true, "view_market": true, "view_profile": true, "access_chat": true, "edit_org_settings": true, "view_analytics": true, "desk": true, "middle_nav": true}'::jsonb,
    'active'
  );

  UPDATE public.users_profiles SET org_id = v_org WHERE user_id = v_uid;

  RETURN v_org;
END;
$$;

-- تصحيح شركات كانت 12 → 9
UPDATE public.org_units
SET base_seat_limit = 9, updated_at = now()
WHERE account_type = 'company' AND base_seat_limit > 9;

-- قبول انضمام: اشتراك المالك + مقاعد
CREATE OR REPLACE FUNCTION public.org_decide_join_request(
  p_request_id uuid,
  p_approve boolean,
  p_permissions jsonb DEFAULT '{}'::jsonb,
  p_reject_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid := auth.uid();
  v_org uuid;
  v_req public.org_join_requests%ROWTYPE;
  v_lim int;
  v_cnt int;
  v_perm jsonb;
BEGIN
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authed');
  END IF;

  SELECT * INTO v_req FROM public.org_join_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF v_req.status IS DISTINCT FROM 'pending' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_pending');
  END IF;

  SELECT id INTO v_org
  FROM public.org_units
  WHERE id = v_req.org_id AND owner_user_id = v_owner
  LIMIT 1;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_owner');
  END IF;

  IF NOT p_approve THEN
    UPDATE public.org_join_requests SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner,
      reject_reason = nullif(trim(coalesce(p_reject_reason, '')), '')
    WHERE id = p_request_id;

    INSERT INTO public.org_banned_users (org_id, user_id, reason, created_by_user_id)
    VALUES (
      v_org,
      v_req.applicant_user_id,
      nullif(trim(coalesce(p_reject_reason, '')), ''),
      v_owner
    )
    ON CONFLICT (org_id, user_id) DO UPDATE SET
      reason = excluded.reason,
      created_at = now(),
      created_by_user_id = excluded.created_by_user_id;

    PERFORM public._inapp_enqueue_for_user(
      v_req.applicant_user_id,
      'org_join_rejected',
      'تم رفض طلب الانضمام',
      coalesce(nullif(trim(p_reject_reason), ''), 'لم تتم الموافقة على طلبك.'),
      jsonb_build_object(
        'title_ar', 'رفض طلب الانضمام',
        'title_en', 'Join request declined',
        'body_ar', coalesce(nullif(trim(p_reject_reason), ''), 'لم تتم الموافقة.'),
        'body_en', coalesce(nullif(trim(p_reject_reason), ''), 'Your request was declined.'),
        'org_id', v_org::text
      )
    );

    RETURN jsonb_build_object('ok', true, 'approved', false);
  END IF;

  IF NOT public.org_owner_has_active_subscription(v_org) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'owner_subscription_required');
  END IF;

  v_lim := public.org_effective_seat_limit(v_org);
  v_cnt := public.org_current_member_count(v_org);
  IF v_cnt >= v_lim THEN
    RETURN jsonb_build_object('ok', false, 'error', 'seat_limit_reached', 'limit', v_lim);
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.org_memberships WHERE user_id = v_req.applicant_user_id
  ) THEN
    UPDATE public.org_join_requests SET
      status = 'rejected',
      decided_at = now(),
      decided_by_user_id = v_owner
    WHERE id = p_request_id;
    RETURN jsonb_build_object('ok', false, 'error', 'already_member_conflict');
  END IF;

  v_perm := public.org_default_member_permissions()
    || coalesce(p_permissions, '{}'::jsonb);

  INSERT INTO public.org_memberships (
    org_id, user_id, member_role, permissions, status, invited_by_user_id
  ) VALUES (
    v_org, v_req.applicant_user_id, 'member', v_perm, 'active', v_owner
  );

  UPDATE public.users_profiles SET org_id = v_org WHERE user_id = v_req.applicant_user_id;

  UPDATE public.org_join_requests SET
    status = 'approved',
    decided_at = now(),
    decided_by_user_id = v_owner
  WHERE id = p_request_id;

  PERFORM public._inapp_enqueue_for_user(
    v_req.applicant_user_id,
    'org_join_approved',
    'تم قبولك في المنشأة',
    'أصبحت عضواً نشطاً.',
    jsonb_build_object(
      'title_ar', 'قبول في المنشأة',
      'title_en', 'Accepted to organization',
      'body_ar', 'يمكنك الآن استخدام ميزات الفريق حسب الصلاحيات.',
      'body_en', 'You can now use team features per your permissions.',
      'org_id', v_org::text
    )
  );

  RETURN jsonb_build_object('ok', true, 'approved', true);
END;
$$;
