-- =============================================================================
-- جلسات مزاد + حقول مستقبلية (ضمان/دفع) — مرحلة بنية تحتية
--
-- - إن وُجدت جلسة `open` لعقار وانتهى `ends_at`، تُرفض المزايدة.
-- - إن لم توجد جلسة للعقار، يبقى السلوك كما في 20260440 (توافق للخلف).
-- - أعمدة deposit_expectation_sar / payment_* / escrow_notes للتوسع لاحقاً
--   (بوابة دفع، ضمان، إدارة) — لا تنفّذ دفعاً تلقائياً.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.property_auction_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'open'::text
    CHECK (status = ANY (ARRAY['open'::text, 'closed'::text, 'cancelled'::text])),
  ends_at timestamptz,
  min_increment_sar numeric DEFAULT 100,
  deposit_expectation_sar numeric,
  payment_provider text,
  payment_reference text,
  escrow_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_property_auction_sessions_property
  ON public.property_auction_sessions (property_id, created_at DESC);

ALTER TABLE public.property_auction_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS property_auction_sessions_select_public_or_owner
  ON public.property_auction_sessions;

CREATE POLICY property_auction_sessions_select_public_or_owner
  ON public.property_auction_sessions
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_auction_sessions.property_id
        AND (
          p.owner_id = auth.uid()
          OR p.published_by_marketer_id = auth.uid()
          OR p.status = ANY (
            ARRAY[
              'active'::text,
              'available'::text,
              'published'::text,
              'live'::text,
              'approved'::text
            ]
          )
          OR lower(trim(coalesce(p.workflow_stage, ''))) = 'published'
        )
    )
  );

GRANT SELECT ON public.property_auction_sessions TO anon;
GRANT SELECT ON public.property_auction_sessions TO authenticated;

COMMENT ON TABLE public.property_auction_sessions IS
  'جلسة مزاد اختيارية؛ عند وجود صف open منتهٍ يرفض place_property_bid.';

CREATE OR REPLACE FUNCTION public.place_property_bid(
  p_property_id uuid,
  p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  min_required numeric;
  inc numeric;
  cur numeric;
  sess_ends timestamptz;
  sess_status text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_bid_amount';
  END IF;

  SELECT ends_at, status
  INTO sess_ends, sess_status
  FROM public.property_auction_sessions
  WHERE property_id = p_property_id
    AND status = 'open'::text
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    IF sess_ends IS NOT NULL AND sess_ends <= now() THEN
      RAISE EXCEPTION 'auction_session_ended';
    END IF;
  END IF;

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    price,
    current_bid,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF coalesce(prop.is_auction, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'not_auction_listing';
  END IF;

  IF NOT (
    lower(trim(coalesce(prop.workflow_stage, ''))) = 'published'
    OR lower(trim(coalesce(prop.status, ''))) = ANY (
      ARRAY[
        'active'::text,
        'available'::text,
        'published'::text,
        'live'::text,
        'approved'::text
      ]
    )
  ) THEN
    RAISE EXCEPTION 'listing_not_open_for_bids';
  END IF;

  IF uid = prop.owner_id THEN
    RAISE EXCEPTION 'owner_cannot_bid';
  END IF;

  IF prop.published_by_marketer_id IS NOT NULL
     AND uid = prop.published_by_marketer_id THEN
    RAISE EXCEPTION 'marketer_cannot_bid_own_listing';
  END IF;

  cur := coalesce(prop.current_bid, prop.price, 0);
  inc := greatest(100::numeric, floor(cur * 0.01));
  min_required := cur + inc;

  IF p_amount < min_required THEN
    RAISE EXCEPTION 'bid_too_low';
  END IF;

  INSERT INTO public.property_auction_bids (property_id, bidder_id, amount)
  VALUES (p_property_id, uid, p_amount);

  UPDATE public.properties
  SET
    current_bid = p_amount,
    updated_at = now()
  WHERE id = p_property_id;
END;
$$;

COMMENT ON FUNCTION public.place_property_bid(uuid, numeric) IS
  'مزايدة؛ يتحقق من جلسة مزاد مفتوحة وغير منتهية إن وُجدت.';

COMMIT;
