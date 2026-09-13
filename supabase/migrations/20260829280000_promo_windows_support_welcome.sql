-- نوافذ أكواد الخصم + أهلية الاشتراك + ترحيب/تصعيد تذاكر الدعم.
-- نفّذ بعد نجاح 20260829270000.

BEGIN;

ALTER TABLE public.subscription_promotions
  ADD COLUMN IF NOT EXISTS campaign_key text;

UPDATE public.subscription_promotions
SET campaign_key = code
WHERE campaign_key IS NULL OR btrim(campaign_key) = '';

CREATE OR REPLACE FUNCTION public._ops_profile_display_name(p_uid uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    nullif(trim(up.full_name_ar), ''),
    nullif(trim(up.full_name), ''),
    nullif(trim(up.username), ''),
    'عميل'
  )
  FROM public.users_profiles up
  WHERE up.user_id = p_uid;
$$;

CREATE OR REPLACE FUNCTION public._ops_has_active_paid_sub(p_uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    WHERE s.user_id = p_uid
      AND s.status = 'active'
      AND coalesce(s.ends_at, s.end_date::timestamptz) > now()
  );
$$;

DROP FUNCTION IF EXISTS public.quote_promo_code(text, numeric);

CREATE OR REPLACE FUNCTION public.quote_promo_code(
  p_code text,
  p_amount_sar numeric,
  p_is_renew boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := public._promo_norm_code(p_code);
  p public.subscription_promotions%ROWTYPE;
  v_before numeric := greatest(0, round(coalesce(p_amount_sar, 0), 2));
  v_after numeric;
  v_used int;
  v_type text;
  v_at text;
  v_ckey text;
BEGIN
  PERFORM public._promo_purge_stale_holds();
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_code IS NULL OR char_length(v_code) < 2 OR char_length(v_code) > 64 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_required');
  END IF;
  SELECT * INTO p
  FROM public.subscription_promotions
  WHERE lower(code) = lower(v_code)
  LIMIT 1;
  IF NOT FOUND OR NOT coalesce(p.is_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_code');
  END IF;
  IF p.valid_from IS NOT NULL AND now() < p.valid_from THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_started');
  END IF;
  IF p.valid_to IS NOT NULL AND now() > p.valid_to THEN
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;
  IF public._ops_has_active_paid_sub(v_uid) AND NOT coalesce(p_is_renew, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'has_active_subscription');
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.subscription_promotion_redemptions r
    WHERE r.promotion_id = p.id
      AND r.user_id = v_uid
      AND r.billing_transaction_id IS NOT NULL
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_used');
  END IF;

  v_ckey := coalesce(nullif(btrim(p.campaign_key), ''), p.code);
  IF EXISTS (
    SELECT 1
    FROM public.subscription_promotion_redemptions r
    JOIN public.subscription_promotions o ON o.id = r.promotion_id
    WHERE r.user_id = v_uid
      AND r.billing_transaction_id IS NOT NULL
      AND o.id <> p.id
      AND coalesce(o.is_active, false)
      AND (o.valid_from IS NULL OR o.valid_from <= now())
      AND (o.valid_to IS NULL OR o.valid_to > now())
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'other_campaign_active');
  END IF;

  SELECT count(*)::int INTO v_used
  FROM public.subscription_promotion_redemptions
  WHERE promotion_id = p.id
    AND billing_transaction_id IS NOT NULL;
  IF p.max_redemptions IS NOT NULL AND v_used >= p.max_redemptions THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sold_out');
  END IF;

  SELECT coalesce(nullif(trim(account_type), ''), 'user') INTO v_at
  FROM public.users_profiles WHERE user_id = v_uid;
  v_type := public._promo_account_plan_type(v_at);
  IF p.applies_user_types IS NOT NULL AND cardinality(p.applies_user_types) > 0 THEN
    IF NOT (v_type = ANY (p.applies_user_types)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'wrong_audience');
    END IF;
  END IF;

  v_after := v_before;
  IF p.kind = 'percent_off' THEN
    v_after := round(v_before * (1 - least(greatest(p.value, 0), 100) / 100.0), 2);
  ELSIF p.kind IN ('fixed_off', 'first_payment_bonus') THEN
    v_after := greatest(0, round(v_before - coalesce(p.value, 0), 2));
  ELSIF p.kind = 'trial_days' THEN
    v_after := v_before;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'promotion_id', p.id,
    'code', p.code,
    'kind', p.kind,
    'value', p.value,
    'trial_days', p.trial_days,
    'campaign_key', v_ckey,
    'valid_from', p.valid_from,
    'valid_to', p.valid_to,
    'title_ar', p.title_ar,
    'title_en', p.title_en,
    'amount_before', v_before,
    'amount_after', v_after
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.promo_checkout_eligibility()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'can_use', false, 'error', 'auth_required');
  END IF;
  IF public._ops_has_active_paid_sub(v_uid) THEN
    RETURN jsonb_build_object(
      'ok', true,
      'can_use', false,
      'error', 'has_active_subscription'
    );
  END IF;
  RETURN jsonb_build_object('ok', true, 'can_use', true);
END;
$$;

DROP FUNCTION IF EXISTS public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean, timestamptz, timestamptz, int);

CREATE OR REPLACE FUNCTION public.platform_staff_upsert_promo(
  p_code text,
  p_kind text DEFAULT 'percent_off',
  p_value numeric DEFAULT 0,
  p_title_ar text DEFAULT '',
  p_title_en text DEFAULT '',
  p_active boolean DEFAULT true,
  p_valid_from timestamptz DEFAULT NULL,
  p_valid_to timestamptz DEFAULT NULL,
  p_max_redemptions int DEFAULT NULL,
  p_campaign_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_code text := public._promo_norm_code(p_code);
  v_kind text := lower(trim(coalesce(p_kind, 'percent_off')));
  v_id uuid;
  v_ckey text := public._promo_norm_code(p_campaign_key);
BEGIN
  IF v_uid IS NULL OR NOT public.is_platform_staff(v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT (
    coalesce((SELECT is_owner FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_promo FROM public.platform_staff WHERE user_id = v_uid), false)
    OR coalesce((SELECT can_finance FROM public.platform_staff WHERE user_id = v_uid), false)
  ) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_promo');
  END IF;
  IF v_code IS NULL OR char_length(v_code) < 2 OR char_length(v_code) > 64 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'code_required');
  END IF;
  IF v_kind NOT IN ('percent_off', 'fixed_off', 'trial_days', 'first_payment_bonus') THEN
    v_kind := 'percent_off';
  END IF;
  IF v_ckey IS NULL THEN
    v_ckey := v_code;
  END IF;
  SELECT id INTO v_id FROM public.subscription_promotions WHERE lower(code) = lower(v_code);
  IF v_id IS NOT NULL THEN
    UPDATE public.subscription_promotions SET
      kind = v_kind,
      value = coalesce(p_value, 0),
      title_ar = p_title_ar,
      title_en = p_title_en,
      is_active = coalesce(p_active, true),
      per_user_limit = 1,
      valid_from = p_valid_from,
      valid_to = p_valid_to,
      max_redemptions = p_max_redemptions,
      campaign_key = v_ckey
    WHERE id = v_id;
  ELSE
    INSERT INTO public.subscription_promotions (
      code, kind, value, title_ar, title_en, is_active, per_user_limit,
      valid_from, valid_to, max_redemptions, campaign_key
    ) VALUES (
      v_code, v_kind, coalesce(p_value, 0), p_title_ar, p_title_en,
      coalesce(p_active, true), 1, p_valid_from, p_valid_to, p_max_redemptions, v_ckey
    ) RETURNING id INTO v_id;
  END IF;
  PERFORM public._staff_audit(
    'upsert_promo', 'subscription_promotions', v_id::text,
    jsonb_build_object('code', v_code, 'campaign_key', v_ckey)
  );
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'code', v_code, 'campaign_key', v_ckey);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_promos()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'rows', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'code', p.code,
        'kind', p.kind,
        'value', p.value,
        'title_ar', p.title_ar,
        'title_en', p.title_en,
        'is_active', p.is_active,
        'valid_from', p.valid_from,
        'valid_to', p.valid_to,
        'max_redemptions', p.max_redemptions,
        'campaign_key', coalesce(p.campaign_key, p.code),
        'used', (
          SELECT count(*)::int FROM public.subscription_promotion_redemptions r
          WHERE r.promotion_id = p.id AND r.billing_transaction_id IS NOT NULL
        )
      ) ORDER BY p.created_at DESC)
      FROM public.subscription_promotions p
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public._ops_pick_support_assignee(p_category text)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid;
  v_need_finance boolean := lower(coalesce(p_category, '')) = 'billing';
  v_need_mod boolean := lower(coalesce(p_category, '')) = 'moderation';
BEGIN
  SELECT ps.user_id INTO v_uid
  FROM public.platform_staff ps
  JOIN public.users_profiles up ON up.user_id = ps.user_id
  WHERE coalesce(ps.is_active, true)
    AND (
      ps.is_owner
      OR (v_need_finance AND coalesce(ps.can_finance, false))
      OR (v_need_mod AND (coalesce(ps.can_ban, false) OR coalesce(ps.can_moderate, false)))
      OR (NOT v_need_finance AND NOT v_need_mod AND coalesce(ps.can_support, false))
      OR coalesce(ps.can_support, false)
    )
    AND up.chat_last_seen_at IS NOT NULL
    AND up.chat_last_seen_at > now() - interval '2 minutes'
  ORDER BY up.chat_last_seen_at DESC
  LIMIT 1;
  IF v_uid IS NOT NULL THEN
    RETURN v_uid;
  END IF;
  SELECT ps.user_id INTO v_uid
  FROM public.platform_staff ps
  WHERE coalesce(ps.is_active, true)
    AND (
      ps.is_owner
      OR coalesce(ps.can_support, false)
      OR (v_need_finance AND coalesce(ps.can_finance, false))
    )
  ORDER BY ps.is_owner DESC, ps.can_support DESC
  LIMIT 1;
  RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.support_submit_complaint_v1(
  p_kind text,
  p_subject text,
  p_body text,
  p_contact_channel text,
  p_details jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_kind text := lower(trim(coalesce(p_kind, 'complaint')));
  v_channel text := lower(trim(coalesce(p_contact_channel, 'in_app')));
  v_name text;
  v_cat text;
  v_assignee uuid;
  v_welcome_ar text;
  v_welcome_en text;
  v_details jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF length(trim(coalesce(p_subject, ''))) < 2 THEN
    RAISE EXCEPTION 'subject_required';
  END IF;
  IF length(trim(coalesce(p_body, ''))) < 5 THEN
    RAISE EXCEPTION 'body_required';
  END IF;
  IF v_kind NOT IN ('complaint', 'suggestion') THEN
    v_kind := 'complaint';
  END IF;
  IF v_channel NOT IN ('whatsapp', 'in_app') THEN
    v_channel := 'in_app';
  END IF;

  v_name := public._ops_profile_display_name(v_uid);
  v_cat := coalesce(p_details->>'assist_category', 'general');
  v_assignee := public._ops_pick_support_assignee(v_cat);
  v_welcome_ar := 'مرحباً ' || v_name || '، معك الدعم الآلي لموثوق لاين. كيف نقدر نخدمك؟ سنحوّل طلبك لأقرب مختص إن احتجت.';
  v_welcome_en := 'Hello ' || v_name || ', this is Mawthuq Line automated support. How can we help? We will route you to the nearest specialist if needed.';

  v_details := coalesce(p_details, '{}'::jsonb) || jsonb_build_object(
    'user_resolution', 'open',
    'submitted_at', to_jsonb(now()),
    'assigned_to', v_assignee,
    'requester_name', v_name,
    'chat_thread', jsonb_build_array(
      jsonb_build_object(
        'role', 'bot',
        'text', v_welcome_ar,
        'text_en', v_welcome_en,
        'at', now()
      )
    )
  );

  INSERT INTO public.regc_user_complaints (
    user_id, subject, body, status, kind, contact_channel, details
  )
  VALUES (
    v_uid, trim(p_subject), trim(p_body), 'open', v_kind, v_channel, v_details
  )
  RETURNING id INTO v_id;

  BEGIN
    PERFORM public.workflow_create_notification(
      v_uid,
      'support_ticket',
      'تم استلام تذكرة الدعم',
      v_welcome_ar,
      'complaint',
      v_id,
      jsonb_build_object(
        'title_ar', 'تم استلام تذكرتك',
        'title_en', 'Support ticket received',
        'body_ar', v_welcome_ar,
        'body_en', v_welcome_en
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  IF v_assignee IS NOT NULL THEN
    BEGIN
      PERFORM public.workflow_create_notification(
        v_assignee,
        'ops_team',
        'تذكرة دعم جديدة',
        coalesce(nullif(trim(p_subject), ''), 'تذكرة'),
        'complaint',
        v_id,
        jsonb_build_object(
          'title_ar', 'تذكرة دعم جديدة — ' || v_name,
          'title_en', 'New support ticket — ' || v_name,
          'body_ar', trim(p_subject),
          'body_en', trim(p_subject)
        )
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_open_ticket(p_complaint_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  r public.regc_user_complaints%ROWTYPE;
  v_staff_name text;
  v_req text;
  v_thread jsonb;
  v_ar text;
  v_en text;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  IF coalesce(r.details->>'staff_welcomed', '') = 'true' THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;
  v_staff_name := public._ops_profile_display_name(v_staff);
  v_req := coalesce(
    nullif(trim(r.details->>'requester_name'), ''),
    public._ops_profile_display_name(r.user_id)
  );
  v_ar := 'مرحباً ' || v_req || '، معك ' || v_staff_name || ' من دعم المنصة. كيف نقدر نخدمك؟';
  v_en := 'Hello ' || v_req || ', this is ' || v_staff_name || ' from platform support. How can we help you?';
  v_thread := coalesce(r.details->'chat_thread', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'role', 'staff',
      'text', v_ar,
      'text_en', v_en,
      'at', now(),
      'by', v_staff,
      'staff_name', v_staff_name
    )
  );
  UPDATE public.regc_user_complaints
  SET details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
    'chat_thread', v_thread,
    'staff_welcomed', 'true',
    'assigned_to', v_staff,
    'assigned_name', v_staff_name
  )
  WHERE id = p_complaint_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_reply_complaint(
  p_complaint_id uuid,
  p_reply text,
  p_status text DEFAULT 'awaiting_user'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_reply text := trim(coalesce(p_reply, ''));
  v_status text := lower(trim(coalesce(p_status, 'awaiting_user')));
  r public.regc_user_complaints%ROWTYPE;
  v_thread jsonb;
  v_staff_name text;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_support FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_support');
  END IF;
  IF length(v_reply) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reply_required');
  END IF;
  IF v_status NOT IN ('open', 'awaiting_user', 'escalated', 'resolved', 'closed') THEN
    v_status := 'awaiting_user';
  END IF;

  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  v_staff_name := public._ops_profile_display_name(v_staff);
  IF coalesce(r.details->>'staff_welcomed', '') IS DISTINCT FROM 'true' THEN
    PERFORM public.platform_staff_open_ticket(p_complaint_id);
    SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  END IF;

  v_thread := coalesce(r.details->'chat_thread', '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'role', 'staff',
      'text', v_reply,
      'at', now(),
      'by', v_staff,
      'staff_name', v_staff_name
    )
  );

  UPDATE public.regc_user_complaints
  SET
    status = v_status,
    details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
      'admin_reply', v_reply,
      'admin_reply_at', to_jsonb(now()),
      'admin_reply_by', v_staff,
      'assigned_name', v_staff_name,
      'chat_thread', v_thread,
      'solution_summary', CASE WHEN v_status IN ('resolved', 'closed') THEN v_reply ELSE r.details->>'solution_summary' END,
      'resolved_by', CASE WHEN v_status IN ('resolved', 'closed') THEN v_staff_name ELSE r.details->>'resolved_by' END
    )
  WHERE id = p_complaint_id;

  PERFORM public._staff_audit(
    CASE WHEN v_status IN ('resolved', 'closed') THEN 'support_closed' ELSE 'support_reply' END,
    'regc_user_complaints',
    p_complaint_id::text,
    jsonb_build_object('status', v_status, 'staff', v_staff_name)
  );

  BEGIN
    PERFORM public.workflow_create_notification(
      r.user_id,
      'support_ticket',
      CASE WHEN v_status IN ('resolved', 'closed')
        THEN 'تم إغلاق تذكرة الدعم'
        ELSE 'رد على تذكرة الدعم'
      END,
      v_reply,
      'complaint',
      p_complaint_id,
      jsonb_build_object(
        'title_ar', CASE WHEN v_status IN ('resolved', 'closed')
          THEN 'تم حل تذكرتك — ' || v_staff_name
          ELSE 'رد من ' || v_staff_name
        END,
        'title_en', CASE WHEN v_status IN ('resolved', 'closed')
          THEN 'Ticket resolved — ' || v_staff_name
          ELSE 'Reply from ' || v_staff_name
        END,
        'body_ar', v_reply,
        'body_en', v_reply
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public._ops_profile_display_name(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_has_active_paid_sub(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_pick_support_assignee(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.quote_promo_code(text, numeric, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.quote_promo_code(text, numeric, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.promo_checkout_eligibility() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promo_checkout_eligibility() TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean, timestamptz, timestamptz, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_upsert_promo(text, text, numeric, text, text, boolean, timestamptz, timestamptz, int, text) TO authenticated;
REVOKE ALL ON FUNCTION public.platform_staff_open_ticket(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.platform_staff_open_ticket(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.promo_checkout_eligibility() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.promo_checkout_eligibility() TO authenticated;

COMMIT;
