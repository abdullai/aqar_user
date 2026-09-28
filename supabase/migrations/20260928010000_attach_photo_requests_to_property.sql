BEGIN;

UPDATE public.photo_shoot_requests r
SET property_id = lr.preview_property_id,
    property_owner_id = coalesce(r.property_owner_id, p.owner_id),
    updated_at = now()
FROM public.listing_requests lr
JOIN public.properties p ON p.id = lr.preview_property_id
WHERE r.listing_request_id = lr.id
  AND r.property_id IS NULL;

CREATE OR REPLACE FUNCTION public.attach_photo_shoot_requests_to_property()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
DECLARE
  v_request_id uuid;
  v_status text;
BEGIN
  IF NEW.request_id IS NULL THEN RETURN NEW; END IF;

  UPDATE public.photo_shoot_requests
  SET property_id = NEW.id,
      property_owner_id = coalesce(property_owner_id, NEW.owner_id),
      updated_at = now()
  WHERE listing_request_id = NEW.request_id
    AND property_id IS NULL;

  SELECT id, status
    INTO v_request_id, v_status
  FROM public.photo_shoot_requests
  WHERE listing_request_id = NEW.request_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_request_id IS NOT NULL THEN
    UPDATE public.properties
    SET listing_guidance = jsonb_set(
      jsonb_set(
        coalesce(listing_guidance, '{}'::jsonb),
        '{photo_shoot_request_id}',
        to_jsonb(v_request_id),
        true
      ),
      '{photo_shoot_status}',
      to_jsonb(coalesce(v_status, 'open')),
      true
    )
    WHERE id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_attach_bundled_photo_shoot_to_property
  ON public.properties;
DROP TRIGGER IF EXISTS tr_attach_photo_shoot_requests_to_property
  ON public.properties;
CREATE TRIGGER tr_attach_photo_shoot_requests_to_property
  AFTER INSERT OR UPDATE OF request_id ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.attach_photo_shoot_requests_to_property();

REVOKE ALL ON FUNCTION public.attach_photo_shoot_requests_to_property()
  FROM PUBLIC, anon, authenticated;

COMMIT;