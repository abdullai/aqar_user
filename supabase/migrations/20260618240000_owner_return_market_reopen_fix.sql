-- =============================================================================
-- إصلاح إعادة الطلب للسوق: مسح حالة النشر، إعادة فتح عروض المسوّقين الآخرين،
-- وتحديث الدعوات للجولة الجديدة.
-- =============================================================================

BEGIN;

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

  IF NOT public._owner_return_request_eligible(v_req) THEN
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

  -- سحب عروض المسوّق المختار سابقاً والعروض المقبولة فقط
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

  -- إعادة فتح عروض المسوّقين الآخرين للجولة الجديدة
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

  -- إعادة ضبط دعوات المسوّقين للجولة الجديدة (ما عدا المستبعدين)
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
