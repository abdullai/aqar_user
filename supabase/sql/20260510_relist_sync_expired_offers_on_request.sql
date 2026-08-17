-- =============================================================================
-- إعادة طرح التسويق: قبل التحقق من مرحلة الطلب، تُحدَّث عروض هذا الطلب
-- المنتهية بـ expires_at إلى expired وتُضبط listing_requests إلى inactive_72h
-- عند عدم بقاء عروض قابلة للإجراء — كما في cron_expire_pending_offers_72h().
-- يحلّ تعذّر «إعادة التسويق» عندما لم يُشغَّل pg_cron على المشروع.
-- =============================================================================

BEGIN;

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

  UPDATE public.listing_offers o
  SET status = 'expired',
      updated_at = now()
  WHERE o.request_id = p_request_id
    AND o.expires_at IS NOT NULL
    AND o.expires_at < now()
    AND o.status IN ('submitted', 'pending');

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
        AND o2.status IN ('submitted', 'pending', 'owner_accepted', 'selected')
    );

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id;

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

COMMIT;
