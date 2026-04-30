BEGIN;

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS request_public_code text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_market_property_requests_public_code
  ON public.market_property_requests (request_public_code)
  WHERE request_public_code IS NOT NULL
    AND length(trim(request_public_code)) > 0;

CREATE OR REPLACE FUNCTION public.market_property_requests_assign_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
BEGIN
  IF NEW.request_public_code IS NOT NULL
     AND length(trim(NEW.request_public_code)) > 0 THEN
    IF NEW.request_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'request_public_code must be 10 digits';
    END IF;
    RETURN NEW;
  END IF;

  LOOP
    candidate := lpad(
      (floor(random() * 10000000000::double precision))::bigint::text,
      10,
      '0'
    );
    EXIT WHEN NOT EXISTS (
      SELECT 1
      FROM public.market_property_requests r
      WHERE r.request_public_code = candidate
    );
  END LOOP;

  NEW.request_public_code := candidate;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_market_property_requests_public_code
  ON public.market_property_requests;

CREATE TRIGGER tr_market_property_requests_public_code
  BEFORE INSERT ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.market_property_requests_assign_public_code();

DO $$
DECLARE
  r record;
  candidate text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.market_property_requests
    WHERE request_public_code IS NULL
       OR length(trim(request_public_code)) = 0
       OR request_public_code !~ '^[0-9]{10}$'
  LOOP
    LOOP
      candidate := lpad(
        (floor(random() * 10000000000::double precision))::bigint::text,
        10,
        '0'
      );
      EXIT WHEN NOT EXISTS (
        SELECT 1
        FROM public.market_property_requests r2
        WHERE r2.request_public_code = candidate
      );
    END LOOP;

    UPDATE public.market_property_requests
    SET request_public_code = candidate
    WHERE id = r.id;
  END LOOP;
END $$;

ALTER TABLE public.market_property_requests
  DROP CONSTRAINT IF EXISTS chk_market_property_requests_public_code_numeric;

ALTER TABLE public.market_property_requests
  ADD CONSTRAINT chk_market_property_requests_public_code_numeric CHECK (
    request_public_code IS NULL
    OR request_public_code ~ '^[0-9]{10}$'
  );

COMMENT ON COLUMN public.market_property_requests.request_public_code IS
  'رقم تعريف الطلب العقاري العام — 10 أرقام إنجليزية فقط، فريد.';

COMMIT;
