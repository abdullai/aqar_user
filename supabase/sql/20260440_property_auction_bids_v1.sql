-- =============================================================================
-- مزايدات على العقارات (مرحلة 1): جدول سجل + RPC يحدّث current_bid بشكل آمن
--
-- - لا يُسمح بـ INSERT مباشر من العميل؛ الإدراج عبر place_property_bid فقط.
-- - الحد الأدنى للزيادة: max(100 ريال، 1% من أعلى سعر حالي/افتتاحي).
-- - يُنفَّذ يدوياً في Supabase SQL Editor بعد المراجعة.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.property_auction_bids (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  bidder_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK (amount > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_property_auction_bids_property_created
  ON public.property_auction_bids (property_id, created_at DESC);

ALTER TABLE public.property_auction_bids ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS property_auction_bids_select_public_or_party
  ON public.property_auction_bids;

CREATE POLICY property_auction_bids_select_public_or_party
  ON public.property_auction_bids
  FOR SELECT
  TO anon, authenticated
  USING (
    bidder_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_auction_bids.property_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_auction_bids.property_id
        AND p.published_by_marketer_id IS NOT NULL
        AND p.published_by_marketer_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = property_auction_bids.property_id
        AND (
          p.status = ANY (
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

-- لا سياسات INSERT/UPDATE/DELETE للعميل — الإدراج عبر الدالة SECURITY DEFINER فقط.

DROP FUNCTION IF EXISTS public.place_property_bid(uuid, numeric);

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
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_bid_amount';
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

COMMENT ON TABLE public.property_auction_bids IS
  'سجل مزايدات؛ الإدراج عبر place_property_bid فقط.';

COMMENT ON FUNCTION public.place_property_bid(uuid, numeric) IS
  'مزايدة موثّقة؛ يحدّث properties.current_bid ويُسجّل صفاً في property_auction_bids.';

REVOKE ALL ON FUNCTION public.place_property_bid(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_property_bid(uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_property_bid(uuid, numeric) TO service_role;

GRANT SELECT ON public.property_auction_bids TO anon;
GRANT SELECT ON public.property_auction_bids TO authenticated;

-- Realtime: من لوحة Supabase → Database → Publications → supabase_realtime
-- أضف الجدول property_auction_bids حتى يعمل التحديث اللحظي في التطبيق.

COMMIT;
