-- RLS hardening: allow_previous_marketers_retry editable by listing owner only
-- (service_role / Edge Functions bypass via JWT role check).
-- Note: SECURITY DEFINER RPCs such as auto_terminate_expired_permit_contracts
--       run with elevated privileges; this trigger still sees auth.jwt() from
--       the invoker — service_role JWT is exempt below.

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

DROP TRIGGER IF EXISTS tr_listing_requests_guard_allow_retry
  ON public.listing_requests;
CREATE TRIGGER tr_listing_requests_guard_allow_retry
  BEFORE UPDATE OF allow_previous_marketers_retry
  ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.listing_requests_guard_allow_retry_edit();

COMMENT ON FUNCTION public.listing_requests_guard_allow_retry_edit() IS
  'يمنع تعديل allow_previous_marketers_retry إلا من مالك الطلب (أو service_role).';

COMMIT;
