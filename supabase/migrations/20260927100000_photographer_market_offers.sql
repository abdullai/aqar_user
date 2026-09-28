BEGIN;

ALTER TABLE public.photo_shoot_requests
  ALTER COLUMN photographer_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS fulfillment_mode text NOT NULL DEFAULT 'direct';

ALTER TABLE public.photo_shoot_requests
  DROP CONSTRAINT IF EXISTS photo_shoot_requests_status_check,
  DROP CONSTRAINT IF EXISTS photo_shoot_fulfillment_mode_check;

ALTER TABLE public.photo_shoot_requests
  ADD CONSTRAINT photo_shoot_requests_status_check
    CHECK (status IN (
      'open', 'pending', 'accepted', 'rejected', 'in_progress',
      'delivered', 'cancelled'
    )),
  ADD CONSTRAINT photo_shoot_fulfillment_mode_check
    CHECK (fulfillment_mode IN ('direct', 'independent_market', 'marketer_bundle'));

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS photography_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS photography_fulfillment text NOT NULL DEFAULT 'independent_market',
  ADD COLUMN IF NOT EXISTS photo_shoot_request_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.listing_requests'::regclass
      AND conname = 'listing_requests_photography_fulfillment_check'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_photography_fulfillment_check
      CHECK (photography_fulfillment IN ('independent_market', 'marketer_bundle'));
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.listing_requests'::regclass
      AND conname = 'listing_requests_photo_shoot_request_fk'
  ) THEN
    ALTER TABLE public.listing_requests
      ADD CONSTRAINT listing_requests_photo_shoot_request_fk
      FOREIGN KEY (photo_shoot_request_id)
      REFERENCES public.photo_shoot_requests (id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.listing_offer_photography (
  offer_id uuid PRIMARY KEY REFERENCES public.listing_offers (id) ON DELETE CASCADE,
  request_id uuid NOT NULL REFERENCES public.listing_requests (id) ON DELETE CASCADE,
  marketer_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  amount_sar numeric NOT NULL CHECK (amount_sar >= 0),
  details text NOT NULL CHECK (length(trim(details)) BETWEEN 3 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.listing_offer_photography ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS listing_offer_photography_select_participants
  ON public.listing_offer_photography;
CREATE POLICY listing_offer_photography_select_participants
  ON public.listing_offer_photography FOR SELECT TO authenticated
  USING (
    marketer_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.listing_requests lr
      WHERE lr.id = request_id AND lr.owner_id = auth.uid()
    )
    OR public.is_platform_staff()
  );
REVOKE INSERT, UPDATE, DELETE ON public.listing_offer_photography
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.listing_offer_photography TO authenticated;

CREATE INDEX IF NOT EXISTS idx_photo_shoot_open_market
  ON public.photo_shoot_requests (created_at DESC)
  WHERE status = 'open' AND fulfillment_mode = 'independent_market';

CREATE TABLE IF NOT EXISTS public.photo_shoot_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.photo_shoot_requests (id) ON DELETE CASCADE,
  photographer_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  amount_sar numeric NOT NULL CHECK (amount_sar >= 0),
  details text NOT NULL CHECK (length(trim(details)) BETWEEN 3 AND 2000),
  proposed_at timestamptz,
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'accepted', 'declined', 'not_selected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, photographer_id)
);

CREATE INDEX IF NOT EXISTS idx_photo_shoot_offers_photographer
  ON public.photo_shoot_offers (photographer_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_photo_shoot_offers_request
  ON public.photo_shoot_offers (request_id, status, created_at DESC);

ALTER TABLE public.photo_shoot_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS photo_shoot_offers_select_participants
  ON public.photo_shoot_offers;
CREATE POLICY photo_shoot_offers_select_participants
  ON public.photo_shoot_offers FOR SELECT TO authenticated
  USING (
    photographer_id = auth.uid()
    OR EXISTS (
      SELECT 1
      FROM public.photo_shoot_requests r
      WHERE r.id = request_id
        AND (r.requester_id = auth.uid() OR r.property_owner_id = auth.uid())
    )
    OR public.is_platform_staff()
  );

REVOKE INSERT, UPDATE, DELETE ON public.photo_shoot_offers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.photo_shoot_offers TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'photo_shoot_offers'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.photo_shoot_offers;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_photo_shoot_market_request(
  p_property_id uuid DEFAULT NULL,
  p_listing_request_id uuid DEFAULT NULL,
  p_fulfillment_mode text DEFAULT 'independent_market',
  p_shoot_kinds text[] DEFAULT ARRAY['photos']::text[],
  p_location_text text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_preferred_at timestamptz DEFAULT NULL,
  p_max_photos int DEFAULT 30,
  p_max_videos int DEFAULT 1,
  p_include_tour boolean DEFAULT false,
  p_owner_media_consent boolean DEFAULT false,
  p_owner_cover_change_consent boolean DEFAULT false,
  p_owner_replace_media_consent boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
  v_owner uuid;
  v_publisher uuid;
  v_request_owner uuid;
  v_linked_property uuid;
  v_guidance jsonb := '{}'::jsonb;
  v_request_id uuid;
  v_mode text := lower(trim(coalesce(p_fulfillment_mode, 'independent_market')));
  v_kinds text[];
  v_photographer uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_property_id IS NULL AND p_listing_request_id IS NULL THEN
    RAISE EXCEPTION 'property_or_listing_request_required';
  END IF;
  IF p_owner_media_consent IS NOT TRUE THEN
    RAISE EXCEPTION 'owner_media_consent_required';
  END IF;
  IF v_mode NOT IN ('independent_market', 'marketer_bundle') THEN
    RAISE EXCEPTION 'invalid_photography_fulfillment_mode';
  END IF;

  IF p_property_id IS NOT NULL THEN
    SELECT owner_id, published_by_marketer_id, coalesce(listing_guidance, '{}'::jsonb)
      INTO v_owner, v_publisher, v_guidance
    FROM public.properties
    WHERE id = p_property_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;
    IF uid IS DISTINCT FROM v_owner AND uid IS DISTINCT FROM v_publisher THEN
      RAISE EXCEPTION 'not_listing_owner_or_publisher';
    END IF;
  END IF;

  IF p_listing_request_id IS NOT NULL THEN
    SELECT lr.owner_id, lr.preview_property_id
      INTO v_request_owner, v_linked_property
    FROM public.listing_requests lr
    WHERE lr.id = p_listing_request_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'listing_request_not_found'; END IF;
    IF uid IS DISTINCT FROM v_request_owner THEN
      RAISE EXCEPTION 'not_listing_request_owner';
    END IF;
    IF p_property_id IS NULL THEN
      p_property_id := v_linked_property;
    ELSIF v_linked_property IS NOT NULL
          AND p_property_id IS DISTINCT FROM v_linked_property THEN
      RAISE EXCEPTION 'listing_request_property_mismatch';
    END IF;
    IF p_property_id IS NOT NULL THEN
      SELECT owner_id, published_by_marketer_id,
             coalesce(listing_guidance, '{}'::jsonb)
        INTO v_owner, v_publisher, v_guidance
      FROM public.properties
      WHERE id = p_property_id
      FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'property_not_found'; END IF;
      IF uid IS DISTINCT FROM v_owner AND uid IS DISTINCT FROM v_publisher THEN
        RAISE EXCEPTION 'not_listing_owner_or_publisher';
      END IF;
      IF v_request_owner IS DISTINCT FROM v_owner
         AND v_request_owner IS DISTINCT FROM v_publisher THEN
        RAISE EXCEPTION 'listing_request_property_owner_mismatch';
      END IF;
    ELSE
      v_owner := v_request_owner;
    END IF;
  END IF;

  v_kinds := ARRAY(
    SELECT DISTINCT CASE
      WHEN kind IN ('tour_3d', '3d', 'virtual_tour') THEN 'tour'
      ELSE kind
    END
    FROM unnest(coalesce(p_shoot_kinds, ARRAY['photos']::text[])) AS kinds(kind)
    WHERE trim(kind) <> ''
  );
  IF coalesce(array_length(v_kinds, 1), 0) = 0 THEN
    RAISE EXCEPTION 'shoot_kind_required';
  END IF;

  IF v_mode = 'marketer_bundle' AND p_listing_request_id IS NULL THEN
    RAISE EXCEPTION 'marketer_bundle_requires_listing_request';
  END IF;

  INSERT INTO public.photo_shoot_requests (
    listing_request_id, property_id, property_owner_id, requester_id,
    photographer_id, shoot_kinds, location_text, latitude, longitude,
    preferred_at, status, max_photos, max_videos, include_tour,
    owner_media_consent, owner_media_consent_at,
    owner_cover_change_consent, owner_replace_media_consent,
    owner_media_consent_scope, fulfillment_mode
  ) VALUES (
    p_listing_request_id, p_property_id, v_owner, uid,
    v_photographer, v_kinds, nullif(trim(p_location_text), ''),
    p_latitude, p_longitude, p_preferred_at,
    'open',
    least(greatest(coalesce(p_max_photos, 30), 1), 80),
    least(greatest(coalesce(p_max_videos, 1), 0), 3),
    coalesce(p_include_tour, 'tour' = ANY (v_kinds)),
    true, now(), coalesce(p_owner_cover_change_consent, false),
    coalesce(p_owner_replace_media_consent, false),
    jsonb_build_object(
      'version', 2,
      'purpose', 'photographer_media_for_this_property',
      'fulfillment_mode', v_mode,
      'cover_change', coalesce(p_owner_cover_change_consent, false),
      'replace_existing_media', coalesce(p_owner_replace_media_consent, false),
      'granted_by', uid
    ),
    v_mode
  )
  RETURNING id INTO v_request_id;

  IF p_property_id IS NOT NULL THEN
    UPDATE public.properties
    SET listing_guidance = jsonb_set(
      jsonb_set(v_guidance, '{photo_shoot_status}',
        '"open"'::jsonb, true),
      '{photo_shoot_request_id}', to_jsonb(v_request_id), true
    )
    WHERE id = p_property_id;
  END IF;

  IF p_listing_request_id IS NOT NULL THEN
    UPDATE public.listing_requests
    SET photography_required = true,
        photography_fulfillment = v_mode,
        photo_shoot_request_id = v_request_id,
        updated_at = now()
    WHERE id = p_listing_request_id;
  END IF;

  IF v_mode = 'independent_market' THEN
    FOR v_photographer IN
      SELECT pp.user_id
      FROM public.photographer_profiles pp
      WHERE pp.status = 'verified'
        AND pp.user_id IS DISTINCT FROM uid
        AND public.user_has_active_photographer_subscription(pp.user_id)
    LOOP
      PERFORM public.workflow_create_notification(
        v_photographer,
        'photo_shoot_requested',
        'فرصة تصوير عقاري جديدة',
        'توجد فرصة تصوير جديدة مناسبة. افتح سوق التصوير للاطلاع عليها.',
        'photo_shoot',
        v_request_id,
        jsonb_build_object(
          'title_ar', 'فرصة تصوير عقاري جديدة',
          'title_en', 'New property photography opportunity',
          'body_ar', 'توجد فرصة تصوير جديدة مناسبة. افتح سوق التصوير للاطلاع عليها.',
          'body_en', 'A new photography opportunity is available in the photographer market.',
          'deep_route', 'photographer_hub',
          'role', 'photographer',
          'photographer_tab', '0',
          'main_tab', 'my_ads',
          'photographer_mode', 'photographer',
          'shoot_request_id', v_request_id,
          'property_id', p_property_id,
          'listing_request_id', p_listing_request_id
        )
      );
    END LOOP;
  END IF;

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_open_photo_shoot_opportunities()
RETURNS TABLE (
  request_id uuid,
  property_id uuid,
  listing_request_id uuid,
  shoot_kinds text[],
  preferred_at timestamptz,
  created_at timestamptz,
  max_photos int,
  max_videos int,
  include_tour boolean,
  location_text text,
  listing_preview jsonb,
  offer_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.user_id = uid AND pp.status = 'verified'
  ) OR NOT public.user_has_active_photographer_subscription(uid) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.property_id,
    r.listing_request_id,
    r.shoot_kinds,
    r.preferred_at,
    r.created_at,
    r.max_photos,
    r.max_videos,
    r.include_tour,
    coalesce(to_jsonb(p)->>'city', to_jsonb(lr)->>'city', ''),
    jsonb_build_object(
      'title', coalesce(to_jsonb(p)->>'title', to_jsonb(lr)->>'title', 'إعلان عقاري'),
      'city', coalesce(to_jsonb(p)->>'city', to_jsonb(lr)->>'city', ''),
      'price', coalesce(to_jsonb(p)->>'price', to_jsonb(lr)->>'price'),
      'purpose', coalesce(to_jsonb(p)->>'purpose', to_jsonb(lr)->>'purpose', ''),
      'cover_path', coalesce(
        to_jsonb(p)->>'cover_image_path',
        to_jsonb(lr)->>'cover_image_path',
        to_jsonb(lr)->>'default_cover_path',
        ''
      )
    ),
    (SELECT count(*) FROM public.photo_shoot_offers o WHERE o.request_id = r.id)
  FROM public.photo_shoot_requests r
  LEFT JOIN public.properties p ON p.id = r.property_id
  LEFT JOIN public.listing_requests lr ON lr.id = r.listing_request_id
  WHERE r.status = 'open'
    AND r.fulfillment_mode = 'independent_market'
    AND r.requester_id IS DISTINCT FROM uid
    AND NOT EXISTS (
      SELECT 1 FROM public.photo_shoot_offers mine
      WHERE mine.request_id = r.id AND mine.photographer_id = uid
    )
  ORDER BY r.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_photo_shoot_offer(
  p_request_id uuid,
  p_amount_sar numeric,
  p_details text,
  p_proposed_at timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
  req public.photo_shoot_requests%ROWTYPE;
  offer_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_amount_sar IS NULL OR p_amount_sar < 0 THEN
    RAISE EXCEPTION 'invalid_offer_amount';
  END IF;
  IF length(trim(coalesce(p_details, ''))) NOT BETWEEN 3 AND 2000 THEN
    RAISE EXCEPTION 'offer_details_required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.user_id = uid AND pp.status = 'verified'
  ) OR NOT public.user_has_active_photographer_subscription(uid) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  SELECT * INTO req
  FROM public.photo_shoot_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF req.status <> 'open' OR req.fulfillment_mode <> 'independent_market' THEN
    RAISE EXCEPTION 'shoot_not_open';
  END IF;
  IF req.requester_id = uid OR req.property_owner_id = uid THEN
    RAISE EXCEPTION 'requester_cannot_offer';
  END IF;

  INSERT INTO public.photo_shoot_offers (
    request_id, photographer_id, amount_sar, details, proposed_at
  ) VALUES (
    p_request_id, uid, p_amount_sar, trim(p_details), p_proposed_at
  ) RETURNING id INTO offer_id;

  PERFORM public.workflow_create_notification(
    req.requester_id,
    'photo_shoot_offer_received',
    'وصلك عرض تصوير عقاري',
    'راجع تفاصيل العرض في «صفحتي ← كمصور ← طلباتي للتصوير».',
    'photo_shoot',
    p_request_id,
    jsonb_build_object(
      'title_ar', 'وصلك عرض تصوير عقاري',
      'title_en', 'A photographer sent you an offer',
      'body_ar', 'راجع تفاصيل العرض في «صفحتي ← كمصور ← طلباتي للتصوير».',
      'body_en', 'Review the offer in My Page → Photographer → My photo requests.',
      'deep_route', 'photographer_hub',
      'role', 'requester',
      'main_tab', 'my_ads',
      'photographer_mode', 'requester',
      'photographer_tab', '1',
      'shoot_request_id', p_request_id,
      'photo_shoot_offer_id', offer_id,
      'property_id', req.property_id,
      'listing_request_id', req.listing_request_id
    )
  );
  IF req.property_owner_id IS NOT NULL
     AND req.property_owner_id IS DISTINCT FROM req.requester_id THEN
    PERFORM public.workflow_create_notification(
      req.property_owner_id,
      'photo_shoot_offer_received',
      'وصل عرض تصوير لإعلانك',
      'يمكنك متابعة عروض التصوير مع صاحب الطلب من صفحة العقار.',
      'photo_shoot',
      p_request_id,
      jsonb_build_object(
        'title_ar', 'وصل عرض تصوير لإعلانك',
        'title_en', 'A photo-shoot offer was received for your listing',
        'body_ar', 'يمكنك متابعة عروض التصوير مع صاحب الطلب من صفحة العقار.',
        'body_en', 'The photography requester can review the offer for your listing.',
        'deep_route', 'photographer_hub',
        'role', 'requester',
        'main_tab', 'my_ads',
        'photographer_mode', 'requester',
        'photographer_tab', '1',
        'shoot_request_id', p_request_id,
        'photo_shoot_offer_id', offer_id,
        'property_id', req.property_id,
        'listing_request_id', req.listing_request_id
      )
    );
  END IF;

  RETURN offer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.respond_photo_shoot_offer(
  p_offer_id uuid,
  p_accept boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
  offer public.photo_shoot_offers%ROWTYPE;
  req public.photo_shoot_requests%ROWTYPE;
  v_name text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO offer
  FROM public.photo_shoot_offers
  WHERE id = p_offer_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'photo_offer_not_found'; END IF;

  SELECT * INTO req
  FROM public.photo_shoot_requests
  WHERE id = offer.request_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shoot_not_found'; END IF;
  IF uid IS DISTINCT FROM req.requester_id
     AND uid IS DISTINCT FROM req.property_owner_id THEN
    RAISE EXCEPTION 'not_photo_shoot_request_owner';
  END IF;
  IF req.status <> 'open' OR offer.status <> 'submitted' THEN
    RAISE EXCEPTION 'photo_offer_not_actionable';
  END IF;

  IF NOT coalesce(p_accept, false) THEN
    UPDATE public.photo_shoot_offers
    SET status = 'declined', updated_at = now()
    WHERE id = p_offer_id;
    PERFORM public.workflow_create_notification(
      offer.photographer_id,
      'photo_shoot_offer_declined',
      'لم يُقبل عرض التصوير',
      'تم إغلاق عرضك لهذا الطلب. ستبقى بقية فرصك في سوق التصوير متاحة.',
      'photo_shoot',
      req.id,
      jsonb_build_object(
        'title_ar', 'لم يُقبل عرض التصوير',
        'title_en', 'Your photography offer was declined',
        'body_ar', 'تم إغلاق عرضك لهذا الطلب. ستبقى بقية فرصك في سوق التصوير متاحة.',
        'body_en', 'This offer was declined. Other opportunities remain available.',
        'deep_route', 'photographer_hub',
        'role', 'photographer',
        'photographer_tab', '1',
        'main_tab', 'my_ads',
        'photographer_mode', 'photographer',
        'shoot_request_id', req.id,
        'photo_shoot_offer_id', p_offer_id
      )
    );
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.user_id = offer.photographer_id AND pp.status = 'verified'
  ) OR NOT public.user_has_active_photographer_subscription(offer.photographer_id) THEN
    RAISE EXCEPTION 'selected_photographer_no_longer_eligible';
  END IF;

  UPDATE public.photo_shoot_offers
  SET status = CASE WHEN id = p_offer_id THEN 'accepted' ELSE 'not_selected' END,
      updated_at = now()
  WHERE request_id = req.id AND status = 'submitted';

  UPDATE public.photo_shoot_requests
  SET photographer_id = offer.photographer_id,
      status = 'accepted',
      accepted_at = now(),
      quoted_amount_sar = offer.amount_sar,
      updated_at = now()
  WHERE id = req.id;

  IF req.property_id IS NOT NULL THEN
    UPDATE public.properties
    SET listing_guidance = jsonb_set(
      coalesce(listing_guidance, '{}'::jsonb),
      '{photo_shoot_status}', '"accepted"'::jsonb, true
    )
    WHERE id = req.property_id;
  END IF;

  SELECT coalesce(display_name, '') INTO v_name
  FROM public.photographer_profiles WHERE user_id = offer.photographer_id;
  PERFORM public.workflow_create_notification(
    offer.photographer_id,
    'photo_shoot_offer_accepted',
    'تم اختيار عرضك للتصوير',
    'ابدأ متابعة طلب التصوير وتجهيز التسليم في «أعمالي».',
    'photo_shoot',
    req.id,
    jsonb_build_object(
      'title_ar', 'تم اختيار عرضك للتصوير',
      'title_en', 'Your photography offer was selected',
      'body_ar', 'ابدأ متابعة طلب التصوير وتجهيز التسليم في «أعمالي».',
      'body_en', 'Your offer was selected. Continue the shoot from My Work.',
      'deep_route', 'photographer_hub',
      'role', 'photographer',
      'photographer_tab', '2',
      'main_tab', 'my_ads',
      'photographer_mode', 'photographer',
      'shoot_request_id', req.id,
      'photo_shoot_offer_id', p_offer_id,
      'property_id', req.property_id,
      'photographer_name', v_name
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_bundled_photo_marketing_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_required boolean;
  v_fulfillment text;
BEGIN
  SELECT photography_required, photography_fulfillment
    INTO v_required, v_fulfillment
  FROM public.listing_requests
  WHERE id = NEW.request_id;

  IF coalesce(v_required, false)
      AND v_fulfillment = 'marketer_bundle' THEN
    IF current_setting('aqar.photo_bundle_offer', true) IS DISTINCT FROM 'on' THEN
      RAISE EXCEPTION 'photography_offer_fields_required';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.photographer_profiles pp
      WHERE pp.user_id = NEW.marketer_id AND pp.status = 'verified'
    ) OR NOT public.user_has_active_photographer_subscription(NEW.marketer_id) THEN
      RAISE EXCEPTION 'photographer_subscription_required';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_guard_bundled_photo_marketing_offer
  ON public.listing_offers;
CREATE TRIGGER tr_guard_bundled_photo_marketing_offer
  BEFORE INSERT OR UPDATE OF price, offer_amount, notes ON public.listing_offers
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_bundled_photo_marketing_offer();

CREATE OR REPLACE FUNCTION public.submit_listing_offer_with_photography(
  p_request_id uuid,
  p_offer_amount numeric,
  p_notes text,
  p_photography_amount numeric,
  p_photography_details text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
  offer_id uuid;
  req public.listing_requests%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO req
  FROM public.listing_requests
  WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'request_not_found'; END IF;
  IF req.photography_required IS NOT TRUE
     OR req.photography_fulfillment <> 'marketer_bundle' THEN
    RAISE EXCEPTION 'photography_not_bundled_for_request';
  END IF;
  IF p_photography_amount IS NULL OR p_photography_amount < 0 THEN
    RAISE EXCEPTION 'invalid_photography_amount';
  END IF;
  IF length(trim(coalesce(p_photography_details, ''))) NOT BETWEEN 3 AND 2000 THEN
    RAISE EXCEPTION 'photography_offer_details_required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.user_id = uid AND pp.status = 'verified'
  ) OR NOT public.user_has_active_photographer_subscription(uid) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  PERFORM set_config('aqar.photo_bundle_offer', 'on', true);
  offer_id := public.submit_listing_offer(
    p_request_id,
    p_offer_amount,
    coalesce(p_notes, '')
  );
  INSERT INTO public.listing_offer_photography (
    offer_id, request_id, marketer_id, amount_sar, details
  ) VALUES (
    offer_id, p_request_id, uid, p_photography_amount,
    trim(p_photography_details)
  )
  ON CONFLICT (offer_id) DO UPDATE
  SET amount_sar = EXCLUDED.amount_sar,
      details = EXCLUDED.details,
      updated_at = now();
  PERFORM set_config('aqar.photo_bundle_offer', 'off', true);
  RETURN offer_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_bundled_photo_shoot_after_marketing_accept()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  req public.listing_requests%ROWTYPE;
  component public.listing_offer_photography%ROWTYPE;
  v_property_id uuid;
BEGIN
  IF lower(trim(coalesce(OLD.status::text, ''))) IN (
    'owner_accepted', 'selected', 'converted_to_contract'
  ) THEN
    RETURN NEW;
  END IF;
  IF lower(trim(coalesce(NEW.status::text, ''))) NOT IN (
    'owner_accepted', 'selected', 'converted_to_contract'
  ) THEN
    RETURN NEW;
  END IF;

  SELECT * INTO req
  FROM public.listing_requests
  WHERE id = NEW.request_id
  FOR UPDATE;
  IF NOT FOUND OR req.photography_required IS NOT TRUE
     OR req.photography_fulfillment <> 'marketer_bundle' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO component
  FROM public.listing_offer_photography
  WHERE offer_id = NEW.id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'photography_offer_component_missing'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.photographer_profiles pp
    WHERE pp.user_id = NEW.marketer_id AND pp.status = 'verified'
  ) OR NOT public.user_has_active_photographer_subscription(NEW.marketer_id) THEN
    RAISE EXCEPTION 'photographer_subscription_required';
  END IF;

  v_property_id := req.preview_property_id;
  UPDATE public.photo_shoot_requests
  SET photographer_id = NEW.marketer_id,
      property_id = coalesce(property_id, v_property_id),
      property_owner_id = coalesce(property_owner_id, req.owner_id),
      status = 'accepted',
      accepted_at = coalesce(accepted_at, now()),
      quoted_amount_sar = component.amount_sar,
      updated_at = now()
  WHERE id = req.photo_shoot_request_id
    AND fulfillment_mode = 'marketer_bundle'
    AND status = 'open';

  PERFORM public.workflow_create_notification(
    NEW.marketer_id,
    'photo_shoot_offer_accepted',
    'قُبل عرض التسويق والتصوير',
    'اختار المالك عرضك المتضمن للتصوير. تابع العمل من صفحتي كمصور.',
    'photo_shoot',
    req.photo_shoot_request_id,
    jsonb_build_object(
      'title_ar', 'قُبل عرض التسويق والتصوير',
      'title_en', 'Your marketing and photography offer was accepted',
      'body_ar', 'اختار المالك عرضك المتضمن للتصوير. تابع العمل من صفحتي كمصور.',
      'body_en', 'Your bundled offer was selected. Continue the photo work from My Page.',
      'deep_route', 'photographer_hub',
      'main_tab', 'my_ads',
      'role', 'photographer',
      'photographer_mode', 'photographer',
      'photographer_tab', '2',
      'shoot_request_id', req.photo_shoot_request_id,
      'request_id', req.id,
      'offer_id', NEW.id,
      'property_id', v_property_id
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_sync_bundled_photo_shoot_after_marketing_accept
  ON public.listing_offers;
CREATE TRIGGER tr_sync_bundled_photo_shoot_after_marketing_accept
  AFTER UPDATE OF status ON public.listing_offers
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_bundled_photo_shoot_after_marketing_accept();

CREATE OR REPLACE FUNCTION public.attach_bundled_photo_shoot_to_property()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
BEGIN
  IF NEW.request_id IS NULL THEN RETURN NEW; END IF;
  UPDATE public.photo_shoot_requests
  SET property_id = NEW.id,
      property_owner_id = coalesce(property_owner_id, NEW.owner_id),
      updated_at = now()
  WHERE listing_request_id = NEW.request_id
    AND fulfillment_mode = 'marketer_bundle'
    AND property_id IS NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_attach_bundled_photo_shoot_to_property
  ON public.properties;
CREATE TRIGGER tr_attach_bundled_photo_shoot_to_property
  AFTER INSERT OR UPDATE OF request_id ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.attach_bundled_photo_shoot_to_property();

CREATE OR REPLACE FUNCTION public.list_my_photo_shoot_offers()
RETURNS TABLE (
  offer_id uuid,
  request_id uuid,
  amount_sar numeric,
  details text,
  proposed_at timestamptz,
  offer_status text,
  offer_created_at timestamptz,
  request_status text,
  delivery_review_status text,
  property_id uuid,
  listing_request_id uuid,
  shoot_kinds text[],
  preferred_at timestamptz,
  listing_preview jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  RETURN QUERY
  SELECT o.id, o.request_id, o.amount_sar, o.details, o.proposed_at,
         o.status, o.created_at, r.status, r.delivery_review_status, r.property_id,
         r.listing_request_id, r.shoot_kinds, r.preferred_at,
         jsonb_build_object(
           'title', coalesce(to_jsonb(p)->>'title', to_jsonb(lr)->>'title', 'إعلان عقاري'),
           'city', coalesce(to_jsonb(p)->>'city', to_jsonb(lr)->>'city', ''),
           'price', coalesce(to_jsonb(p)->>'price', to_jsonb(lr)->>'price'),
           'cover_path', coalesce(
             to_jsonb(p)->>'cover_image_path',
             to_jsonb(lr)->>'cover_image_path',
             to_jsonb(lr)->>'default_cover_path',
             ''
           )
         )
  FROM public.photo_shoot_offers o
  JOIN public.photo_shoot_requests r ON r.id = o.request_id
  LEFT JOIN public.properties p ON p.id = r.property_id
  LEFT JOIN public.listing_requests lr ON lr.id = r.listing_request_id
  WHERE o.photographer_id = uid
  ORDER BY o.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_my_photo_shoot_requests()
RETURNS TABLE (
  shoot jsonb,
  listing_preview jsonb,
  offer_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  RETURN QUERY
  SELECT
    to_jsonb(r),
    jsonb_build_object(
      'title', coalesce(to_jsonb(p)->>'title', to_jsonb(lr)->>'title', ''),
      'city', coalesce(to_jsonb(p)->>'city', to_jsonb(lr)->>'city', ''),
      'public_code', coalesce(
        to_jsonb(p)->>'listing_public_code',
        to_jsonb(lr)->>'listing_request_public_code',
        ''
      ),
      'price', coalesce(to_jsonb(p)->>'price', to_jsonb(lr)->>'price'),
      'purpose', coalesce(to_jsonb(p)->>'purpose', to_jsonb(lr)->>'purpose', ''),
      'cover_path', coalesce(
        to_jsonb(p)->>'cover_image_path',
        to_jsonb(lr)->>'cover_image_path',
        to_jsonb(lr)->>'default_cover_path',
        ''
      )
    ),
    (SELECT count(*) FROM public.photo_shoot_offers o WHERE o.request_id = r.id)
  FROM public.photo_shoot_requests r
  LEFT JOIN public.properties p ON p.id = r.property_id
  LEFT JOIN public.listing_requests lr ON lr.id = r.listing_request_id
  WHERE r.requester_id = uid OR r.property_owner_id = uid
  ORDER BY r.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_photo_shoot_request_offers(
  p_request_id uuid DEFAULT NULL
)
RETURNS TABLE (
  offer_id uuid,
  photographer_id uuid,
  display_name text,
  rating_avg numeric,
  rating_count int,
  amount_sar numeric,
  details text,
  proposed_at timestamptz,
  offer_status text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_request_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.photo_shoot_requests r
    WHERE r.id = p_request_id
      AND (r.requester_id = uid OR r.property_owner_id = uid)
  ) THEN
    RAISE EXCEPTION 'not_photo_shoot_request_owner';
  END IF;
  RETURN QUERY
  SELECT o.id, o.photographer_id, coalesce(pp.display_name, ''),
         coalesce(pp.rating_avg, 0), coalesce(pp.rating_count, 0),
         o.amount_sar, o.details, o.proposed_at, o.status, o.created_at
  FROM public.photo_shoot_offers o
  JOIN public.photo_shoot_requests r ON r.id = o.request_id
  LEFT JOIN public.photographer_profiles pp ON pp.user_id = o.photographer_id
  WHERE (p_request_id IS NOT NULL AND o.request_id = p_request_id)
     OR (p_request_id IS NULL AND
         (r.requester_id = uid OR r.property_owner_id = uid))
  ORDER BY (o.status = 'accepted') DESC, o.created_at ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.create_photo_shoot_market_request(
  uuid, uuid, text, text[], text, double precision, double precision,
  timestamptz, int, int, boolean, boolean, boolean, boolean
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_photo_shoot_market_request(
  uuid, uuid, text, text[], text, double precision, double precision,
  timestamptz, int, int, boolean, boolean, boolean, boolean
) TO authenticated;

REVOKE ALL ON FUNCTION public.list_open_photo_shoot_opportunities()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_open_photo_shoot_opportunities()
  TO authenticated;

REVOKE ALL ON FUNCTION public.submit_photo_shoot_offer(
  uuid, numeric, text, timestamptz
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_photo_shoot_offer(
  uuid, numeric, text, timestamptz
) TO authenticated;

REVOKE ALL ON FUNCTION public.respond_photo_shoot_offer(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_photo_shoot_offer(uuid, boolean)
  TO authenticated;

REVOKE ALL ON FUNCTION public.submit_listing_offer_with_photography(
  uuid, numeric, text, numeric, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_listing_offer_with_photography(
  uuid, numeric, text, numeric, text
) TO authenticated;

REVOKE ALL ON FUNCTION public.guard_bundled_photo_marketing_offer()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_bundled_photo_shoot_after_marketing_accept()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.attach_bundled_photo_shoot_to_property()
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.list_my_photo_shoot_offers()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_photo_shoot_offers()
  TO authenticated;

REVOKE ALL ON FUNCTION public.list_my_photo_shoot_requests()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_photo_shoot_requests()
  TO authenticated;

REVOKE ALL ON FUNCTION public.list_photo_shoot_request_offers(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_photo_shoot_request_offers(uuid)
  TO authenticated;

COMMIT;