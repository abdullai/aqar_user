BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_property_edit_ticket_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_property_id text;
  v_count integer;
BEGIN
  IF coalesce(NEW.details->>'ticket_category', '') <> 'property_edit_request' THEN
    RETURN NEW;
  END IF;

  v_property_id := trim(coalesce(NEW.details->>'property_id', ''));
  IF v_property_id = '' OR NEW.user_id IS NULL THEN
    RAISE EXCEPTION 'property_edit_request_invalid';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(NEW.user_id::text || ':' || v_property_id, 0)
  );

  SELECT count(*)::integer
  INTO v_count
  FROM public.regc_user_complaints c
  WHERE c.user_id = NEW.user_id
    AND c.details->>'ticket_category' = 'property_edit_request'
    AND c.details->>'property_id' = v_property_id;

  IF v_count >= 3 THEN
    RAISE EXCEPTION 'property_edit_request_limit_reached';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS regc_property_edit_ticket_limit
  ON public.regc_user_complaints;
CREATE TRIGGER regc_property_edit_ticket_limit
BEFORE INSERT ON public.regc_user_complaints
FOR EACH ROW
EXECUTE FUNCTION public.enforce_property_edit_ticket_limit();

COMMIT;