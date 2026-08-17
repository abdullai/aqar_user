-- رمز إعلان عام فريد لكل عقار (عرض في البطاقة والتفاصيل)
-- طبّق على قاعدة Supabase بعد مراجعة المخطط.

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS listing_public_code text;

CREATE UNIQUE INDEX IF NOT EXISTS uq_properties_listing_public_code
  ON public.properties (listing_public_code)
  WHERE listing_public_code IS NOT NULL AND length(trim(listing_public_code)) > 0;

CREATE OR REPLACE FUNCTION public.properties_assign_listing_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
BEGIN
  IF NEW.listing_public_code IS NOT NULL AND length(trim(NEW.listing_public_code)) > 0 THEN
    RETURN NEW;
  END IF;

  LOOP
    candidate := 'AQ' || upper(substr(md5(random()::text || clock_timestamp()::text || NEW.id::text), 1, 10));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.listing_public_code = candidate
    );
  END LOOP;

  NEW.listing_public_code := candidate;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_properties_listing_public_code ON public.properties;
CREATE TRIGGER tr_properties_listing_public_code
  BEFORE INSERT ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.properties_assign_listing_public_code();

-- تعبئة السجلات القديمة
DO $$
DECLARE
  r record;
  candidate text;
BEGIN
  FOR r IN
    SELECT id FROM public.properties
    WHERE listing_public_code IS NULL OR length(trim(listing_public_code)) = 0
  LOOP
    LOOP
      candidate := 'AQ' || upper(substr(md5(random()::text || clock_timestamp()::text || r.id::text), 1, 10));
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.properties p
        WHERE p.listing_public_code = candidate
      );
    END LOOP;

    UPDATE public.properties
    SET listing_public_code = candidate
    WHERE id = r.id;
  END LOOP;
END $$;
