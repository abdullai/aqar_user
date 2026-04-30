-- =============================================================================
-- Backfill marketing card fields for existing data
-- هدفها: تحسين ظهور بطاقات "الدعوات/بانتظار التسويق" للبيانات القديمة.
-- =============================================================================

BEGIN;

-- 1) مزامنة حقول listing_requests الأساسية من آخر عقار مرتبط request_id
WITH latest_prop AS (
  SELECT DISTINCT ON (p.request_id)
    p.request_id,
    p.title,
    p.city,
    p.description,
    p.location,
    p.address_line,
    p.price,
    p.area,
    p.created_at,
    p.status
  FROM public.properties p
  WHERE p.request_id IS NOT NULL
  ORDER BY p.request_id, p.created_at DESC
)
UPDATE public.listing_requests r
SET
  title = coalesce(nullif(trim(r.title), ''), lp.title),
  city = coalesce(nullif(trim(r.city), ''), lp.city),
  description = coalesce(nullif(trim(r.description), ''), lp.description),
  updated_at = now(),
  payload = coalesce(r.payload, '{}'::jsonb) ||
    jsonb_build_object(
      'title', coalesce(nullif(trim(r.title), ''), lp.title),
      'city', coalesce(nullif(trim(r.city), ''), lp.city),
      'description', coalesce(nullif(trim(r.description), ''), lp.description),
      'location', lp.location,
      'address_line', lp.address_line,
      'price', lp.price,
      'area', lp.area
    )
FROM latest_prop lp
WHERE r.id = lp.request_id;

-- 2) إضافة صورة الغلاف للـ payload من property_images (إن كانت ناقصة)
WITH img AS (
  SELECT DISTINCT ON (p.request_id)
    p.request_id,
    pi.path AS image_path
  FROM public.properties p
  JOIN public.property_images pi ON pi.property_id = p.id
  WHERE p.request_id IS NOT NULL
  ORDER BY p.request_id, p.created_at DESC, coalesce(pi.sort_order, 0) ASC
)
UPDATE public.listing_requests r
SET
  payload = coalesce(r.payload, '{}'::jsonb) ||
    jsonb_build_object(
      'cover_image', img.image_path,
      'images', jsonb_build_array(img.image_path)
    ),
  updated_at = now()
FROM img
WHERE r.id = img.request_id
  AND (
    coalesce(trim((r.payload ->> 'cover_image')), '') = ''
    AND coalesce(trim((r.payload ->> 'image')), '') = ''
    AND coalesce(trim((r.payload ->> 'main_image')), '') = ''
  );

COMMIT;

