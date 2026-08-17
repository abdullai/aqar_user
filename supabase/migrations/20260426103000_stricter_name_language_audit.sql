BEGIN;

CREATE OR REPLACE VIEW public.v_aqar_data_quality_users AS
SELECT
  user_id,
  username,
  account_type,
  full_name,
  full_name_ar,
  full_name_en,
  signature_storage_path,
  (
    nullif(trim(coalesce(signature_storage_path, '')), '') IS NULL
    OR lower(trim(coalesce(signature_storage_path, ''))) IN (
      'default_signatures/placeholder.png',
      'placeholder.png'
    )
    OR lower(trim(coalesce(signature_storage_path, ''))) LIKE '%placeholder%'
  ) AS missing_signature,
  (
    nullif(trim(coalesce(full_name_en, '')), '') IS NULL
    OR trim(coalesce(full_name_en, '')) ~ '^[0-9]+$'
    OR trim(coalesce(full_name_en, '')) ~ '[ء-ي]'
    OR trim(coalesce(full_name_en, '')) !~ '[A-Za-z]'
    OR nullif(trim(coalesce(first_name_en, '')), '') IS NULL
    OR trim(coalesce(first_name_en, '')) ~ '^[0-9]+$'
    OR trim(coalesce(first_name_en, '')) ~ '[ء-ي]'
    OR nullif(trim(coalesce(fourth_name_en, '')), '') IS NULL
    OR trim(coalesce(fourth_name_en, '')) ~ '^[0-9]+$'
    OR trim(coalesce(fourth_name_en, '')) ~ '[ء-ي]'
  ) AS incomplete_english_name,
  (
    nullif(trim(coalesce(full_name_ar, full_name, '')), '') IS NULL
    OR trim(coalesce(full_name_ar, full_name, '')) ~ '^[0-9]+$'
    OR trim(coalesce(full_name_ar, full_name, '')) !~ '[ء-ي]'
    OR nullif(trim(coalesce(first_name_ar, '')), '') IS NULL
    OR trim(coalesce(first_name_ar, '')) ~ '^[0-9]+$'
    OR trim(coalesce(first_name_ar, '')) !~ '[ء-ي]'
    OR nullif(trim(coalesce(fourth_name_ar, '')), '') IS NULL
    OR trim(coalesce(fourth_name_ar, '')) ~ '^[0-9]+$'
    OR trim(coalesce(fourth_name_ar, '')) !~ '[ء-ي]'
  ) AS incomplete_arabic_name
FROM public.users_profiles;

COMMIT;
