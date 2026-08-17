-- =============================================================================
-- Permit Flow RPCs (contract_signed -> permit_pending -> permit_issued -> published)
-- Uses existing table `public.listing_permits` and its `status` enum values.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- A) create_or_update_listing_permit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_or_update_listing_permit(
  p_request_id uuid,
  p_permit_no text,
  p_authority_name text,
  p_license_no text,
  p_notes text DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_marketer_id uuid;
  v_id uuid;
  v_due_at timestamptz;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
  INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  v_marketer_id := req.selected_marketer_id;
  IF v_marketer_id IS NULL THEN
    -- No selected marketer => cannot accept permits.
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  IF uid IS DISTINCT FROM v_marketer_id THEN
    RAISE EXCEPTION 'not_marketer';
  END IF;

  -- Allow create/update only during contracting and permit stage.
  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN ('contract_signed', 'permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_due_at := req.permit_deadline_at;
  IF v_due_at IS NULL THEN
    -- Fallback to 72h window when deadline isn't set yet.
    v_due_at := now() + interval '72 hours';
  END IF;

  SELECT lp.id
  INTO v_id
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = v_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_id IS NULL THEN
    INSERT INTO public.listing_permits (
      request_id,
      status,
      due_at,
      payload,
      submitted_at,
      reviewed_at,
      created_at,
      updated_at,
      marketer_id,
      permit_no,
      authority_name,
      license_no,
      issued_at,
      expires_at,
      notes
    )
    VALUES (
      p_request_id,
      'pending'::permit_status,
      v_due_at,
      coalesce(p_payload, '{}'::jsonb),
      now(),
      NULL,
      now(),
      now(),
      v_marketer_id,
      p_permit_no,
      p_authority_name,
      p_license_no,
      NULL,
      p_expires_at,
      p_notes
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.listing_permits
    SET
      status = 'pending'::permit_status,
      due_at = v_due_at,
      payload = coalesce(p_payload, '{}'::jsonb),
      submitted_at = now(),
      reviewed_at = NULL,
      updated_at = now(),
      permit_no = p_permit_no,
      authority_name = p_authority_name,
      license_no = p_license_no,
      issued_at = NULL,
      expires_at = p_expires_at,
      notes = p_notes
    WHERE id = v_id;
  END IF;

  -- Move request into permit stage (optional/gradual path):
  -- contract_signed -> permit_pending
  IF lower(trim(coalesce(req.workflow_stage, ''))) IN ('contract_signed', 'awaiting_permits', 'pending_permits') THEN
    UPDATE public.listing_requests
    SET
      workflow_stage = 'permit_pending',
      permit_deadline_at = coalesce(permit_deadline_at, v_due_at),
      updated_at = now()
    WHERE id = p_request_id;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_or_update_listing_permit(
  uuid, text, text, text, text, timestamptz, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_or_update_listing_permit(
  uuid, text, text, text, text, timestamptz, jsonb
) TO authenticated;

-- -----------------------------------------------------------------------------
-- B) issue_listing_permit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_listing_permit(
  p_request_id uuid,
  p_permit_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_target_marketer_id uuid;
  v_id uuid;
  v_status public.permit_status;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
  INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF uid IS DISTINCT FROM req.owner_id THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN ('permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_target_marketer_id := req.selected_marketer_id;
  IF v_target_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  IF p_permit_id IS NOT NULL THEN
    SELECT lp.id, lp.status
    INTO v_id, v_status
    FROM public.listing_permits lp
    WHERE lp.id = p_permit_id
      AND lp.request_id = p_request_id
      AND lp.marketer_id = v_target_marketer_id
    FOR UPDATE
    LIMIT 1;
  ELSE
    SELECT lp.id, lp.status
    INTO v_id, v_status
    FROM public.listing_permits lp
    WHERE lp.request_id = p_request_id
      AND lp.marketer_id = v_target_marketer_id
    ORDER BY lp.created_at DESC
    LIMIT 1
    FOR UPDATE;
  END IF;

  IF v_id IS NULL THEN
    RAISE EXCEPTION 'permit_not_found';
  END IF;

  IF v_status NOT IN ('pending'::permit_status, 'submitted'::permit_status) THEN
    RAISE EXCEPTION 'permit_not_pending';
  END IF;

  -- Ensure required permit fields are present.
  IF NOT EXISTS (
    SELECT 1
    FROM public.listing_permits lp
    WHERE lp.id = v_id
      AND coalesce(nullif(trim(lp.permit_no), ''), '') <> ''
      AND coalesce(nullif(trim(lp.authority_name), ''), '') <> ''
      AND coalesce(nullif(trim(lp.license_no), ''), '') <> ''
  ) THEN
    RAISE EXCEPTION 'permit_data_incomplete';
  END IF;

  UPDATE public.listing_permits
  SET
    status = 'approved'::permit_status,
    issued_at = COALESCE(issued_at, now()),
    reviewed_at = now(),
    updated_at = now()
  WHERE id = v_id;

  UPDATE public.listing_requests
  SET
    workflow_stage = 'permit_issued',
    updated_at = now()
  WHERE id = p_request_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_listing_permit(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.issue_listing_permit(uuid, uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- C) publish_property_after_permit
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_property_after_permit(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_contract_id uuid;
  v_permit_status public.permit_status;
  v_issued_at timestamptz;
  v_prop_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
  INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  -- Must be issued by stage or by permit status.
  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN ('permit_issued', 'permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_contract_id := req.contract_id;
  IF v_contract_id IS NULL THEN
    RAISE EXCEPTION 'contract_not_found';
  END IF;

  -- Determine the latest permit status for selected marketer.
  IF req.selected_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  SELECT lp.status, lp.issued_at
  INTO v_permit_status, v_issued_at
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = req.selected_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1;

  IF v_permit_status IS NULL OR v_permit_status <> 'approved'::permit_status THEN
    RAISE EXCEPTION 'permit_not_approved';
  END IF;

  -- Ensure authorization matches `publish_property_from_contract`.
  -- Note: workflow depends on listing_requests.selected_marketer_id.
  IF uid IS DISTINCT FROM req.owner_id AND uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  v_prop_id := public.publish_property_from_contract(v_contract_id);
  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_after_permit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_after_permit(uuid) TO authenticated;

COMMIT;

