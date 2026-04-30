-- =============================================================================
-- طلبات التسويق (listing_requests): إقرار تنظيمي للمالك
--
-- المنطق:
--   • الطلبات الجديدة: لا تحتاج خطوة يدوية — owner_regulatory_ack_at يُضبط تلقائياً
--     (محفّز BEFORE INSERT + التطبيق يرسل القيمة عند الإنشاء).
--   • الطلبات الأقدم من LEGACY_CUTOFF: تبقى owner_regulatory_ack_at = NULL حتى يؤكد
--     المالك عبر RPC listing_request_owner_ack_regulatory (مرة واحدة).
--
-- عدّل LEGACY_CUTOFF في سطر UPDATE أدناه لتاريخ يناسب منصتك.
-- =============================================================================

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS owner_regulatory_ack_at timestamptz;

COMMENT ON COLUMN public.listing_requests.owner_regulatory_ack_at IS
  'وقت إقرار المالك التنظيمي للطلب؛ NULL للطلبات القديمة حتى يُكمّل المالك الإقرار.';

-- كل طلب أُنشئ من/بعد هذا التاريخ يُعتبر مؤكّداً تلقائياً (لا حاجة لخطوة إضافية).
UPDATE public.listing_requests lr
SET owner_regulatory_ack_at = now()
WHERE lr.owner_regulatory_ack_at IS NULL
  AND lr.created_at >= timestamptz '2026-04-01 00:00:00+00';

CREATE OR REPLACE FUNCTION public.listing_requests_owner_ack_default_bi()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.owner_regulatory_ack_at IS NULL THEN
    NEW.owner_regulatory_ack_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_listing_requests_owner_ack_default ON public.listing_requests;
CREATE TRIGGER tr_listing_requests_owner_ack_default
  BEFORE INSERT ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.listing_requests_owner_ack_default_bi();

CREATE OR REPLACE FUNCTION public.listing_request_owner_ack_regulatory(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  UPDATE public.listing_requests lr
  SET owner_regulatory_ack_at = now(),
      updated_at = now()
  WHERE lr.id = p_request_id
    AND lr.owner_id = auth.uid();

  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RAISE EXCEPTION 'not_found_or_forbidden';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.listing_request_owner_ack_regulatory(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listing_request_owner_ack_regulatory(uuid) TO authenticated;

COMMENT ON FUNCTION public.listing_request_owner_ack_regulatory(uuid) IS
  'يضبط إقرار المالك التنظيمي لطلب تسويق قديم؛ يتحقق من owner_id = auth.uid().';
