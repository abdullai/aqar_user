BEGIN;

CREATE OR REPLACE FUNCTION public.cron_expire_pending_offers_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
BEGIN
  UPDATE public.listing_offers
  SET status = 'expired',
      updated_at = now()
  WHERE expires_at IS NOT NULL
    AND expires_at < now()
    AND status IN ('submitted', 'pending');
  GET DIAGNOSTICS n = ROW_COUNT;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'waiting_marketers',
    status = CASE
      WHEN coalesce(lr.status, '') IN ('published', 'live', 'reserved', 'sold', 'closed')
        THEN lr.status
      ELSE 'active'
    END,
    marketing_round = coalesce(lr.marketing_round, 1) + 1,
    allow_previous_marketers_retry = true,
    waiting_marketers_since = now(),
    inactive_72h_at = NULL,
    updated_at = now()
  WHERE coalesce(lr.workflow_stage, '') = 'waiting_marketers'
    AND coalesce(lr.status, '') NOT IN ('published', 'live', 'reserved', 'sold', 'closed')
    AND EXISTS (
      SELECT 1 FROM public.listing_offers o
      WHERE o.request_id = lr.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.listing_offers o2
      WHERE o2.request_id = lr.id
        AND o2.status IN ('submitted', 'pending', 'owner_accepted', 'selected')
    );

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_pending_offers_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_pending_offers_72h() TO service_role;

COMMIT;
