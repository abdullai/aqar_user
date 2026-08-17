BEGIN;

CREATE OR REPLACE VIEW public.v_aqar_data_quality_listing_requests AS
SELECT
  lr.id,
  lr.owner_id,
  lr.title,
  lr.city,
  lr.status,
  lr.price,
  lr.request_price,
  lr.preview_price,
  (
    nullif(trim(coalesce(lr.title, '')), '') IS NULL
    OR nullif(trim(coalesce(lr.city, '')), '') IS NULL
    OR lr.owner_id IS NULL
    OR coalesce(lr.price, lr.request_price, lr.preview_price) IS NULL
  ) AS has_missing_request_data
FROM public.listing_requests lr;

CREATE OR REPLACE VIEW public.v_aqar_data_quality_summary AS
SELECT
  'users_missing_signature' AS check_key,
  count(*)::bigint AS affected_rows
FROM public.v_aqar_data_quality_users
WHERE missing_signature
UNION ALL
SELECT
  'users_incomplete_english_name' AS check_key,
  count(*)::bigint AS affected_rows
FROM public.v_aqar_data_quality_users
WHERE incomplete_english_name
UNION ALL
SELECT
  'users_incomplete_arabic_name' AS check_key,
  count(*)::bigint AS affected_rows
FROM public.v_aqar_data_quality_users
WHERE incomplete_arabic_name
UNION ALL
SELECT
  'properties_missing_card_data' AS check_key,
  count(*)::bigint AS affected_rows
FROM public.v_aqar_data_quality_properties
WHERE has_missing_card_data
UNION ALL
SELECT
  'listing_requests_missing_data' AS check_key,
  count(*)::bigint AS affected_rows
FROM public.v_aqar_data_quality_listing_requests
WHERE has_missing_request_data;

COMMIT;
