-- رقم عام 10 أرقام لطلبات التسويق listing_requests + نسخه تلقائياً لـ properties.listing_public_code
-- عند إنشاء عقار مرتبط بـ request_id (نفس الرقم من الطلب حتى النشر).

BEGIN;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS listing_request_public_code text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_listing_requests_public_code
  ON public.listing_requests (listing_request_public_code)
  WHERE listing_request_public_code IS NOT NULL
    AND length(trim(listing_request_public_code)) > 0;

CREATE OR REPLACE FUNCTION public.listing_requests_assign_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
BEGIN
  IF NEW.listing_request_public_code IS NOT NULL
     AND length(trim(NEW.listing_request_public_code)) > 0 THEN
    IF NEW.listing_request_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'listing_request_public_code must be 10 digits';
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
      FROM public.listing_requests lr
      WHERE lr.listing_request_public_code = candidate
    );
  END LOOP;

  NEW.listing_request_public_code := candidate;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_listing_requests_public_code
  ON public.listing_requests;

CREATE TRIGGER tr_listing_requests_public_code
  BEFORE INSERT ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.listing_requests_assign_public_code();

DO $$
DECLARE
  r record;
  candidate text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.listing_requests
    WHERE listing_request_public_code IS NULL
       OR length(trim(listing_request_public_code)) = 0
       OR listing_request_public_code !~ '^[0-9]{10}$'
  LOOP
    LOOP
      candidate := lpad(
        (floor(random() * 10000000000::double precision))::bigint::text,
        10,
        '0'
      );
      EXIT WHEN NOT EXISTS (
        SELECT 1
        FROM public.listing_requests lr2
        WHERE lr2.listing_request_public_code = candidate
      );
    END LOOP;

    UPDATE public.listing_requests
    SET listing_request_public_code = candidate
    WHERE id = r.id;
  END LOOP;
END $$;

ALTER TABLE public.listing_requests
  DROP CONSTRAINT IF EXISTS chk_listing_requests_public_code_numeric;

ALTER TABLE public.listing_requests
  ADD CONSTRAINT chk_listing_requests_public_code_numeric CHECK (
    listing_request_public_code IS NULL
    OR listing_request_public_code ~ '^[0-9]{10}$'
  );

COMMENT ON COLUMN public.listing_requests.listing_request_public_code IS
  'رقم تعريف طلب التسويق العام — 10 أرقام إنجليزية فقط، فريد ضمن listing_requests.';

-- عند إدراج عقار بـ request_id: استخدم رقم الطلب إن وُجد (موحّد مع بطاقة الطلب).
CREATE OR REPLACE FUNCTION public.properties_assign_listing_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
  from_request text;
BEGIN
  IF NEW.listing_public_code IS NOT NULL AND length(trim(NEW.listing_public_code)) > 0 THEN
    IF NEW.listing_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'listing_public_code must be 10 digits';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.request_id IS NOT NULL THEN
    SELECT lr.listing_request_public_code
      INTO from_request
    FROM public.listing_requests lr
    WHERE lr.id = NEW.request_id;

    IF from_request IS NOT NULL
       AND length(trim(from_request)) > 0
       AND from_request ~ '^[0-9]{10}$' THEN
      NEW.listing_public_code := from_request;
      RETURN NEW;
    END IF;
  END IF;

  LOOP
    candidate := lpad((floor(random() * 10000000000::double precision))::bigint::text, 10, '0');
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.listing_public_code = candidate
    );
  END LOOP;

  NEW.listing_public_code := candidate;
  RETURN NEW;
END;
$$;

COMMIT;
