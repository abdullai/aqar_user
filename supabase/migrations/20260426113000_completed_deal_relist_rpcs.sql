CREATE OR REPLACE FUNCTION public.relist_completed_property_as_new(p_property_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old public.properties%ROWTYPE;
  v_new_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT p.* INTO v_old
  FROM public.properties p
  WHERE p.id = p_property_id
    AND coalesce(p.status, '') IN ('sold', 'completed')
    AND EXISTS (
      SELECT 1
      FROM public.reservations r
      WHERE r.property_id = p.id
        AND r.user_id = v_uid
        AND coalesce(r.status, '') IN ('completed', 'sold')
    )
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COMPLETED_DEAL_NOT_FOUND';
  END IF;

  INSERT INTO public.properties (
    owner_id, title, description, region, governorate, city, type, area, price,
    currency, negotiable, is_auction, current_bid, views, status, workflow_stage,
    latitude, longitude, video_url, virtual_tour_url, availability_date, amenities,
    address_line, purpose, location, bedrooms, bathrooms, parking_spots, year_built,
    furnished, floor, total_floors, extra_details, listing_guidance, rega_payload,
    waiting_marketers_since, created_at, updated_at
  )
  VALUES (
    v_uid, v_old.title, v_old.description, v_old.region, v_old.governorate,
    v_old.city, v_old.type, v_old.area, v_old.price, v_old.currency,
    v_old.negotiable, false, NULL, 0, 'waiting_mediator', 'waiting_marketers',
    v_old.latitude, v_old.longitude, v_old.video_url, v_old.virtual_tour_url,
    v_old.availability_date, v_old.amenities, v_old.address_line, v_old.purpose,
    v_old.location, v_old.bedrooms, v_old.bathrooms, v_old.parking_spots,
    v_old.year_built, v_old.furnished, v_old.floor, v_old.total_floors,
    v_old.extra_details, v_old.listing_guidance, v_old.rega_payload,
    now(), now(), now()
  )
  RETURNING id INTO v_new_id;

  UPDATE public.reservations
  SET status = 'relisted'
  WHERE property_id = p_property_id
    AND user_id = v_uid
    AND coalesce(status, '') IN ('completed', 'sold');

  RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.relist_completed_market_request_as_new(p_market_request_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old public.market_property_requests%ROWTYPE;
  v_new_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT r.* INTO v_old
  FROM public.market_property_requests r
  WHERE r.id = p_market_request_id
    AND coalesce(r.status, '') IN ('completed', 'closed', 'sold')
    AND r.requester_id = v_uid
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'COMPLETED_REQUEST_NOT_FOUND';
  END IF;

  INSERT INTO public.market_property_requests (
    requester_id, status, request_priority, title, description, purpose,
    property_type, city, districts, budget_min, budget_max, area_min_m2,
    prefer_new, show_requester_name, requester_public_name,
    cover_image_storage_path, details_json, created_at, updated_at
  )
  VALUES (
    v_uid, 'published', v_old.request_priority, v_old.title, v_old.description,
    v_old.purpose, v_old.property_type, v_old.city, v_old.districts,
    v_old.budget_min, v_old.budget_max, v_old.area_min_m2, v_old.prefer_new,
    true, v_old.requester_public_name, v_old.cover_image_storage_path,
    v_old.details_json, now(), now()
  )
  RETURNING id INTO v_new_id;

  UPDATE public.market_property_requests
  SET status = 'relisted', updated_at = now()
  WHERE id = p_market_request_id
    AND requester_id = v_uid;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.relist_completed_property_as_new(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.relist_completed_market_request_as_new(uuid) TO authenticated;
