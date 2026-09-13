-- مسار عروض التسويق: صف marketer_profiles، حد 6 عروض، إبقاء العروض الأخرى
-- معلّقة حتى النشر، وإعادة تنشيطها عند انتهاء 72 ساعة.

BEGIN;

-- صفوف حسابات التسويق بلا marketer_profiles تكسر FK listing_offers.marketer_id
DO $$
BEGIN
  INSERT INTO public.marketer_profiles (user_id)
  SELECT up.user_id
  FROM public.users_profiles up
  WHERE lower(trim(coalesce(up.account_type, ''))) IN (
        'marketer', 'office', 'company', 'institution', 'agency'
      )
    AND NOT EXISTS (
      SELECT 1 FROM public.marketer_profiles mp WHERE mp.user_id = up.user_id
    )
  ON CONFLICT (user_id) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'marketer_profiles backfill skipped: %', SQLERRM;
END $$;

CREATE OR REPLACE FUNCTION public.ensure_marketer_profile(p_uid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type text;
BEGIN
  IF p_uid IS NULL THEN
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.marketer_profiles mp WHERE mp.user_id = p_uid
  ) THEN
    RETURN;
  END IF;

  SELECT lower(trim(coalesce(up.account_type, '')))
    INTO v_type
  FROM public.users_profiles up
  WHERE up.user_id = p_uid
  LIMIT 1;

  IF coalesce(v_type, '') NOT IN (
       'marketer', 'office', 'company', 'institution', 'agency'
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.org_memberships m
       WHERE m.user_id = p_uid
         AND lower(trim(coalesce(m.status, ''))) IN ('active', 'accepted', 'approved')
     ) THEN
    RAISE EXCEPTION 'not_a_marketer';
  END IF;

  INSERT INTO public.marketer_profiles (user_id)
  VALUES (p_uid)
  ON CONFLICT (user_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_marketer_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_marketer_profile(uuid)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.submit_listing_offer(
  p_request_id uuid,
  p_offer_amount numeric,
  p_notes text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_round int;
  v_owner uuid;
  v_existing_id uuid;
  v_existing_status text;
  v_existing_round int;
  v_id uuid;
  v_stage text;
  v_status text;
  v_live int;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  PERFORM public.ensure_marketer_profile(uid);

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id = uid THEN
    RAISE EXCEPTION 'owner_cannot_offer';
  END IF;

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  v_stage := lower(trim(coalesce(req.workflow_stage, '')));
  v_status := lower(trim(coalesce(req.status::text, '')));

  IF v_stage IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved', 'archived',
    'inactive_72h', 'inactive72h', 'owner_action_required'
  ) OR v_status IN (
    'inactive_72h', 'inactive72h', 'owner_action_required'
  ) THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  IF req.prev_selected_marketer_id IS NOT DISTINCT FROM uid
     AND coalesce(req.allow_previous_marketers_retry, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'previous_marketer_blocked';
  END IF;

  v_owner := req.owner_id;
  v_round := coalesce(req.marketing_round, 1);

  SELECT o.id,
         lower(trim(coalesce(o.status::text, ''))),
         coalesce(o.round_no, 1)
    INTO v_existing_id, v_existing_status, v_existing_round
  FROM public.listing_offers o
  WHERE o.request_id = p_request_id
    AND o.marketer_id = uid
  ORDER BY o.created_at DESC NULLS LAST, o.id DESC
  LIMIT 1
  FOR UPDATE;

  IF v_existing_id IS NOT NULL THEN
    IF v_existing_status IN ('submitted', 'pending')
       AND v_existing_round = v_round THEN
      RAISE EXCEPTION 'duplicate_offer_same_round';
    END IF;

    UPDATE public.listing_offers
       SET status = 'submitted',
           round_no = v_round,
           price = p_offer_amount,
           offer_amount = p_offer_amount,
           notes = coalesce(p_notes, ''),
           expires_at = now() + interval '72 hours',
           last_call_at = NULL,
           last_call_count = 0,
           lost_at = NULL,
           updated_at = now()
     WHERE id = v_existing_id
     RETURNING id INTO v_id;
  ELSE
    SELECT count(*)::int INTO v_live
    FROM public.listing_offers o
    WHERE o.request_id = p_request_id
      AND coalesce(o.round_no, 1) = v_round
      AND lower(trim(coalesce(o.status::text, ''))) IN (
            'submitted', 'pending', '', 'owner_accepted', 'selected'
          );
    IF coalesce(v_live, 0) >= 6 THEN
      RAISE EXCEPTION 'offers_cap_reached';
    END IF;

    INSERT INTO public.listing_offers (
      request_id,
      marketer_id,
      price,
      notes,
      status,
      round_no,
      offer_amount,
      created_at,
      expires_at
    ) VALUES (
      p_request_id,
      uid,
      p_offer_amount,
      coalesce(p_notes, ''),
      'submitted',
      v_round,
      p_offer_amount,
      now(),
      now() + interval '72 hours'
    )
    RETURNING id INTO v_id;
  END IF;

  UPDATE public.listing_requests lr
  SET
    status = 'offers_received',
    updated_at = now()
  WHERE lr.id = p_request_id
    AND lower(trim(coalesce(lr.workflow_stage, ''))) IN (
      'waiting_marketers', 'added_by_owner', ''
    );

  PERFORM public.workflow_create_notification(
    v_owner,
    'offer_received',
    'وصلك عرض تسويق جديد',
    'راجع العروض في صفحتي واختر الأنسب.',
    'listing_request',
    p_request_id,
    jsonb_build_object(
      'request_id', p_request_id,
      'offer_id', v_id,
      'deep_route', 'owner_offers',
      'main_tab', 'my_ads',
      'role', 'owner'
    )
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_listing_offer(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_listing_offer(uuid, numeric, text) TO authenticated;

-- نشر تلقائي إذا صدر تصريح REGA ولم يُنشر (72 ساعة أو قبول مسوّق لاحق).
CREATE OR REPLACE FUNCTION public._system_publish_request_with_issued_permit(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  req record;
  v_prop uuid;
  v_mid uuid;
  v_permit_no text := '';
BEGIN
  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT lp.marketer_id, coalesce(nullif(trim(lp.permit_no), ''), '')
    INTO v_mid, v_permit_no
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lower(trim(coalesce(lp.status::text, ''))) IN (
      'issued', 'approved', 'permit_issued', 'active'
    )
  ORDER BY lp.created_at DESC NULLS LAST
  LIMIT 1;

  IF req.contract_id IS NOT NULL THEN
    BEGIN
      SELECT public.publish_property_from_contract(req.contract_id) INTO v_prop;
    EXCEPTION WHEN OTHERS THEN
      v_prop := NULL;
    END;
  END IF;

  UPDATE public.listing_requests
     SET workflow_stage = 'published',
         owner_action_required_at = NULL,
         owner_action_reason = NULL,
         permit_deadline_at = NULL,
         updated_at = now()
   WHERE id = p_request_id
     AND lower(trim(coalesce(workflow_stage, ''))) IS DISTINCT FROM 'published';

  IF v_prop IS NULL THEN
    SELECT p.id INTO v_prop
    FROM public.properties p
    WHERE p.request_id = p_request_id
    ORDER BY p.created_at DESC NULLS LAST
    LIMIT 1;
  END IF;
  IF v_prop IS NULL THEN
    v_prop := req.preview_property_id;
  END IF;

  IF v_prop IS NOT NULL THEN
    UPDATE public.properties p
       SET workflow_stage = 'published',
           status = 'published',
           published_at = coalesce(p.published_at, now()),
           published_by_marketer_id = coalesce(
             p.published_by_marketer_id, v_mid, req.selected_marketer_id
           ),
           updated_at = now()
     WHERE p.id = v_prop;
  END IF;

  BEGIN
    INSERT INTO public.regc_user_complaints (
      user_id, subject, body, status, kind, contact_channel, details
    )
    VALUES (
      coalesce(req.owner_id, v_mid),
      'تعارض تصريح إعلان REGA',
      'طلب تسويق ' || p_request_id::text ||
        CASE WHEN v_permit_no <> '' THEN ' (رقم ' || v_permit_no || ')' ELSE '' END ||
        ': وُجد تصريح صادر من الهيئة. نُشر الإعلان في الرئيسية تلقائياً ويحتاج مراجعة الدعم.',
      'open',
      'complaint',
      'in_app',
      jsonb_build_object(
        'assist_category', 'rega_permit_conflict',
        'request_id', p_request_id,
        'auto_published', true,
        'permit_no', v_permit_no
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_prop;
END;
$$;

REVOKE ALL ON FUNCTION public._system_publish_request_with_issued_permit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._system_publish_request_with_issued_permit(uuid)
  TO service_role;

-- عند القبول: لا تُرفض العروض الأخرى حتى النشر.
CREATE OR REPLACE FUNCTION public.accept_listing_offer(p_offer_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_round int;
  v_prior_issued boolean := false;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO off FROM public.listing_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = off.request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  v_round := coalesce(req.marketing_round, 1);
  IF coalesce(off.round_no, 1) IS DISTINCT FROM v_round THEN
    RAISE EXCEPTION 'stale_round';
  END IF;

  IF req.selected_marketer_id IS NOT NULL
     AND req.selected_marketer_id IS DISTINCT FROM off.marketer_id
     AND lower(trim(coalesce(req.workflow_stage, ''))) NOT IN (
       'waiting_marketers', 'offers_received', 'owner_action_required',
       'inactive_72h', 'inactive72h', 'added_by_owner', ''
     ) THEN
    RAISE EXCEPTION 'offer_already_selected';
  END IF;

  UPDATE public.listing_offers
  SET status = 'owner_accepted',
      owner_responded_at = now(),
      lost_at = NULL,
      updated_at = now()
  WHERE id = p_offer_id;

  UPDATE public.listing_requests
  SET
    selected_offer_id = p_offer_id,
    selected_marketer_id = off.marketer_id,
    workflow_stage = 'contract_signed',
    contract_started_at = coalesce(req.contract_started_at, now()),
    contract_signed_at = coalesce(req.contract_signed_at, now()),
    permit_deadline_at = NULL,
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.ensure_signed_listing_contract_for_publish(off.request_id);

  v_prior_issued := EXISTS (
    SELECT 1
    FROM public.listing_permits lp
    WHERE lp.request_id = off.request_id
      AND lp.marketer_id IS DISTINCT FROM off.marketer_id
      AND lower(trim(coalesce(lp.status::text, ''))) IN (
        'issued', 'approved', 'permit_issued', 'active'
      )
  );
  IF v_prior_issued THEN
    PERFORM public._system_publish_request_with_issued_permit(off.request_id);
  END IF;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_accepted',
    'تم قبول عرضك',
    'تابع إصدار التصريح من تبويب «إصدار التصريح» في صفحتي.',
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer',
      'my_ads_sub_tab', '2',
      'hub_tab_schema_v', '4'
    )
  );
END;
$$;

-- الإبقاء على العروض معلّقة حتى النشر (لا تُعلَم خاسرة عند اختيار المسوّق).
CREATE OR REPLACE FUNCTION public._tr_listing_requests_mark_losing()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public._listing_close_unselected_offers()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;
  IF lower(trim(coalesce(NEW.workflow_stage, ''))) = 'published'
     AND lower(trim(coalesce(OLD.workflow_stage, ''))) IS DISTINCT FROM 'published' THEN
    UPDATE public.listing_offers o
       SET status = 'owner_rejected',
           lost_at = coalesce(o.lost_at, now()),
           updated_at = now()
     WHERE o.request_id = NEW.id
       AND o.id IS DISTINCT FROM NEW.selected_offer_id
       AND lower(trim(coalesce(o.status::text, ''))) IN (
         'submitted', 'pending', ''
       );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_listing_close_unselected_offers ON public.listing_requests;
CREATE TRIGGER trg_listing_close_unselected_offers
AFTER UPDATE OF workflow_stage ON public.listing_requests
FOR EACH ROW
EXECUTE FUNCTION public._listing_close_unselected_offers();

CREATE OR REPLACE FUNCTION public.cron_expire_marketer_permit_72h()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_count int := 0;
  v_has_issued boolean;
BEGIN
  FOR r IN
    SELECT id, owner_id, selected_marketer_id, selected_offer_id, permit_deadline_at
      FROM public.listing_requests
     WHERE lower(trim(coalesce(workflow_stage,''))) IN (
           'marketer_selected',
           'contract_signed',
           'permit_pending',
           'awaiting_permits',
           'pending_permits',
           'permit_issued'
         )
       AND permit_deadline_at IS NOT NULL
       AND permit_deadline_at < now()
       AND owner_action_required_at IS NULL
     LIMIT 500
  LOOP
    v_has_issued := EXISTS (
      SELECT 1
      FROM public.listing_permits lp
      WHERE lp.request_id = r.id
        AND lp.marketer_id IS NOT DISTINCT FROM r.selected_marketer_id
        AND lower(trim(coalesce(lp.status::text, ''))) IN (
          'issued', 'approved', 'permit_issued', 'active'
        )
    );

    IF v_has_issued THEN
      PERFORM public._system_publish_request_with_issued_permit(r.id);
      IF r.owner_id IS NOT NULL THEN
        PERFORM public.workflow_create_notification(
          r.owner_id,
          'workflow.permit.expired_72h_published',
          'نُشر الإعلان تلقائياً',
          'انتهت مهلة 72 ساعة ووُجد تصريح صادر. نُشر الإعلان في الرئيسية وأُبلغ الدعم.',
          'listing_request',
          r.id,
          jsonb_build_object(
            'reason', 'publish_72h_expired_with_rega_permit',
            'priority', 'high',
            'rega_permit_conflict', true,
            'auto_published', true
          )
        );
      END IF;
      v_count := v_count + 1;
      CONTINUE;
    END IF;

    UPDATE public.listing_requests
       SET workflow_stage = 'owner_action_required',
           owner_action_required_at = now(),
           owner_action_reason = 'publish_72h_expired',
           inactive_72h_at = now(),
           prev_selected_marketer_id = coalesce(prev_selected_marketer_id, selected_marketer_id),
           selected_marketer_id = NULL,
           selected_offer_id = NULL,
           allow_previous_marketers_retry = false,
           auto_expired_at = now(),
           updated_at = now()
     WHERE id = r.id;

    IF r.selected_offer_id IS NOT NULL THEN
      UPDATE public.listing_offers
         SET status = 'expired',
             updated_at = now()
       WHERE id = r.selected_offer_id;
    END IF;

    -- العروض المعلّقة تعود نشطة ليختار المالك مسوّقاً آخر
    UPDATE public.listing_offers o
       SET status = 'submitted',
           lost_at = NULL,
           updated_at = now()
     WHERE o.request_id = r.id
       AND o.id IS DISTINCT FROM r.selected_offer_id
       AND o.marketer_id IS DISTINCT FROM r.selected_marketer_id
       AND lower(trim(coalesce(o.status::text, ''))) IN (
         'submitted', 'pending', 'owner_rejected', ''
       );

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'workflow.permit.expired_72h',
        'انتهت مهلة 72 ساعة',
        'لم يُنشر الإعلان خلال 72 ساعة. يمكنك اختيار مسوّق آخر من العروض المعلّقة.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'reason', 'publish_72h_expired',
          'priority', 'high',
          'rega_permit_conflict', false,
          'my_ads_sub_tab', '3',
          'hub_tab_schema_v', '4'
        )
      );
    END IF;

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'workflow.permit.lost_72h',
        'انتهت مهلة 72 ساعة',
        'انتهت مهلة النشر. لن يظهر لك الطلب إلا بعد «إتاحة فرصة».',
        'listing_request',
        r.id,
        jsonb_build_object(
          'reason', 'publish_72h_expired',
          'my_ads_sub_tab', '3',
          'hub_tab_schema_v', '4'
        )
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'expired_count', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_marketer_permit_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_marketer_permit_72h()
  TO authenticated, service_role;

-- المسوّق السابق المحروم يفعّل «إتاحة فرصة» ليُسمح له بتقديم عرض جديد.
CREATE OR REPLACE FUNCTION public.marketer_grant_72h_opportunity(
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.prev_selected_marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_previous_marketer';
  END IF;

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN (
       'owner_action_required', 'inactive_72h', 'inactive72h',
       'waiting_marketers', 'offers_received'
     ) THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  UPDATE public.listing_requests
     SET allow_previous_marketers_retry = true,
         updated_at = now()
   WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', true, 'request_id', p_request_id);
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_grant_72h_opportunity(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_grant_72h_opportunity(uuid)
  TO authenticated;

COMMIT;
