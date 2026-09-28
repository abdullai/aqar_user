BEGIN;

CREATE TABLE IF NOT EXISTS public.listing_request_market_return_acks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.listing_requests (id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  acknowledged_at timestamptz NOT NULL DEFAULT now(),
  prior_workflow_stage text,
  prior_owner_action_reason text,
  prior_permit_deadline_at timestamptz,
  next_round integer NOT NULL,
  allow_same_marketer boolean NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_listing_request_return_acks_owner
  ON public.listing_request_market_return_acks
    (owner_id, acknowledged_at DESC);
CREATE INDEX IF NOT EXISTS idx_listing_request_return_acks_request
  ON public.listing_request_market_return_acks
    (request_id, acknowledged_at DESC);

ALTER TABLE public.listing_request_market_return_acks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS listing_request_market_return_acks_select_participants
  ON public.listing_request_market_return_acks;
CREATE POLICY listing_request_market_return_acks_select_participants
  ON public.listing_request_market_return_acks
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR public.is_platform_staff());

REVOKE INSERT, UPDATE, DELETE
  ON public.listing_request_market_return_acks
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.listing_request_market_return_acks TO authenticated;

CREATE OR REPLACE FUNCTION public.owner_return_request_to_market_with_ack(
  p_request_id uuid,
  p_allow_same_marketer boolean DEFAULT false,
  p_legal_acknowledged boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
  req public.listing_requests%ROWTYPE;
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_legal_acknowledged IS NOT TRUE THEN
    RAISE EXCEPTION 'owner_legal_ack_required';
  END IF;

  SELECT * INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;
  IF req.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_request_owner';
  END IF;

  result := public.owner_return_request_to_market(
    p_request_id,
    coalesce(p_allow_same_marketer, false)
  );
  IF coalesce((result->>'ok')::boolean, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'owner_return_to_market_failed';
  END IF;

  INSERT INTO public.listing_request_market_return_acks (
    request_id,
    owner_id,
    prior_workflow_stage,
    prior_owner_action_reason,
    prior_permit_deadline_at,
    next_round,
    allow_same_marketer
  ) VALUES (
    req.id,
    uid,
    req.workflow_stage,
    req.owner_action_reason,
    req.permit_deadline_at,
    coalesce(req.marketing_round, 1) + 1,
    coalesce(p_allow_same_marketer, false)
  );

  RETURN result || jsonb_build_object('legal_ack_recorded', true);
END;
$$;

REVOKE ALL ON FUNCTION public.owner_return_request_to_market_with_ack(
  uuid, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_return_request_to_market_with_ack(
  uuid, boolean, boolean
) TO authenticated;

-- Prevent clients from bypassing the acknowledgement RPC.
REVOKE ALL ON FUNCTION public.owner_return_request_to_market(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.owner_return_request_to_market(uuid, boolean)
  TO service_role;

COMMIT;