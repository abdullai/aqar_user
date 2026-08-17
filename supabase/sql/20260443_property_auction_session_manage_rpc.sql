-- =============================================================================
-- إدارة جلسات المزاد من التطبيق (مالك أو مسوّق منشّر فقط)
-- يشغّل بعد 20260442_property_auction_sessions_v1.sql
--
-- لتحديث الجلسة لحظياً في الواجهة: فعّل جدول property_auction_sessions
-- في نشر Realtime (لوحة Supabase → Database → Publications / Realtime).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.open_property_auction_session(
  p_property_id uuid,
  p_ends_at timestamptz DEFAULT NULL,
  p_min_increment_sar numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  new_id uuid;
  inc numeric;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id;

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

  IF uid != prop.owner_id
     AND (
       prop.published_by_marketer_id IS NULL
       OR uid != prop.published_by_marketer_id
     ) THEN
    RAISE EXCEPTION 'not_authorized_to_manage_auction';
  END IF;

  IF p_ends_at IS NOT NULL AND p_ends_at <= now() THEN
    RAISE EXCEPTION 'auction_end_must_be_future';
  END IF;

  inc := coalesce(p_min_increment_sar, 100::numeric);
  IF inc < 1::numeric THEN
    RAISE EXCEPTION 'invalid_min_increment';
  END IF;

  UPDATE public.property_auction_sessions
  SET
    status = 'cancelled'::text,
    updated_at = now()
  WHERE property_id = p_property_id
    AND status = 'open'::text;

  INSERT INTO public.property_auction_sessions (
    property_id,
    status,
    ends_at,
    min_increment_sar
  )
  VALUES (
    p_property_id,
    'open'::text,
    p_ends_at,
    inc
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_property_auction_session(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF coalesce(prop.is_auction, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'not_auction_listing';
  END IF;

  IF uid != prop.owner_id
     AND (
       prop.published_by_marketer_id IS NULL
       OR uid != prop.published_by_marketer_id
     ) THEN
    RAISE EXCEPTION 'not_authorized_to_manage_auction';
  END IF;

  UPDATE public.property_auction_sessions
  SET
    status = 'closed'::text,
    updated_at = now()
  WHERE property_id = p_property_id
    AND status = 'open'::text;
END;
$$;

COMMENT ON FUNCTION public.open_property_auction_session(uuid, timestamptz, numeric) IS
  'يفتح جلسة مزاد جديدة؛ يُلغي أي جلسة open سابقة لنفس العقار.';

COMMENT ON FUNCTION public.close_property_auction_session(uuid) IS
  'يغلق جلسة المزاد المفتوحة للعقار.';

GRANT EXECUTE ON FUNCTION public.open_property_auction_session(uuid, timestamptz, numeric)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.close_property_auction_session(uuid)
  TO authenticated;

COMMIT;
