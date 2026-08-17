BEGIN;

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
WHERE has_missing_card_data;

COMMENT ON VIEW public.v_aqar_data_quality_summary IS
  'Counts of legacy user/property rows that need manual completion after automated backfill.';

COMMIT;
