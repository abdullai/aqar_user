-- Prevent identical property and marketing-request publications at the database boundary.
-- This complements the client-side checks and protects against repeated taps,
-- multiple devices, and stale browser state.

CREATE OR REPLACE FUNCTION public.prevent_duplicate_property_publish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF coalesce(NEW.deleted_by_user, false) = false
     AND nullif(btrim(coalesce(NEW.deed_number, '')), '') IS NOT NULL
     AND NEW.deed_date IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.properties p
       WHERE p.id <> coalesce(NEW.id, gen_random_uuid())
         AND p.owner_id = NEW.owner_id
         AND coalesce(p.deleted_by_user, false) = false
         AND nullif(btrim(coalesce(p.deed_number, '')), '') =
             nullif(btrim(coalesce(NEW.deed_number, '')), '')
         AND p.deed_date = NEW.deed_date
         AND lower(btrim(coalesce(p.title, ''))) = lower(btrim(coalesce(NEW.title, '')))
         AND lower(btrim(coalesce(p.city, ''))) = lower(btrim(coalesce(NEW.city, '')))
         AND coalesce(p.price, 0) = coalesce(NEW.price, 0)
         AND coalesce(p.area, 0) = coalesce(NEW.area, 0)
     ) THEN
    RAISE EXCEPTION 'duplicate_listing_content'
      USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_duplicate_property_publish
  ON public.properties;

CREATE TRIGGER prevent_duplicate_property_publish
BEFORE INSERT OR UPDATE OF owner_id, deed_number, deed_date, title, city, price, area
ON public.properties
FOR EACH ROW
EXECUTE FUNCTION public.prevent_duplicate_property_publish();

REVOKE ALL ON FUNCTION public.prevent_duplicate_property_publish() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.prevent_duplicate_listing_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  incoming jsonb := coalesce(NEW.payload_json::jsonb, '{}'::jsonb);
BEGIN
  IF coalesce(NEW.status, '') NOT IN ('cancelled', 'canceled', 'rejected', 'deleted')
     AND nullif(btrim(coalesce(incoming->>'deed_number', '')), '') IS NOT NULL
     AND nullif(btrim(coalesce(incoming->>'deed_date', '')), '') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM public.listing_requests r
       CROSS JOIN LATERAL (SELECT coalesce(r.payload_json::jsonb, '{}'::jsonb) AS data) j
       WHERE r.id <> coalesce(NEW.id, gen_random_uuid())
         AND r.owner_id = NEW.owner_id
         AND coalesce(r.status, '') NOT IN ('cancelled', 'canceled', 'rejected', 'deleted')
         AND btrim(coalesce(j.data->>'deed_number', '')) = btrim(incoming->>'deed_number')
         AND btrim(coalesce(j.data->>'deed_date', '')) = btrim(incoming->>'deed_date')
         AND lower(btrim(coalesce(r.title, ''))) = lower(btrim(coalesce(NEW.title, '')))
         AND lower(btrim(coalesce(r.city, ''))) = lower(btrim(coalesce(NEW.city, '')))
         AND coalesce(r.price, 0) = coalesce(NEW.price, 0)
         AND coalesce(j.data->>'area', '') = coalesce(incoming->>'area', '')
     ) THEN
    RAISE EXCEPTION 'duplicate_listing_content' USING ERRCODE = '23505';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_duplicate_listing_request ON public.listing_requests;
CREATE TRIGGER prevent_duplicate_listing_request
BEFORE INSERT OR UPDATE OF owner_id, payload_json, title, city, price
ON public.listing_requests
FOR EACH ROW EXECUTE FUNCTION public.prevent_duplicate_listing_request();

REVOKE ALL ON FUNCTION public.prevent_duplicate_listing_request() FROM PUBLIC;
