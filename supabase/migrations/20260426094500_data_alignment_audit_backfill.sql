-- Compatibility audit + conservative backfill for legacy profile/listing data.
-- This migration does not invent signatures or overwrite existing user names.

BEGIN;

ALTER TABLE public.users_profiles
  ADD COLUMN IF NOT EXISTS full_name text,
  ADD COLUMN IF NOT EXISTS full_name_en text,
  ADD COLUMN IF NOT EXISTS first_name_en text,
  ADD COLUMN IF NOT EXISTS second_name_en text,
  ADD COLUMN IF NOT EXISTS third_name_en text,
  ADD COLUMN IF NOT EXISTS fourth_name_en text,
  ADD COLUMN IF NOT EXISTS full_name_ar text,
  ADD COLUMN IF NOT EXISTS first_name_ar text,
  ADD COLUMN IF NOT EXISTS second_name_ar text,
  ADD COLUMN IF NOT EXISTS third_name_ar text,
  ADD COLUMN IF NOT EXISTS fourth_name_ar text,
  ADD COLUMN IF NOT EXISTS signature_storage_path text;

UPDATE public.users_profiles up
SET
  full_name_ar = nullif(trim(concat_ws(
    ' ',
    nullif(trim(coalesce(first_name_ar, '')), ''),
    nullif(trim(coalesce(second_name_ar, '')), ''),
    nullif(trim(coalesce(third_name_ar, '')), ''),
    nullif(trim(coalesce(fourth_name_ar, '')), '')
  )), ''),
  full_name_en = nullif(trim(concat_ws(
    ' ',
    nullif(trim(coalesce(first_name_en, '')), ''),
    nullif(trim(coalesce(second_name_en, '')), ''),
    nullif(trim(coalesce(third_name_en, '')), ''),
    nullif(trim(coalesce(fourth_name_en, '')), '')
  )), '')
WHERE
  (
    nullif(trim(coalesce(full_name_ar, '')), '') IS NULL
    AND (
      nullif(trim(coalesce(first_name_ar, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(second_name_ar, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(third_name_ar, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(fourth_name_ar, '')), '') IS NOT NULL
    )
  )
  OR (
    nullif(trim(coalesce(full_name_en, '')), '') IS NULL
    AND (
      nullif(trim(coalesce(first_name_en, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(second_name_en, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(third_name_en, '')), '') IS NOT NULL
      OR nullif(trim(coalesce(fourth_name_en, '')), '') IS NOT NULL
    )
  );

WITH parts AS (
  SELECT
    user_id,
    regexp_split_to_array(trim(full_name_en), '\s+') AS p
  FROM public.users_profiles
  WHERE nullif(trim(coalesce(full_name_en, '')), '') IS NOT NULL
)
UPDATE public.users_profiles up
SET
  first_name_en = coalesce(nullif(trim(up.first_name_en), ''), parts.p[1]),
  second_name_en = coalesce(nullif(trim(up.second_name_en), ''), parts.p[2]),
  third_name_en = coalesce(nullif(trim(up.third_name_en), ''), parts.p[3]),
  fourth_name_en = coalesce(
    nullif(trim(up.fourth_name_en), ''),
    CASE
      WHEN array_length(parts.p, 1) >= 4 THEN parts.p[array_length(parts.p, 1)]
      ELSE NULL
    END
  )
FROM parts
WHERE up.user_id = parts.user_id
  AND (
    nullif(trim(coalesce(up.first_name_en, '')), '') IS NULL
    OR nullif(trim(coalesce(up.second_name_en, '')), '') IS NULL
    OR nullif(trim(coalesce(up.third_name_en, '')), '') IS NULL
    OR nullif(trim(coalesce(up.fourth_name_en, '')), '') IS NULL
  );

WITH parts AS (
  SELECT
    user_id,
    regexp_split_to_array(trim(coalesce(full_name_ar, full_name)), '\s+') AS p
  FROM public.users_profiles
  WHERE nullif(trim(coalesce(full_name_ar, full_name, '')), '') IS NOT NULL
)
UPDATE public.users_profiles up
SET
  first_name_ar = coalesce(nullif(trim(up.first_name_ar), ''), parts.p[1]),
  second_name_ar = coalesce(nullif(trim(up.second_name_ar), ''), parts.p[2]),
  third_name_ar = coalesce(nullif(trim(up.third_name_ar), ''), parts.p[3]),
  fourth_name_ar = coalesce(
    nullif(trim(up.fourth_name_ar), ''),
    CASE
      WHEN array_length(parts.p, 1) >= 4 THEN parts.p[array_length(parts.p, 1)]
      ELSE NULL
    END
  )
FROM parts
WHERE up.user_id = parts.user_id
  AND (
    nullif(trim(coalesce(up.first_name_ar, '')), '') IS NULL
    OR nullif(trim(coalesce(up.second_name_ar, '')), '') IS NULL
    OR nullif(trim(coalesce(up.third_name_ar, '')), '') IS NULL
    OR nullif(trim(coalesce(up.fourth_name_ar, '')), '') IS NULL
  );

UPDATE public.properties p
SET updated_at = coalesce(p.updated_at, p.created_at, now())
WHERE p.updated_at IS NULL;

UPDATE public.listing_requests lr
SET updated_at = coalesce(lr.updated_at, lr.created_at, now())
WHERE lr.updated_at IS NULL;

CREATE OR REPLACE VIEW public.v_aqar_data_quality_users AS
SELECT
  user_id,
  username,
  account_type,
  full_name,
  full_name_ar,
  full_name_en,
  signature_storage_path,
  (nullif(trim(coalesce(signature_storage_path, '')), '') IS NULL) AS missing_signature,
  (
    nullif(trim(coalesce(full_name_en, '')), '') IS NULL
    OR nullif(trim(coalesce(first_name_en, '')), '') IS NULL
    OR nullif(trim(coalesce(fourth_name_en, '')), '') IS NULL
  ) AS incomplete_english_name,
  (
    nullif(trim(coalesce(full_name_ar, full_name, '')), '') IS NULL
    OR nullif(trim(coalesce(first_name_ar, '')), '') IS NULL
    OR nullif(trim(coalesce(fourth_name_ar, '')), '') IS NULL
  ) AS incomplete_arabic_name
FROM public.users_profiles;

CREATE OR REPLACE VIEW public.v_aqar_data_quality_properties AS
SELECT
  p.id,
  p.owner_id,
  p.title,
  p.city,
  p.status,
  p.request_id,
  (
    nullif(trim(coalesce(p.title, '')), '') IS NULL
    OR nullif(trim(coalesce(p.city, '')), '') IS NULL
    OR p.owner_id IS NULL
    OR p.price IS NULL
    OR p.area IS NULL
  ) AS has_missing_card_data
FROM public.properties p;

COMMENT ON VIEW public.v_aqar_data_quality_users IS
  'Read-only audit view for legacy profile rows that still need user-facing completion.';

COMMENT ON VIEW public.v_aqar_data_quality_properties IS
  'Read-only audit view for legacy property rows missing fields used by current listing cards.';

COMMIT;
