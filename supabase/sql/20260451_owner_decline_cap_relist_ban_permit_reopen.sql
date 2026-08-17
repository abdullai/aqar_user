-- =============================================================================
-- وحدة متبقية من سير التسويق:
-- 1) عدّ مسوّقين مرفوضين (مميزين) في الجولة الحالية؛ عند 3 → إلغاء الطلب +
--    حظر مراجعة + إشعار للمالك (وFCM عبر webhook على in_app_notifications).
-- 2) منع تقديم عروض جديدة عند banned_under_review.
-- 3) منع إعادة طرح الطلب (relist) أثناء banned_under_review.
-- 4) انتهاء مهلة تصريح 72س: إعادة الطلب إلى waiting_marketers (جولة جديدة)
--    بدل inactive_72h، مع إلغاء العقد غير الموقّع وإشعار المالك والمسوّق.
--
-- تطبيق: نفّذ على Supabase بعد 20260447_owner_decline_listing_offer_and_notify.sql
-- وجدول pg_cron (أو جدولة Edge) لتشغيل:
--   SELECT public.cron_expire_permit_pending_72h();
--   SELECT public.cron_expire_pending_offers_72h();
-- مثال:
--   SELECT cron.schedule(
--     'expire_permit_72h', '*/15 * * * *',
--     $$SELECT public.cron_expire_permit_pending_72h()$$
--   );
-- =============================================================================

BEGIN;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS owner_distinct_marketer_declines integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.listing_requests.owner_distinct_marketer_declines IS
  'عدد المسوّقين المميزين الذين رُفضت عروضهم في marketing_round الحالية.';

-- ---------------------------------------------------------------------------
-- owner_decline_listing_offer — حد 3 مسوّقين مرفوضين + حظر
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_decline_listing_offer(
  p_offer_id uuid,
  p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_reason text;
  body_ar text;
  v_round int;
  v_distinct int;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

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

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  IF coalesce(off.status, '') NOT IN ('submitted', 'pending', '') THEN
    RAISE EXCEPTION 'offer_not_pending';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  v_round := coalesce(req.marketing_round, 1);

  UPDATE public.listing_offers
  SET
    status = 'declined',
    owner_decline_reason = v_reason,
    updated_at = now()
  WHERE id = p_offer_id;

  SELECT COUNT(DISTINCT marketer_id)::int INTO v_distinct
  FROM public.listing_offers o
  WHERE o.request_id = off.request_id
    AND coalesce(o.round_no, 1) = v_round
    AND o.status = 'declined';

  IF v_distinct >= 3 THEN
    UPDATE public.listing_offers o
    SET
      status = 'owner_rejected',
      updated_at = now()
    WHERE o.request_id = off.request_id
      AND coalesce(o.round_no, 1) = v_round
      AND o.id <> p_offer_id
      AND o.status IN ('submitted', 'pending');

    UPDATE public.listing_requests lr
    SET
      owner_distinct_marketer_declines = v_distinct,
      workflow_stage = 'cancelled',
      status = 'cancelled',
      banned_under_review = true,
      needs_manual_review = true,
      updated_at = now()
    WHERE lr.id = off.request_id;

    PERFORM public.workflow_create_notification(
      uid,
      'listing_offer_decline_limit',
      'توقف الطلب بعد 3 رفض لمسوّقين',
      'رُفضت عروض ثلاثة مسوّقين مميزين في هذه الجولة. أُوقف الطلب للمراجعة.',
      'listing_request',
      off.request_id,
      jsonb_build_object(
        'request_id', off.request_id,
        'deep_route', 'listing_request_status',
        'main_tab', 'my_ads',
        'role', 'owner',
        'owner_distinct_marketer_declines', v_distinct
      )
    );
  ELSE
    UPDATE public.listing_requests lr
    SET
      owner_distinct_marketer_declines = v_distinct,
      updated_at = now()
    WHERE lr.id = off.request_id;
  END IF;

  IF v_reason IS NULL THEN
    body_ar := 'رفض المالك عرضك. يمكنك متابعة طلبات أخرى.';
  ELSE
    body_ar := 'رفض المالك عرضك. السبب: ' || v_reason;
  END IF;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_declined',
    'تم رفض عرضك',
    body_ar,
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'offer_id', p_offer_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer',
      'owner_decline_reason', v_reason
    )
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- submit_listing_offer — رفض عند الحظر
-- ---------------------------------------------------------------------------
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
  dup int;
  v_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

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

  IF coalesce(req.workflow_stage, '') IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved', 'archived'
  ) THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_owner := req.owner_id;
  v_round := coalesce(req.marketing_round, 1);

  SELECT COUNT(*) INTO dup
  FROM public.listing_offers o
  WHERE o.request_id = p_request_id
    AND o.marketer_id = uid
    AND coalesce(o.round_no, 1) = v_round
    AND o.status IN ('submitted', 'pending');

  IF dup > 0 THEN
    RAISE EXCEPTION 'duplicate_offer_same_round';
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

  UPDATE public.listing_requests lr
  SET
    status = 'offers_received',
    updated_at = now()
  WHERE lr.id = p_request_id;

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

-- ---------------------------------------------------------------------------
-- relist_property_for_marketing — لا إعادة طرح أثناء الحظر
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.relist_property_for_marketing(
  p_request_id uuid,
  p_allow_previous_marketers_retry boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  prev record;
  v_next_round int;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;
  IF req.owner_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_owner'; END IF;

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  IF NOT (
    coalesce(req.workflow_stage, '') IN ('inactive_72h', 'cancelled', 'terminated')
    OR lower(trim(coalesce(req.status, ''))) IN (
      'inactive_72h', 'cancelled', 'terminated', 'declined', 'rejected'
    )
  ) THEN
    RAISE EXCEPTION 'invalid_stage_for_relist';
  END IF;

  v_next_round := coalesce(req.marketing_round, 1) + 1;

  IF NOT p_allow_previous_marketers_retry THEN
    FOR prev IN
      SELECT DISTINCT marketer_id
      FROM public.listing_offers
      WHERE request_id = p_request_id
        AND status NOT IN ('owner_accepted', 'selected')
    LOOP
      INSERT INTO public.listing_request_marketer_exclusions (
        listing_request_id, marketer_id, round_no, reason, can_retry
      )
      SELECT
        p_request_id, prev.marketer_id, v_next_round, 'relist_non_accepted', false
      WHERE NOT EXISTS (
        SELECT 1 FROM public.listing_request_marketer_exclusions e
        WHERE e.listing_request_id = p_request_id
          AND e.marketer_id = prev.marketer_id
          AND e.round_no = v_next_round
      );
    END LOOP;
  END IF;

  UPDATE public.listing_offers
  SET status = 'cancelled',
      updated_at = now()
  WHERE request_id = p_request_id
    AND status IN ('submitted', 'pending', 'expired');

  UPDATE public.listing_requests
  SET
    workflow_stage = 'waiting_marketers',
    marketing_round = v_next_round,
    relist_count = coalesce(relist_count, 0) + 1,
    allow_previous_marketers_retry = p_allow_previous_marketers_retry,
    selected_offer_id = NULL,
    selected_marketer_id = NULL,
    contract_id = NULL,
    contract_sent_at = NULL,
    contract_signed_at = NULL,
    permit_deadline_at = NULL,
    inactive_72h_at = NULL,
    waiting_marketers_since = now(),
    owner_distinct_marketer_declines = 0,
    status = 'waiting_marketers',
    updated_at = now()
  WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.relist_property_for_marketing(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.relist_property_for_marketing(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- cron_expire_permit_pending_72h — إعادة لفّ التسويق بدل inactive_72h
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_permit_pending_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT
      lr.id,
      lr.owner_id,
      lr.contract_id,
      lr.selected_marketer_id
    FROM public.listing_requests lr
    WHERE coalesce(lr.workflow_stage, '') IN (
        'permit_pending', 'awaiting_permits', 'pending_permits'
      )
      AND lr.permit_deadline_at IS NOT NULL
      AND lr.permit_deadline_at < now()
    FOR UPDATE OF lr SKIP LOCKED
  LOOP
    n := n + 1;

    UPDATE public.listing_offers o
    SET status = 'cancelled',
        updated_at = now()
    WHERE o.request_id = r.id
      AND o.status IN ('submitted', 'pending', 'expired');

    IF r.contract_id IS NOT NULL THEN
      UPDATE public.listing_contracts lc
      SET
        status = 'cancelled'::contract_status,
        cancelled_at = COALESCE(lc.cancelled_at, now()),
        cancelled_reason = COALESCE(
          nullif(trim(lc.cancelled_reason), ''),
          'permit_deadline_expired_72h'
        ),
        updated_at = now()
      WHERE lc.id = r.contract_id
        AND lc.status::text IS DISTINCT FROM 'signed';
    END IF;

    UPDATE public.listing_requests lr
    SET
      workflow_stage = 'waiting_marketers',
      status = 'waiting_marketers',
      marketing_round = coalesce(lr.marketing_round, 1) + 1,
      selected_offer_id = NULL,
      selected_marketer_id = NULL,
      contract_id = NULL,
      contract_sent_at = NULL,
      contract_signed_at = NULL,
      permit_deadline_at = NULL,
      inactive_72h_at = NULL,
      waiting_marketers_since = now(),
      owner_distinct_marketer_declines = 0,
      updated_at = now()
    WHERE lr.id = r.id;

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'permit_deadline_expired',
        'انتهت مهلة التصريح',
        'لم يُكمل المسوّق التصريح في الوقت. عُيد الطلب لمرحلة انتظار مسوّقين جدد.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'contract_id', r.contract_id,
          'deep_route', 'listing_request_status',
          'main_tab', 'my_ads',
          'role', 'owner'
        )
      );
    END IF;

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'permit_deadline_expired',
        'انتهت مهلة التصريح',
        'انتهت مهلة إكمال التصريح لهذا الطلب. عُيد للتسويق مع مسوّقين آخرين.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'deep_route', 'listing_request_status',
          'main_tab', 'my_ads',
          'role', 'marketer'
        )
      );
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_permit_pending_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_permit_pending_72h() TO service_role;

COMMIT;
