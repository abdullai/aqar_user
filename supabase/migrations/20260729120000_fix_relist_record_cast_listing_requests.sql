-- =============================================================================
-- إصلاح: cannot cast type record to listing_requests (42846)
-- السبب: relist_property_for_marketing يعلن req كـ record ثم يمرّره إلى
-- _owner_return_request_eligible(listing_requests) فيفشل التحويل.
-- الحل: %ROWTYPE + فحص أهلية عبر id بدون cast مركّب.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._owner_return_request_eligible_by_id(p_request_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.listing_requests r
    WHERE r.id = p_request_id
      AND (
        r.owner_action_required_at IS NOT NULL
        OR r.inactive_72h_at IS NOT NULL
        OR (
          r.permit_deadline_at IS NOT NULL
          AND r.permit_deadline_at < now()
        )
        OR lower(trim(coalesce(r.workflow_stage, ''))) IN (
          'inactive_72h', 'inactive72h', 'owner_action_required'
        )
        OR lower(trim(coalesce(r.status, ''))) IN (
          'inactive_72h', 'inactive72h', 'owner_action_required'
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public._owner_return_request_eligible(p_req public.listing_requests)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_req.owner_action_required_at IS NOT NULL
    OR p_req.inactive_72h_at IS NOT NULL
    OR (
      p_req.permit_deadline_at IS NOT NULL
      AND p_req.permit_deadline_at < now()
    )
    OR lower(trim(coalesce(p_req.workflow_stage, ''))) IN (
      'inactive_72h', 'inactive72h', 'owner_action_required'
    )
    OR lower(trim(coalesce(p_req.status, ''))) IN (
      'inactive_72h', 'inactive72h', 'owner_action_required'
    );
$$;

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
  req public.listing_requests%ROWTYPE;
  prev record;
  v_next_round int;
  v_stage text;
  v_status text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;
  IF req.owner_id IS DISTINCT FROM uid THEN RAISE EXCEPTION 'not_owner'; END IF;

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  UPDATE public.listing_offers o
  SET status = 'expired',
      updated_at = now()
  WHERE o.request_id = p_request_id
    AND o.expires_at IS NOT NULL
    AND o.expires_at < now()
    AND o.status::text IN ('submitted', 'pending');

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'inactive_72h',
    inactive_72h_at = coalesce(lr.inactive_72h_at, now()),
    updated_at = now()
  WHERE lr.id = p_request_id
    AND coalesce(lr.workflow_stage, '') = 'waiting_marketers'
    AND EXISTS (
      SELECT 1 FROM public.listing_offers o0 WHERE o0.request_id = lr.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.listing_offers o2
      WHERE o2.request_id = lr.id
        AND o2.status::text IN ('submitted', 'pending', 'owner_accepted', 'selected')
    );

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id;

  v_stage := lower(trim(coalesce(req.workflow_stage, '')));
  v_status := lower(trim(coalesce(req.status, '')));

  IF NOT (
    v_stage IN ('inactive_72h', 'inactive72h', 'owner_action_required', 'cancelled', 'terminated')
    OR v_status IN (
      'inactive_72h', 'inactive72h', 'owner_action_required',
      'cancelled', 'terminated', 'declined', 'rejected'
    )
    OR public._owner_return_request_eligible_by_id(p_request_id)
  ) THEN
    RAISE EXCEPTION 'invalid_stage_for_relist';
  END IF;

  v_next_round := coalesce(req.marketing_round, 1) + 1;

  IF NOT p_allow_previous_marketers_retry THEN
    FOR prev IN
      SELECT DISTINCT marketer_id
      FROM public.listing_offers
      WHERE request_id = p_request_id
        AND status::text NOT IN ('owner_accepted', 'selected')
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
    AND status::text IN ('submitted', 'pending', 'expired', 'owner_accepted');

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
    owner_action_required_at = NULL,
    owner_action_reason = NULL,
    waiting_marketers_since = now(),
    owner_distinct_marketer_declines = 0,
    status = 'waiting_marketers',
    updated_at = now()
  WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.relist_property_for_marketing(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.relist_property_for_marketing(uuid, boolean) TO authenticated;

-- تأمين owner_return على نفس فحص الأهلية بدون cast مركّب
CREATE OR REPLACE FUNCTION public.owner_return_request_to_market(
  p_request_id uuid,
  p_allow_same_marketer boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.listing_requests%ROWTYPE;
  v_round int;
  v_reason text;
  v_has_pending boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF v_req.owner_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'not_request_owner';
  END IF;

  IF coalesce(v_req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  IF NOT public._owner_return_request_eligible_by_id(p_request_id) THEN
    RAISE EXCEPTION 'no_owner_action_pending';
  END IF;

  IF v_req.owner_action_required_at IS NULL THEN
    v_reason := coalesce(
      v_req.owner_action_reason,
      CASE
        WHEN v_req.permit_deadline_at IS NOT NULL AND v_req.permit_deadline_at < now()
          THEN 'publish_72h_expired'
        WHEN lower(trim(coalesce(v_req.workflow_stage, ''))) = 'owner_action_required'
          THEN 'owner_action_required'
        WHEN v_req.inactive_72h_at IS NOT NULL
          THEN 'inactive_72h'
        ELSE 'owner_return_backfill'
      END
    );
    UPDATE public.listing_requests
       SET owner_action_required_at = coalesce(
             inactive_72h_at, auto_expired_at, updated_at, now()
           ),
           owner_action_reason = v_reason,
           inactive_72h_at = coalesce(inactive_72h_at, now())
     WHERE id = p_request_id
     RETURNING * INTO v_req;
  END IF;

  v_round := coalesce(v_req.marketing_round, 1) + 1;

  IF v_req.prev_selected_marketer_id IS NULL AND v_req.selected_marketer_id IS NOT NULL THEN
    UPDATE public.listing_requests
       SET prev_selected_marketer_id = v_req.selected_marketer_id
     WHERE id = p_request_id
     RETURNING * INTO v_req;
  END IF;

  IF v_req.prev_selected_marketer_id IS NOT NULL
     AND NOT coalesce(p_allow_same_marketer, false) THEN
    INSERT INTO public.listing_request_marketer_exclusions (
      listing_request_id, marketer_id, round_no, reason, can_retry
    )
    VALUES (
      p_request_id, v_req.prev_selected_marketer_id, v_round,
      coalesce(v_req.owner_action_reason, 'owner_excluded'), false
    )
    ON CONFLICT (listing_request_id, marketer_id, round_no) DO NOTHING;
  END IF;

  UPDATE public.listing_requests
     SET workflow_stage = 'waiting_marketers',
         status = 'waiting_marketers',
         marketing_round = v_round,
         relist_count = coalesce(relist_count, 0) + 1,
         waiting_marketers_since = now(),
         owner_action_required_at = NULL,
         owner_action_reason = NULL,
         inactive_72h_at = NULL,
         auto_expired_at = NULL,
         contract_started_at = NULL,
         contract_sent_at = NULL,
         contract_signed_at = NULL,
         contract_deadline_at = NULL,
         permit_deadline_at = NULL,
         selected_offer_id = NULL,
         selected_marketer_id = NULL,
         allow_previous_marketers_retry = coalesce(p_allow_same_marketer, false),
         updated_at = now()
   WHERE id = p_request_id;

  UPDATE public.listing_offers
     SET status = 'withdrawn',
         lost_at = coalesce(lost_at, now()),
         lost_reason = coalesce(nullif(trim(lost_reason), ''), 'returned_to_market'),
         updated_at = now()
   WHERE request_id = p_request_id
     AND (
       marketer_id = v_req.prev_selected_marketer_id
       OR lower(status::text) IN ('owner_accepted', 'selected')
     )
     AND lower(status::text) NOT IN ('withdrawn', 'cancelled');

  UPDATE public.listing_offers o
     SET status = 'submitted',
         round_no = v_round,
         lost_at = NULL,
         lost_reason = NULL,
         updated_at = now()
   WHERE o.request_id = p_request_id
     AND (
       p_allow_same_marketer
       OR o.marketer_id IS DISTINCT FROM v_req.prev_selected_marketer_id
     )
     AND lower(o.status::text) IN ('submitted', 'pending', 'expired', 'withdrawn')
     AND NOT EXISTS (
       SELECT 1
       FROM public.listing_request_marketer_exclusions ex
       WHERE ex.listing_request_id = p_request_id
         AND ex.marketer_id = o.marketer_id
         AND ex.round_no = v_round
     );

  SELECT EXISTS (
    SELECT 1
    FROM public.listing_offers lo
    WHERE lo.request_id = p_request_id
      AND lo.round_no = v_round
      AND lower(lo.status::text) IN ('submitted', 'pending')
  ) INTO v_has_pending;

  IF v_has_pending THEN
    UPDATE public.listing_requests
       SET status = 'offers_received'
     WHERE id = p_request_id;
  END IF;

  IF to_regclass('public.listing_request_invites') IS NOT NULL THEN
    UPDATE public.listing_request_invites inv
       SET status = 'pending',
           round_no = v_round,
           updated_at = now()
     WHERE inv.request_id = p_request_id
       AND (
         p_allow_same_marketer
         OR inv.marketer_id IS DISTINCT FROM v_req.prev_selected_marketer_id
       )
       AND NOT EXISTS (
         SELECT 1
         FROM public.listing_request_marketer_exclusions ex
         WHERE ex.listing_request_id = p_request_id
           AND ex.marketer_id = inv.marketer_id
           AND ex.round_no = v_round
       );
  END IF;

  IF v_req.preview_property_id IS NOT NULL THEN
    UPDATE public.properties p
       SET workflow_stage = 'waiting_marketers',
           status = 'draft',
           selected_marketer_id = NULL,
           published_by_marketer_id = NULL,
           published_at = NULL,
           inactive_72h_at = NULL,
           updated_at = now()
     WHERE p.id = v_req.preview_property_id
       AND p.owner_id = v_uid;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'round_no', v_round,
    'has_pending_offers', v_has_pending,
    'allow_same_marketer', coalesce(p_allow_same_marketer, false),
    'excluded_marketer_id',
      CASE WHEN p_allow_same_marketer THEN NULL ELSE v_req.prev_selected_marketer_id END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_return_request_to_market(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_return_request_to_market(uuid, boolean)
  TO authenticated, service_role;

COMMIT;
