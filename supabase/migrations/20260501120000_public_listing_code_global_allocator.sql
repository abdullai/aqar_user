-- تخصيص موحّد لرقم العرض العام (10 أرقام) عبر:
--   properties.listing_public_code
--   listing_requests.listing_request_public_code
--   market_property_requests.request_public_code
-- + جدول نحيف public_listing_code_retirements عند الحذف (لا إعادة استخدام الرقم).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) سجل إنهاء الرقم العام — صف عند الحذف فقط (بحث إداري لاحقاً)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.public_listing_code_retirements (
  public_code text NOT NULL,
  entity_kind text NOT NULL,
  entity_id uuid NOT NULL,
  outcome text NOT NULL DEFAULT 'deleted',
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT public_listing_code_retirements_code_key UNIQUE (public_code),
  CONSTRAINT public_listing_code_retirements_code_format CHECK (
    public_code ~ '^[0-9]{10}$'
  ),
  CONSTRAINT public_listing_code_retirements_entity_kind CHECK (
    entity_kind = ANY (
      ARRAY[
        'listing_request'::text,
        'property'::text,
        'market_property_request'::text
      ]
    )
  ),
  CONSTRAINT public_listing_code_retirements_outcome CHECK (
    length(trim(outcome)) > 0
  )
);

CREATE INDEX IF NOT EXISTS idx_public_listing_code_retirements_occurred
  ON public.public_listing_code_retirements (occurred_at DESC);

COMMENT ON TABLE public.public_listing_code_retirements IS
  'سجل نحيف: رقم العرض العام لم يعد مستخدماً (حذف/إنهاء). يمنع إعادة تخصيص نفس الرقم.';

ALTER TABLE public.public_listing_code_retirements ENABLE ROW LEVEL SECURITY;

-- PostgREST: لا وصول افتراضي للمستخدمين — الإدارة لاحقاً عبر سياسة أو service_role.
REVOKE ALL ON public.public_listing_code_retirements FROM PUBLIC;
GRANT SELECT ON public.public_listing_code_retirements TO service_role;

-- ---------------------------------------------------------------------------
-- 2) هل الرقم مستخدم حالياً أو متقاعد؟
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.public_listing_code_is_taken(p_code text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.listing_public_code = p_code
  )
  OR EXISTS (
    SELECT 1
    FROM public.listing_requests lr
    WHERE lr.listing_request_public_code = p_code
  )
  OR EXISTS (
    SELECT 1
    FROM public.market_property_requests m
    WHERE m.request_public_code = p_code
  )
  OR EXISTS (
    SELECT 1
    FROM public.public_listing_code_retirements r
    WHERE r.public_code = p_code
  );
$$;

COMMENT ON FUNCTION public.public_listing_code_is_taken(text) IS
  'true إذا ظهر الرقم في أي جدول نشطة أو في سجل الإنهاء (لا يُعاد تخصيصه).';

-- ---------------------------------------------------------------------------
-- 3) تخصيص رقم جديد فريد عالمياً (عشوائي 10 خانات مع فحص الاتحاد)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.allocate_public_listing_code_10d()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  candidate text;
  attempts int := 0;
BEGIN
  LOOP
    attempts := attempts + 1;
    IF attempts > 5000 THEN
      RAISE EXCEPTION 'allocate_public_listing_code_10d: too many attempts';
    END IF;
    candidate := lpad(
      (floor(random() * 10000000000::double precision))::bigint::text,
      10,
      '0'
    );
    EXIT WHEN NOT public.public_listing_code_is_taken(candidate);
  END LOOP;
  RETURN candidate;
END;
$$;

COMMENT ON FUNCTION public.allocate_public_listing_code_10d() IS
  'يولّد 10 أرقام غير مستخدمة في properties + listing_requests + market_property_requests + retirements.';

-- ---------------------------------------------------------------------------
-- 4) تحديث تريغرات الإدراج الثلاثة لاستخدام المخصص الموحّد
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listing_requests_assign_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.listing_request_public_code IS NOT NULL
     AND length(trim(NEW.listing_request_public_code)) > 0 THEN
    IF NEW.listing_request_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'listing_request_public_code must be 10 digits';
    END IF;
    RETURN NEW;
  END IF;

  NEW.listing_request_public_code := public.allocate_public_listing_code_10d();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.market_property_requests_assign_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.request_public_code IS NOT NULL
     AND length(trim(NEW.request_public_code)) > 0 THEN
    IF NEW.request_public_code !~ '^[0-9]{10}$' THEN
      RAISE EXCEPTION 'request_public_code must be 10 digits';
    END IF;
    RETURN NEW;
  END IF;

  NEW.request_public_code := public.allocate_public_listing_code_10d();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.properties_assign_listing_public_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
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

  NEW.listing_public_code := public.allocate_public_listing_code_10d();
  RETURN NEW;
END;
$$;

COMMENT ON COLUMN public.listing_requests.listing_request_public_code IS
  'رقم عرض عام — 10 أرقام؛ فريد عالمياً مع properties و market_property_requests.';

COMMENT ON COLUMN public.market_property_requests.request_public_code IS
  'رقم عرض عام — 10 أرقام؛ فريد عالمياً مع properties و listing_requests.';

COMMENT ON COLUMN public.properties.listing_public_code IS
  'رقم عرض عام — 10 أرقام؛ فريد عالمياً؛ يُنسخ من طلب التسويق عند request_id إن وُجد.';

-- ---------------------------------------------------------------------------
-- 5) قبل الحذف: تسجيل الرقم في جدول الإنهاء (منع إعادة الاستخدام + أثر إداري)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_retire_public_code_listing_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c text;
BEGIN
  c := trim(coalesce(OLD.listing_request_public_code, ''));
  IF c ~ '^[0-9]{10}$' THEN
    INSERT INTO public.public_listing_code_retirements (
      public_code,
      entity_kind,
      entity_id,
      outcome
    )
    VALUES (c, 'listing_request', OLD.id, 'deleted')
    ON CONFLICT (public_code) DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_retire_public_code_property()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c text;
BEGIN
  c := trim(coalesce(OLD.listing_public_code, ''));
  IF c ~ '^[0-9]{10}$' THEN
    INSERT INTO public.public_listing_code_retirements (
      public_code,
      entity_kind,
      entity_id,
      outcome
    )
    VALUES (c, 'property', OLD.id, 'deleted')
    ON CONFLICT (public_code) DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_retire_public_code_market_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c text;
BEGIN
  c := trim(coalesce(OLD.request_public_code, ''));
  IF c ~ '^[0-9]{10}$' THEN
    INSERT INTO public.public_listing_code_retirements (
      public_code,
      entity_kind,
      entity_id,
      outcome
    )
    VALUES (c, 'market_property_request', OLD.id, 'deleted')
    ON CONFLICT (public_code) DO NOTHING;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS tr_listing_requests_public_code_retire
  ON public.listing_requests;
CREATE TRIGGER tr_listing_requests_public_code_retire
  BEFORE DELETE ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_retire_public_code_listing_request();

DROP TRIGGER IF EXISTS tr_properties_public_code_retire ON public.properties;
CREATE TRIGGER tr_properties_public_code_retire
  BEFORE DELETE ON public.properties
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_retire_public_code_property();

DROP TRIGGER IF EXISTS tr_market_property_requests_public_code_retire
  ON public.market_property_requests;
CREATE TRIGGER tr_market_property_requests_public_code_retire
  BEFORE DELETE ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_retire_public_code_market_request();

COMMIT;
