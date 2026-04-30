-- =============================================================================
-- Keep listing_requests.preview_property_id synced automatically
-- + ready-to-run diagnostics for missing card media/details
-- =============================================================================

BEGIN;

-- 1) Auto-sync preview_property_id from properties.request_id on insert/update.
CREATE OR REPLACE FUNCTION public.sync_listing_request_preview_property_id()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.request_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.listing_requests r
  SET
    preview_property_id = NEW.id,
    updated_at = now()
  WHERE r.id = NEW.request_id
    AND (
      r.preview_property_id IS NULL
      OR r.preview_property_id = NEW.id
      OR (
        EXISTS (
          SELECT 1
          FROM public.properties p_old
          WHERE p_old.id = r.preview_property_id
            AND p_old.request_id = NEW.request_id
            AND coalesce(p_old.created_at, now()) <= coalesce(NEW.created_at, now())
        )
      )
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_listing_request_preview_property_id
  ON public.properties;

CREATE TRIGGER trg_sync_listing_request_preview_property_id
AFTER INSERT OR UPDATE OF request_id, created_at
ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.sync_listing_request_preview_property_id();

COMMIT;

-- =============================================================================
-- Diagnostics (run each SELECT manually when needed)
-- =============================================================================

-- A) Requests still missing preview-property link:
-- select id, owner_id, title, status, workflow_stage, created_at
-- from public.listing_requests
-- where preview_property_id is null
-- order by created_at desc;

-- B) Requests that have linked property but no image rows:
-- select
--   r.id as request_id,
--   r.preview_property_id,
--   p.title,
--   p.status,
--   p.workflow_stage
-- from public.listing_requests r
-- join public.properties p on p.id = r.preview_property_id
-- left join public.property_images pi on pi.property_id = p.id
-- group by r.id, r.preview_property_id, p.title, p.status, p.workflow_stage
-- having count(pi.*) = 0
-- order by r.id desc;

-- C) Requests/cards missing both image and video in payload:
-- select
--   r.id as request_id,
--   r.title,
--   r.preview_property_id,
--   coalesce(r.payload_json, r.payload)::text as payload_text
-- from public.listing_requests r
-- where (
--   coalesce(r.payload_json, r.payload)::jsonb ->> 'request_video_path' is null
--   and coalesce(r.payload_json, r.payload)::jsonb ->> 'video_url' is null
--   and coalesce(r.payload_json, r.payload)::jsonb ->> 'cover_image' is null
-- )
-- order by r.created_at desc;

