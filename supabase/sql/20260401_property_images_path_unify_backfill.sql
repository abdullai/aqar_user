-- =============================================================================
-- توحيد صور العقارات: عمود path (كما يتوقع التطبيق) + ربط من image_url / images[]
-- + إزالة التكرار في property_images — لكل عقار وبكل مراحل workflow.
-- نفّذ في Supabase SQL Editor بعد أخذ نسخة احتياطية.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) أعمدة يتوقعها التطبيق
-- ---------------------------------------------------------------------------
ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS path text;

-- اسم الملف/المسار في مخططات قديمة؛ يجب إنشاؤه قبل أي UPDATE يذكر file_name
ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS file_name text;

ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS uploaded_by uuid;

ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS media_type text;

ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS sort_order integer;

ALTER TABLE public.property_images
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

-- ---------------------------------------------------------------------------
-- 2) تعبئة path من file_name عند الغياب (مخطط قديم)
-- ---------------------------------------------------------------------------
UPDATE public.property_images
SET path = NULLIF(btrim(path), '');

UPDATE public.property_images
SET path = NULLIF(btrim(file_name), '')
WHERE (path IS NULL OR path = '')
  AND file_name IS NOT NULL
  AND btrim(file_name) <> '';

UPDATE public.property_images
SET file_name = path
WHERE path IS NOT NULL
  AND path <> ''
  AND (file_name IS NULL OR btrim(file_name) = '');

-- ---------------------------------------------------------------------------
-- 3) حذف التكرار: نفس العقار + نفس المسار — نحتفظ بصف واحد
-- ---------------------------------------------------------------------------
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY
        property_id,
        lower(
          btrim(
            coalesce(
              nullif(btrim(coalesce(path, '')), ''),
              nullif(btrim(coalesce(file_name, '')), '')
            )
          )
        )
      ORDER BY
        sort_order NULLS LAST,
        created_at NULLS LAST,
        id
    ) AS rn
  FROM public.property_images
  WHERE coalesce(
    nullif(btrim(coalesce(path, '')), ''),
    nullif(btrim(coalesce(file_name, '')), '')
  ) IS NOT NULL
)
DELETE FROM public.property_images pi
USING ranked r
WHERE pi.id = r.id
  AND r.rn > 1;

-- ---------------------------------------------------------------------------
-- 4) استيراد من properties.images[] (إن لم يوجد صف بنفس المسار)
-- ---------------------------------------------------------------------------
INSERT INTO public.property_images (
  property_id,
  path,
  sort_order,
  file_name,
  media_type,
  created_at
)
SELECT
  p.id,
  v.img_path,
  (v.ord - 1)::int,
  v.img_path,
  'image/jpeg',
  now()
FROM public.properties p
CROSS JOIN LATERAL (
  SELECT
    btrim(u.elem) AS img_path,
    u.ord::int AS ord
  FROM unnest(coalesce(p.images, array[]::text[])) WITH ORDINALITY AS u(elem, ord)
  WHERE btrim(coalesce(u.elem, '')) <> ''
) v
WHERE NOT EXISTS (
  SELECT 1
  FROM public.property_images x
  WHERE x.property_id = p.id
    AND lower(
      btrim(
        coalesce(
          nullif(btrim(coalesce(x.path, '')), ''),
          nullif(btrim(coalesce(x.file_name, '')), '')
        )
      )
    ) = lower(btrim(v.img_path))
);

-- ---------------------------------------------------------------------------
-- 5) استيراد من properties.image_url (رابط تخزين أو مسار نسبي)
--    يستخرج الجزء بعد property-images/ إن وُجد في URL
-- ---------------------------------------------------------------------------
WITH parsed AS (
  SELECT
    p.id AS property_id,
    CASE
      WHEN strpos(p.image_url, 'property-images/') > 0 THEN
        substring(
          p.image_url
          FROM strpos(p.image_url, 'property-images/')
            + char_length('property-images/')
        )
      WHEN p.image_url !~ '^https?://' THEN
        nullif(btrim(p.image_url), '')
      ELSE
        NULL
    END AS img_path
  FROM public.properties p
  WHERE p.image_url IS NOT NULL
    AND btrim(p.image_url) <> ''
)
INSERT INTO public.property_images (
  property_id,
  path,
  sort_order,
  file_name,
  media_type,
  created_at
)
SELECT
  pr.property_id,
  pr.img_path,
  0,
  pr.img_path,
  'image/jpeg',
  now()
FROM parsed pr
WHERE pr.img_path IS NOT NULL
  AND btrim(pr.img_path) <> ''
  AND NOT EXISTS (
    SELECT 1
    FROM public.property_images x
    WHERE x.property_id = pr.property_id
  );

-- نفس تعريف parsed لكل جملة INSERT (PostgreSQL لا يبقي الـ CTE بين جملتين منفصلتين)
-- إن كان للعقار صور مسبقاً لكن image_url يشير لمسار جديد، أضفه فقط إن غير مكرر
WITH parsed AS (
  SELECT
    p.id AS property_id,
    CASE
      WHEN strpos(p.image_url, 'property-images/') > 0 THEN
        substring(
          p.image_url
          FROM strpos(p.image_url, 'property-images/')
            + char_length('property-images/')
        )
      WHEN p.image_url !~ '^https?://' THEN
        nullif(btrim(p.image_url), '')
      ELSE
        NULL
    END AS img_path
  FROM public.properties p
  WHERE p.image_url IS NOT NULL
    AND btrim(p.image_url) <> ''
)
INSERT INTO public.property_images (
  property_id,
  path,
  sort_order,
  file_name,
  media_type,
  created_at
)
SELECT
  pr.property_id,
  pr.img_path,
  coalesce(
    (SELECT max(pi.sort_order) + 1 FROM public.property_images pi WHERE pi.property_id = pr.property_id),
    0
  )::int,
  pr.img_path,
  'image/jpeg',
  now()
FROM parsed pr
WHERE pr.img_path IS NOT NULL
  AND btrim(pr.img_path) <> ''
  AND EXISTS (SELECT 1 FROM public.property_images z WHERE z.property_id = pr.property_id)
  AND NOT EXISTS (
    SELECT 1
    FROM public.property_images x
    WHERE x.property_id = pr.property_id
      AND lower(
        btrim(
          coalesce(
            nullif(btrim(coalesce(x.path, '')), ''),
            nullif(btrim(coalesce(x.file_name, '')), '')
          )
        )
      ) = lower(btrim(pr.img_path))
  );

-- ---------------------------------------------------------------------------
-- 5b) إزالة أي تكرار ناتج عن الاستيراد من image_url / images
-- ---------------------------------------------------------------------------
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY
        property_id,
        lower(
          btrim(
            coalesce(
              nullif(btrim(coalesce(path, '')), ''),
              nullif(btrim(coalesce(file_name, '')), '')
            )
          )
        )
      ORDER BY
        sort_order NULLS LAST,
        created_at NULLS LAST,
        id
    ) AS rn
  FROM public.property_images
  WHERE coalesce(
    nullif(btrim(coalesce(path, '')), ''),
    nullif(btrim(coalesce(file_name, '')), '')
  ) IS NOT NULL
)
DELETE FROM public.property_images pi
USING ranked r
WHERE pi.id = r.id
  AND r.rn > 1;

-- ---------------------------------------------------------------------------
-- 6) إعادة ترقيم sort_order لكل عقار
-- ---------------------------------------------------------------------------
WITH o AS (
  SELECT
    id,
    (row_number() OVER (
      PARTITION BY property_id
      ORDER BY sort_order NULLS LAST, created_at NULLS LAST, id
    ) - 1)::int AS new_so
  FROM public.property_images
)
UPDATE public.property_images pi
SET sort_order = o.new_so
FROM o
WHERE pi.id = o.id;

-- ---------------------------------------------------------------------------
-- 7) مزامنة properties.image_url مع أول صورة (مسار التخزين) — للقوائم السريعة
-- ---------------------------------------------------------------------------
UPDATE public.properties p
SET image_url = sub.p
FROM (
  SELECT DISTINCT ON (pi.property_id)
    pi.property_id,
    coalesce(nullif(btrim(pi.path), ''), nullif(btrim(pi.file_name), '')) AS p
  FROM public.property_images pi
  WHERE coalesce(nullif(btrim(pi.path), ''), nullif(btrim(pi.file_name), '')) IS NOT NULL
  ORDER BY pi.property_id, pi.sort_order NULLS LAST, pi.id
) sub
WHERE p.id = sub.property_id;

-- ---------------------------------------------------------------------------
-- 8) فهرس للأداء
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_property_images_property_sort
  ON public.property_images (property_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_property_images_property_path_lower
  ON public.property_images (property_id, lower(btrim(coalesce(path, file_name, ''))));

COMMENT ON COLUMN public.property_images.path IS
  'مسار الكائن في دلو property-images (مثال: owner_uuid/file.jpg). المصدر الأساسي للصور في التطبيق.';

COMMIT;

-- =============================================================================
-- (اختياري) توحيق workflow_stage للعقارات المحذوفة — راجع سياساتك قبل التنفيذ
-- =============================================================================
-- UPDATE public.properties
-- SET workflow_stage = coalesce(nullif(btrim(workflow_stage), ''), 'archived')
-- WHERE lower(btrim(status)) = 'deleted';
