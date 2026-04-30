-- =============================================================================
-- REGA / lifecycle extensions: sold completion, manual review flags, return bump
-- Idempotent ADD COLUMN + RPCs. Apply after core property/listing migrations.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) properties — sale audit (re-list requires new listing row in app policy)
-- ---------------------------------------------------------------------------
ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS sold_at timestamptz,
  ADD COLUMN IF NOT EXISTS sold_to_user_id uuid;

COMMENT ON COLUMN public.properties.sold_at IS 'When listing was marked sold (complete_property_sale).';
COMMENT ON COLUMN public.properties.sold_to_user_id IS 'Buyer (reservation holder) at time of sale.';

CREATE INDEX IF NOT EXISTS idx_properties_sold_at ON public.properties (sold_at)
  WHERE sold_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- B) listing_requests — count owner returns for manual review escalation
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS contract_return_bump integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS needs_manual_review boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.listing_requests.contract_return_bump IS
  'Increments when owner returns contract to marketer (owner_return_listing_contract).';
COMMENT ON COLUMN public.listing_requests.needs_manual_review IS
  'Set true when contract_return_bump reaches threshold (e.g. 3).';

-- ---------------------------------------------------------------------------
-- C) owner_return_listing_contract — bump + flag (replaces prior body)
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
  v_next_bump int;
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
    contract_return_bump = COALESCE(lr.contract_return_bump, 0) + 1,
    needs_manual_review = (COALESCE(lr.contract_return_bump, 0) + 1) >= 3,
    updated_at = now()
  WHERE lr.id = c.request_id
  RETURNING lr.contract_return_bump INTO v_next_bump;

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
        'reason', v_reason,
        'contract_return_bump', v_next_bump,
        'needs_manual_review', COALESCE(v_next_bump, 0) >= 3
      )
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.owner_return_listing_contract(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_return_listing_contract(uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- D) complete_property_sale — reserved listing → sold (buyer / owner / broker)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_property_sale(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  r record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prop FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  SELECT * INTO r
  FROM public.reservations
  WHERE property_id = p_property_id
    AND status IN ('pending', 'paid')
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_active_reservation';
  END IF;

  IF NOT (
    uid = r.user_id
    OR uid = prop.owner_id
    OR (prop.published_by_marketer_id IS NOT NULL AND uid = prop.published_by_marketer_id)
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF lower(trim(coalesce(prop.workflow_stage, ''))) IS DISTINCT FROM 'reserved' THEN
    RAISE EXCEPTION 'property_not_reserved';
  END IF;

  UPDATE public.properties p
  SET
    status = 'sold',
    workflow_stage = 'archived',
    sold_at = now(),
    sold_to_user_id = r.user_id,
    reservation_expires_at = NULL,
    updated_at = now()
  WHERE p.id = p_property_id;

  UPDATE public.reservations
  SET status = 'paid', updated_at = now()
  WHERE id = r.id;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE property_id = p_property_id
    AND id IS DISTINCT FROM r.id
    AND status IN ('pending', 'paid');

  PERFORM public.workflow_create_notification(
    prop.owner_id,
    'property_sale_completed',
    'تم إتمام البيع',
    'تم تسجيل إتمام البيع على إعلانك.',
    'property',
    p_property_id,
    jsonb_build_object('property_id', p_property_id, 'reservation_id', r.id)
  );

  IF prop.published_by_marketer_id IS NOT NULL
     AND prop.published_by_marketer_id IS DISTINCT FROM prop.owner_id THEN
    PERFORM public.workflow_create_notification(
      prop.published_by_marketer_id,
      'property_sale_completed',
      'تم إتمام البيع',
      'تم تسجيل إتمام البيع لإعلان منشور من جهتك.',
      'property',
      p_property_id,
      jsonb_build_object('property_id', p_property_id, 'reservation_id', r.id)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_property_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;

COMMIT;
