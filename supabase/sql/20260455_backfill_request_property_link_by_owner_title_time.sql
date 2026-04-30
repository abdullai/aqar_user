-- =============================================================================
-- Backfill links between listing_requests and properties for legacy rows
-- Strategy (conservative):
--   1) match by same owner + normalized title + close creation time window
--   2) set listing_requests.preview_property_id
--   3) set properties.request_id when empty
-- NOTE:
--   This migration does NOT create new properties; it only links existing rows.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Helper: normalize title text (Arabic and English friendly)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._norm_title_for_linking(txt text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
           lower(
             replace(
               replace(
                 replace(
                   replace(
                     replace(coalesce(trim(txt), ''), 'أ', 'ا'),
                   'إ', 'ا'),
                 'آ', 'ا'),
               'ة', 'ه'),
             'ى', 'ي')
           ),
           '\s+',
           '',
           'g'
         );
$$;

-- ---------------------------------------------------------------------------
-- A) Diagnostic preview (safe): requests missing preview link + best candidate
-- ---------------------------------------------------------------------------
-- To inspect before/after:
-- WITH req AS (
--   SELECT r.id, r.owner_id, r.title, r.created_at
--   FROM public.listing_requests r
--   WHERE r.preview_property_id IS NULL
-- ),
-- cand AS (
--   SELECT
--     req.id AS request_id,
--     p.id   AS property_id,
--     req.title AS request_title,
--     p.title   AS property_title,
--     abs(extract(epoch from (p.created_at - req.created_at))) AS sec_gap,
--     row_number() OVER (
--       PARTITION BY req.id
--       ORDER BY abs(extract(epoch from (p.created_at - req.created_at))) ASC
--     ) AS rn
--   FROM req
--   JOIN public.properties p
--     ON p.owner_id = req.owner_id
--    AND public._norm_title_for_linking(p.title) =
--        public._norm_title_for_linking(req.title)
--    AND p.request_id IS NULL
--    AND p.created_at BETWEEN req.created_at - interval '30 days'
--                         AND req.created_at + interval '30 days'
-- )
-- SELECT *
-- FROM cand
-- WHERE rn = 1
-- ORDER BY sec_gap ASC, request_id;

-- ---------------------------------------------------------------------------
-- B) Apply linking by conservative best candidate
-- ---------------------------------------------------------------------------
WITH req AS (
  SELECT r.id, r.owner_id, r.title, r.created_at
  FROM public.listing_requests r
  WHERE r.preview_property_id IS NULL
),
cand AS (
  SELECT
    req.id AS request_id,
    p.id   AS property_id,
    abs(extract(epoch from (p.created_at - req.created_at))) AS sec_gap,
    row_number() OVER (
      PARTITION BY req.id
      ORDER BY abs(extract(epoch from (p.created_at - req.created_at))) ASC
    ) AS rn
  FROM req
  JOIN public.properties p
    ON p.owner_id = req.owner_id
   AND public._norm_title_for_linking(p.title) =
       public._norm_title_for_linking(req.title)
   AND p.request_id IS NULL
   AND p.created_at BETWEEN req.created_at - interval '30 days'
                        AND req.created_at + interval '30 days'
),
best AS (
  SELECT request_id, property_id
  FROM cand
  WHERE rn = 1
)
UPDATE public.listing_requests r
SET
  preview_property_id = b.property_id,
  updated_at = now()
FROM best b
WHERE r.id = b.request_id
  AND r.preview_property_id IS NULL;

-- Also write back reverse FK when empty.
WITH req_linked AS (
  SELECT r.id AS request_id, r.preview_property_id AS property_id
  FROM public.listing_requests r
  WHERE r.preview_property_id IS NOT NULL
),
to_upd AS (
  SELECT rl.request_id, rl.property_id
  FROM req_linked rl
  JOIN public.properties p ON p.id = rl.property_id
  WHERE p.request_id IS NULL
)
UPDATE public.properties p
SET
  request_id = u.request_id,
  updated_at = now()
FROM to_upd u
WHERE p.id = u.property_id
  AND p.request_id IS NULL;

COMMIT;

