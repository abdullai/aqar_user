-- =============================================================================
-- 2026-06-03 v12.1 — السماح لـ cron النظامي بتعديل allow_previous_marketers_retry
-- =============================================================================
-- SQL Editor يعمل غالباً بدور postgres بدون JWT service_role، فيرفض
-- listing_requests_guard_allow_retry_edit التحديث من cron_expire_pending_offers_72h.
-- الحل: علم جلسة يُضبط داخل دوال SECURITY DEFINER للنظام.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.listing_requests_guard_allow_retry_edit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  jr text := coalesce(lower(trim(auth.jwt() ->> 'role')), '');
BEGIN
  IF NEW.allow_previous_marketers_retry IS DISTINCT FROM
      OLD.allow_previous_marketers_retry THEN
    IF current_setting('aqar.system_listing_request_update', true) = '1' THEN
      RETURN NEW;
    END IF;
    IF jr = 'service_role' THEN
      RETURN NEW;
    END IF;
    IF auth.uid() IS NULL OR auth.uid() <> OLD.owner_id THEN
      RAISE EXCEPTION
        USING ERRCODE = '42501',
          MESSAGE = 'allow_previous_marketers_retry may only be changed by the listing owner';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cron_expire_pending_offers_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
BEGIN
  PERFORM set_config('aqar.system_listing_request_update', '1', true);

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

  PERFORM set_config('aqar.system_listing_request_update', '', true);

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_pending_offers_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_pending_offers_72h() TO service_role;

COMMIT;
