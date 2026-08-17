-- Contract verify QR token + operational auto_terminate_expired_permit_contracts
-- permit_attempts: generic counter (can be incremented from app); rega_mismatch_attempts also triggers.

BEGIN;

-- ---------------------------------------------------------------------------
-- A) listing_contracts.verify_public_token — opaque high-entropy token for QR
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_contracts
  ADD COLUMN IF NOT EXISTS verify_public_token uuid;

UPDATE public.listing_contracts c
SET verify_public_token = gen_random_uuid()
WHERE c.verify_public_token IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS listing_contracts_verify_public_token_uidx
  ON public.listing_contracts (verify_public_token);

CREATE OR REPLACE FUNCTION public.trg_listing_contracts_biu_verify_token()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.verify_public_token IS NULL THEN
    NEW.verify_public_token := gen_random_uuid();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS listing_contracts_biu_verify_token ON public.listing_contracts;
CREATE TRIGGER listing_contracts_biu_verify_token
  BEFORE INSERT OR UPDATE OF verify_public_token
  ON public.listing_contracts
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_listing_contracts_biu_verify_token();

-- ---------------------------------------------------------------------------
-- B) listing_requests.permit_attempts — alongside rega_mismatch_attempts
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS permit_attempts integer NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- C) RPC: assert_listing_contract_verify_token
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_listing_contract_verify_token(
  p_contract_id uuid,
  p_token uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.listing_contracts c
    WHERE c.id = p_contract_id
      AND c.verify_public_token IS NOT DISTINCT FROM p_token
  );
$$;

REVOKE ALL ON FUNCTION public.assert_listing_contract_verify_token(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_listing_contract_verify_token(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- D) auto_terminate_expired_permit_contracts — 72h deadline OR 3 attempts
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auto_terminate_expired_permit_contracts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
  v_title text := 'تنبيه — التصريح';
  v_body text :=
    'المسوق لم يكمل الإجراءات في الوقت المحدد، تم إعادة الإعلان للسوق.';
  v_body_no_retry text :=
    'المسوق لم يكمل الإجراءات في الوقت المحدد. رُفع الطلب إلى «لم يتخذ إجراء 72 ساعة» للمراجعة.';
BEGIN
  FOR r IN
    SELECT lr.*
    FROM public.listing_requests lr
    WHERE coalesce(lower(trim(lr.workflow_stage)), '') IN (
        'permit_pending',
        'awaiting_permits',
        'pending_permits'
      )
      AND lr.banned_under_review IS NOT TRUE
      AND (
        (lr.permit_deadline_at IS NOT NULL AND lr.permit_deadline_at < now())
        OR coalesce(lr.rega_mismatch_attempts, 0) >= 3
        OR coalesce(lr.permit_attempts, 0) >= 3
      )
    FOR UPDATE OF lr SKIP LOCKED
  LOOP
    n := n + 1;

    IF r.contract_id IS NOT NULL THEN
      UPDATE public.listing_contracts lc
      SET
        status = 'cancelled'::contract_status,
        cancelled_at = coalesce(lc.cancelled_at, now()),
        cancelled_reason = coalesce(
          nullif(trim(lc.cancelled_reason), ''),
          'auto_terminate_permit_deadline_or_attempts'
        ),
        updated_at = now()
      WHERE lc.id = r.contract_id
        AND lc.status::text IS DISTINCT FROM 'signed';
    END IF;

    IF coalesce(r.allow_previous_marketers_retry, false) THEN
      UPDATE public.listing_requests lr2
      SET
        workflow_stage = 'waiting_marketers',
        contract_id = NULL,
        selected_offer_id = NULL,
        selected_marketer_id = NULL,
        permit_deadline_at = NULL,
        rega_mismatch_attempts = 0,
        permit_attempts = 0,
        inactive_72h_at = NULL,
        updated_at = now()
      WHERE lr2.id = r.id;
    ELSE
      UPDATE public.listing_requests lr2
      SET
        workflow_stage = 'inactive_72h',
        inactive_72h_at = coalesce(lr2.inactive_72h_at, now()),
        permit_deadline_at = NULL,
        rega_mismatch_attempts = 0,
        permit_attempts = 0,
        updated_at = now()
      WHERE lr2.id = r.id;
    END IF;

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'permit_auto_terminated',
        v_title,
        CASE
          WHEN coalesce(r.allow_previous_marketers_retry, false) THEN v_body
          ELSE v_body_no_retry
        END,
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'contract_id', r.contract_id,
          'main_tab', 'my_ads',
          'my_ads_sub_tab', '0',
          'deep_route', 'listing_request_status'
        )
      );
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'processed_requests', n,
    'version', 2
  );
END;
$$;

REVOKE ALL ON FUNCTION public.auto_terminate_expired_permit_contracts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auto_terminate_expired_permit_contracts() TO service_role;

COMMIT;
