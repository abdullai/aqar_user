-- =============================================================================
-- Request-centric workflow extensions (pre-publish: listing_requests)
-- Post-publish mirror on properties only where needed.
-- Idempotent / additive. Review triggers & RLS in your project before apply.
-- =============================================================================
-- Corrective: remove artifacts from an earlier property-centric draft if applied.
-- =============================================================================

BEGIN;

DROP TABLE IF EXISTS public.workflow_conversation_messages CASCADE;
DROP TABLE IF EXISTS public.workflow_conversations CASCADE;
DROP TABLE IF EXISTS public.permit_records CASCADE;

DROP TABLE IF EXISTS public.property_marketer_exclusions CASCADE;

DROP INDEX IF EXISTS public.ux_listing_offers_prop_marketer_round;
DROP INDEX IF EXISTS public.idx_listing_offers_property;

ALTER TABLE public.listing_offers
  DROP COLUMN IF EXISTS property_id;

ALTER TABLE public.listing_contracts
  DROP COLUMN IF EXISTS property_id;

-- ---------------------------------------------------------------------------
-- A) listing_requests — primary workflow before publish
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS workflow_stage text,
  ADD COLUMN IF NOT EXISTS marketing_round integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS relist_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS selected_offer_id uuid,
  ADD COLUMN IF NOT EXISTS selected_marketer_id uuid,
  ADD COLUMN IF NOT EXISTS allow_previous_marketers_retry boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS waiting_marketers_since timestamptz,
  ADD COLUMN IF NOT EXISTS contract_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS contract_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS contract_signed_at timestamptz,
  ADD COLUMN IF NOT EXISTS permit_deadline_at timestamptz,
  ADD COLUMN IF NOT EXISTS inactive_72h_at timestamptz;

COMMENT ON COLUMN public.listing_requests.workflow_stage IS
  'Preferred stage before publish; keep status for legacy UI/RPC.';

CREATE INDEX IF NOT EXISTS idx_listing_requests_workflow_stage
  ON public.listing_requests (workflow_stage);
CREATE INDEX IF NOT EXISTS idx_listing_requests_owner_workflow
  ON public.listing_requests (owner_id, workflow_stage);

-- Backfill from status when workflow_stage empty (non-destructive)
UPDATE public.listing_requests lr
SET workflow_stage = CASE
  WHEN lower(trim(coalesce(lr.status, ''))) IN ('published', 'active', 'approved', 'live')
    THEN 'published'
  WHEN lower(trim(coalesce(lr.status, ''))) IN ('offers_received', 'new', 'invited', 'pending')
    THEN 'waiting_marketers'
  WHEN lower(trim(coalesce(lr.status, ''))) IN ('assigned')
    THEN 'marketer_selected'
  WHEN lower(trim(coalesce(lr.status, ''))) IN ('contract', 'pending_owner', 'await_contract', 'awaiting_contract')
    THEN 'contract_sent'
  WHEN lower(trim(coalesce(lr.status, ''))) IN ('signed', 'contract_signed')
    THEN 'contract_signed'
  WHEN lower(trim(coalesce(lr.status, ''))) IN (
    'awaiting_permits', 'pending_permits', 'permit_submitted', 'permits_submitted', 'submitted'
  ) THEN 'permit_pending'
  ELSE coalesce(nullif(trim(lr.workflow_stage), ''), 'waiting_marketers')
END
WHERE lr.workflow_stage IS NULL OR trim(lr.workflow_stage) = '';

UPDATE public.listing_requests
SET waiting_marketers_since = coalesce(waiting_marketers_since, created_at)
WHERE coalesce(workflow_stage, '') = 'waiting_marketers'
  AND waiting_marketers_since IS NULL;

-- ---------------------------------------------------------------------------
-- B) listing_offers — additive only (request_id remains primary link)
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_offers
  ADD COLUMN IF NOT EXISTS marketer_type text,
  ADD COLUMN IF NOT EXISTS round_no integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS offer_amount numeric,
  ADD COLUMN IF NOT EXISTS commission_type text,
  ADD COLUMN IF NOT EXISTS commission_value numeric,
  ADD COLUMN IF NOT EXISTS duration_days integer,
  ADD COLUMN IF NOT EXISTS owner_response text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

UPDATE public.listing_offers o
SET offer_amount = o.price
WHERE o.offer_amount IS NULL AND o.price IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_listing_offers_request ON public.listing_offers (request_id);
CREATE INDEX IF NOT EXISTS idx_listing_offers_expires ON public.listing_offers (expires_at)
  WHERE expires_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- C) listing_contracts — extend (no property_id)
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_contracts
  ADD COLUMN IF NOT EXISTS offer_id uuid,
  ADD COLUMN IF NOT EXISTS round_no integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS contract_html text,
  ADD COLUMN IF NOT EXISTS contract_text text,
  ADD COLUMN IF NOT EXISTS contract_pdf_url text,
  ADD COLUMN IF NOT EXISTS marketer_seal_url text,
  ADD COLUMN IF NOT EXISTS sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS returned_at timestamptz,
  ADD COLUMN IF NOT EXISTS returned_reason text,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_reason text,
  ADD COLUMN IF NOT EXISTS terminated_at timestamptz,
  ADD COLUMN IF NOT EXISTS terminated_reason text,
  ADD COLUMN IF NOT EXISTS extra_margin_notes text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Backfill contract_text from legacy column name only if it exists (schemas vary).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'listing_contracts'
      AND column_name = 'contract_body'
  ) THEN
    EXECUTE $q$
      UPDATE public.listing_contracts
      SET contract_text = contract_body
      WHERE contract_text IS NULL AND contract_body IS NOT NULL
    $q$;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'listing_contracts_offer_id_fkey'
  ) THEN
    ALTER TABLE public.listing_contracts
      ADD CONSTRAINT listing_contracts_offer_id_fkey
      FOREIGN KEY (offer_id) REFERENCES public.listing_offers(id) ON DELETE SET NULL;
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- D) listing_permits — light extensions (skip if table missing)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'listing_permits'
  ) THEN
    ALTER TABLE public.listing_permits
      ADD COLUMN IF NOT EXISTS permit_no text,
      ADD COLUMN IF NOT EXISTS authority_name text,
      ADD COLUMN IF NOT EXISTS license_no text,
      ADD COLUMN IF NOT EXISTS issued_at timestamptz,
      ADD COLUMN IF NOT EXISTS expires_at timestamptz,
      ADD COLUMN IF NOT EXISTS notes text,
      ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- E) properties — mirror after publish (nullable workflow_stage)
-- ---------------------------------------------------------------------------
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS workflow_stage text,
  ADD COLUMN IF NOT EXISTS published_by_marketer_id uuid,
  ADD COLUMN IF NOT EXISTS reservation_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS inactive_72h_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_properties_workflow_stage_pub
  ON public.properties (workflow_stage)
  WHERE workflow_stage IS NOT NULL;

UPDATE public.properties p
SET workflow_stage = CASE
  WHEN lower(trim(coalesce(p.status, ''))) IN ('published', 'active', 'approved', 'live', 'available')
    THEN 'published'
  WHEN lower(trim(coalesce(p.status, ''))) IN ('reserved') THEN 'reserved'
  ELSE p.workflow_stage
END
WHERE p.workflow_stage IS NULL
  AND lower(trim(coalesce(p.status, ''))) IN ('published', 'active', 'approved', 'live', 'available', 'reserved');

-- ---------------------------------------------------------------------------
-- listing_request_marketer_exclusions (optional relist)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.listing_request_marketer_exclusions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_request_id uuid NOT NULL REFERENCES public.listing_requests(id) ON DELETE CASCADE,
  marketer_id uuid NOT NULL,
  round_no integer NOT NULL,
  reason text,
  can_retry boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_lrme_request_marketer_round
  ON public.listing_request_marketer_exclusions (listing_request_id, marketer_id, round_no);

CREATE INDEX IF NOT EXISTS idx_lrme_request ON public.listing_request_marketer_exclusions (listing_request_id);

-- ---------------------------------------------------------------------------
-- Notification helper (in_app_notifications — adjust columns if yours differ)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.workflow_create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text,
  p_entity_type text DEFAULT NULL,
  p_entity_id uuid DEFAULT NULL,
  p_data jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.in_app_notifications (
    user_id, type, title, body, message, is_read, entity_type, entity_id, data, created_at
  ) VALUES (
    p_user_id,
    p_type,
    p_title,
    p_body,
    p_body,
    false,
    p_entity_type,
    p_entity_id,
    coalesce(p_data, '{}'::jsonb),
    now()
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.workflow_create_notification(uuid, text, text, text, text, uuid, jsonb) TO service_role;

-- ---------------------------------------------------------------------------
-- RPC: submit_listing_offer (request-centric)
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

  IF coalesce(req.workflow_stage, '') IN (
    'marketer_selected', 'contract_pending', 'contract_sent', 'contract_returned',
    'contract_signed', 'contract_cancelled', 'cancelled', 'terminated',
    'permit_pending', 'permit_issued', 'published', 'reserved'
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

  PERFORM public.workflow_create_notification(
    v_owner,
    'offer_received',
    'وصلك عرض تسويق جديد',
    'راجع العروض في صفحتي واختر الأنسب.',
    'listing_request',
    p_request_id,
    jsonb_build_object('request_id', p_request_id, 'offer_id', v_id)
  );

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_listing_offer(uuid, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_listing_offer(uuid, numeric, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: accept_listing_offer (does not replace owner_select_offer / contract seal)
-- ---------------------------------------------------------------------------
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

  UPDATE public.listing_offers
  SET status = 'owner_accepted',
      owner_responded_at = now(),
      updated_at = now()
  WHERE id = p_offer_id;

  UPDATE public.listing_offers
  SET status = 'owner_rejected',
      updated_at = now()
  WHERE request_id = off.request_id
    AND coalesce(round_no, 1) = v_round
    AND id <> p_offer_id
    AND status IN ('submitted', 'pending');

  UPDATE public.listing_requests
  SET
    selected_offer_id = p_offer_id,
    selected_marketer_id = off.marketer_id,
    workflow_stage = 'marketer_selected',
    contract_started_at = coalesce(req.contract_started_at, now()),
    updated_at = now()
  WHERE id = off.request_id;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    'offer_accepted',
    'تم قبول عرضك',
    'يمكنك متابعة التعاقد من إدارتي.',
    'listing_request',
    off.request_id,
    jsonb_build_object('request_id', off.request_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.accept_listing_offer(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_listing_offer(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: relist_property_for_marketing — operates on listing_requests (name kept for app compat)
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
    updated_at = now()
  WHERE id = p_request_id;
END;
$$;

REVOKE ALL ON FUNCTION public.relist_property_for_marketing(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.relist_property_for_marketing(uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- Cron helpers (service_role)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_pending_offers_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
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
    workflow_stage = 'inactive_72h',
    inactive_72h_at = now(),
    updated_at = now()
  WHERE coalesce(lr.workflow_stage, '') = 'waiting_marketers'
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

CREATE OR REPLACE FUNCTION public.cron_expire_permit_pending_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int;
BEGIN
  WITH moved AS (
    UPDATE public.listing_requests lr
    SET
      workflow_stage = 'inactive_72h',
      inactive_72h_at = now(),
      updated_at = now()
    WHERE coalesce(lr.workflow_stage, '') IN ('permit_pending', 'awaiting_permits', 'pending_permits')
      AND lr.permit_deadline_at IS NOT NULL
      AND lr.permit_deadline_at < now()
    RETURNING lr.id
  )
  SELECT COUNT(*)::int INTO n FROM moved;

  RETURN coalesce(n, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_permit_pending_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_permit_pending_72h() TO service_role;

COMMIT;

-- RLS: do not change here — extend in dashboard when ready.
-- pg_cron example:
-- SELECT cron.schedule('expire_offers', '*/15 * * * *', $$SELECT public.cron_expire_pending_offers_72h()$$);
