-- =============================================================================
-- Normalize listing_requests payload fields for legacy rows
-- Fixes rows where payload_json/payload is a JSON *string* that contains
-- another JSON object (double-encoded).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._jsonb_loose_to_object(v jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s text;
  d jsonb;
BEGIN
  IF v IS NULL THEN
    RETURN NULL;
  END IF;

  IF jsonb_typeof(v) = 'object' THEN
    RETURN v;
  END IF;

  IF jsonb_typeof(v) = 'string' THEN
    s := v #>> '{}';
    BEGIN
      d := s::jsonb;
      IF jsonb_typeof(d) = 'object' THEN
        RETURN d;
      END IF;
    EXCEPTION
      WHEN others THEN
        RETURN NULL;
    END;
  END IF;

  RETURN NULL;
END;
$$;

UPDATE public.listing_requests r
SET
  payload_json = coalesce(
    public._jsonb_loose_to_object(r.payload_json),
    r.payload_json
  ),
  payload = coalesce(
    public._jsonb_loose_to_object(r.payload),
    r.payload
  ),
  updated_at = now()
WHERE (
    r.payload_json IS NOT NULL
    AND jsonb_typeof(r.payload_json) = 'string'
  )
   OR (
    r.payload IS NOT NULL
    AND jsonb_typeof(r.payload) = 'string'
  );

COMMIT;

