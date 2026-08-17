-- =============================================================================
-- Listing contract workflow RPCs (contract_status enum: draft, pending_owner,
-- pending_marketer, signed, cancelled). workflow_stage on listing_requests
-- stays separate (contract_sent, contract_returned, contract_signed, …).
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) send_listing_contract_to_owner
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_listing_contract_to_owner(p_contract_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  req record;
  v_owner uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = c.request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;

  IF c.offer_id IS NULL OR req.selected_offer_id IS DISTINCT FROM c.offer_id THEN
    RAISE EXCEPTION 'contract_offer_mismatch';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.listing_contracts x
    WHERE x.request_id = c.request_id
      AND x.id IS DISTINCT FROM c.id
      AND x.status::text = 'pending_owner'
  ) THEN
    RAISE EXCEPTION 'duplicate_pending_owner_contract';
  END IF;

  IF c.marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_marketer';
  END IF;

  IF c.status::text NOT IN ('draft', 'pending_marketer') THEN
    RAISE EXCEPTION 'contract_cannot_send';
  END IF;

  v_owner := c.owner_id;

  UPDATE public.listing_contracts
  SET
    status = 'pending_owner'::contract_status,
    sent_at = now(),
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_sent',
    contract_sent_at = now(),
    updated_at = now()
  WHERE lr.id = c.request_id;

  PERFORM public.workflow_create_notification(
    v_owner,
    'contract_sent_to_owner',
    'عقد التسويق للمراجعة',
    'أرسل المسوق عقد التسويق. راجع المحتوى ويمكنك التوقيع أو إعادة العقد مع سبب.',
    'listing_contract',
    p_contract_id,
    jsonb_build_object('request_id', c.request_id, 'contract_id', p_contract_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.send_listing_contract_to_owner(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_listing_contract_to_owner(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- B) owner_return_listing_contract
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_return_listing_contract(
  p_contract_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  v_mk uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  IF c.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF c.status::text IS DISTINCT FROM 'pending_owner' THEN
    RAISE EXCEPTION 'contract_not_pending_owner';
  END IF;

  v_mk := c.marketer_id;

  UPDATE public.listing_contracts
  SET
    status = 'pending_marketer'::contract_status,
    returned_at = now(),
    returned_reason = coalesce(v_reason, returned_reason),
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_returned',
    updated_at = now()
  WHERE lr.id = c.request_id;

  IF v_mk IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      v_mk,
      'contract_returned_by_owner',
      'أعاد المالك العقد للتعديل',
      coalesce(
        'أعاد المالك العقد للمراجعة. السبب: ' || v_reason,
        'أعاد المالك العقد للمراجعة والتعديل.'
      ),
      'listing_contract',
      p_contract_id,
      jsonb_build_object(
        'request_id', c.request_id,
        'contract_id', p_contract_id,
        'reason', v_reason
      )
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_return_listing_contract(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_return_listing_contract(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- C) owner_sign_listing_contract
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_sign_listing_contract(p_contract_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  req record;
  v_mk uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = c.request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;

  IF c.offer_id IS NULL OR req.selected_offer_id IS DISTINCT FROM c.offer_id THEN
    RAISE EXCEPTION 'contract_offer_mismatch';
  END IF;

  IF c.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF c.status::text IS DISTINCT FROM 'pending_owner' THEN
    RAISE EXCEPTION 'contract_not_pending_owner';
  END IF;

  v_mk := c.marketer_id;

  UPDATE public.listing_contracts
  SET
    owner_signed_at = now(),
    status = 'signed'::contract_status,
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_signed',
    contract_signed_at = now(),
    updated_at = now()
  WHERE lr.id = c.request_id;

  IF v_mk IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      v_mk,
      'contract_signed_by_owner',
      'وقع المالك العقد',
      'وقع المالك عقد التسويق. يمكنك متابعة الخطوات التالية من إدارتي.',
      'listing_contract',
      p_contract_id,
      jsonb_build_object('request_id', c.request_id, 'contract_id', p_contract_id)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_sign_listing_contract(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_sign_listing_contract(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- D) cancel_listing_contract
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_listing_contract(
  p_contract_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  c record;
  v_other uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = p_contract_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contract_not_found'; END IF;

  IF c.owner_id IS DISTINCT FROM uid AND c.marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF c.status::text = 'signed' THEN
    RAISE EXCEPTION 'contract_already_signed';
  END IF;

  IF c.status::text = 'cancelled' THEN
    RETURN;
  END IF;

  v_other := CASE
    WHEN c.owner_id = uid THEN c.marketer_id
    ELSE c.owner_id
  END;

  UPDATE public.listing_contracts
  SET
    status = 'cancelled'::contract_status,
    cancelled_at = now(),
    cancelled_reason = coalesce(v_reason, cancelled_reason),
    updated_at = now()
  WHERE id = p_contract_id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_cancelled',
    updated_at = now()
  WHERE lr.id = c.request_id;

  IF v_other IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      v_other,
      'contract_cancelled',
      'تم إلغاء عقد التسويق',
      coalesce('سبب الإلغاء: ' || v_reason, 'تم إلغاء عقد التسويق.'),
      'listing_contract',
      p_contract_id,
      jsonb_build_object(
        'request_id', c.request_id,
        'contract_id', p_contract_id,
        'reason', v_reason
      )
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_listing_contract(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_listing_contract(uuid, text) TO authenticated;

COMMIT;
