-- =============================================================================
-- 2026-06-02 — Pricing backfill + bi-directional JSONB <-> columns sync (v10)
-- =============================================================================
-- بعد ترحيل v9 (الذي أضاف الأعمدة المخصّصة للضريبة والعمولة)، هذا الترحيل يقوم بـ:
--
--   (A) Backfill ذكي للإعلانات الموجودة في قاعدة البيانات (المنشورة وغير المنشورة):
--       — إن كانت قد حُفظت قيم فوترة سابقاً داخل listing_guidance->'pricing'
--         (مثلاً نتيجة تعديل من نسخة Flutter حديثة قبل إضافة الأعمدة)، نقل تلك
--         القيم إلى الأعمدة المخصّصة الجديدة (price_includes_vat، vat_rate،
--         marketing_commission_kind، marketing_commission_rate،
--         marketing_commission_amount).
--       — الإعلانات التي ليس لديها أي pricing في JSONB تبقى على القيم الافتراضية
--         الآمنة (شامل ضريبة 5%، بدون عمولة) — والمالك يستطيع تعديلها لاحقاً عبر
--         زر «تعديل الإعلان» الذي يُعيد طرح السؤالين.
--
--   (B) Trigger مزدوج الاتجاه على properties و listing_requests:
--       — اتجاه JSONB → الأعمدة (على INSERT فقط، عندما تكون الأعمدة عند قيمها
--         الافتراضية وlisting_guidance->'pricing' يحتوي قيماً واضحة): مفيد عندما
--         يستخدم العميل واجهة قديمة لا تعرف بالأعمدة الجديدة، أو ينسخ صفوفاً.
--       — اتجاه الأعمدة → JSONB (دائماً): يُبقي listing_guidance.pricing مرآةً
--         محدّثة لقيم الأعمدة لاستخدامها كنسخة احتياطية ولقراءة آمنة من العميل
--         القديم أو من تقارير لا تعتمد على الأعمدة الجديدة.
--
--   (C) دالة عامة public.fn_resync_listing_pricing(...) تُستخدم لإعادة المزامنة
--       اليدوية لصف واحد عند الحاجة (للديباغ أو الإصلاح).
--
-- ✅ الترحيل idempotent — يمكن إعادة تشغيله دون أن يكسر شيئاً.
-- ✅ آمن مع RLS — لا يغيّر السياسات. يستخدم BEFORE trigger داخل المعاملة الحالية.
-- ✅ متوافق مع الإعلانات القديمة — لا يغير المبالغ المعروضة للعملاء الحاليين.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (A) Backfill: نقل القيم من listing_guidance.pricing إلى الأعمدة الجديدة.
-- ---------------------------------------------------------------------------
--   مفيد للإعلانات (drafts أو منشورة) التي حُفظت من نسخة Flutter جديدة قبل أن
--   تُضاف الأعمدة الفعلية (احتمال نادر لكن وارد عند ترحيلات على مراحل).
--   الفلتر يضمن أن لا نلمس صفوفاً ليس لديها أي pricing في JSONB.

UPDATE public.properties
SET
  price_includes_vat = CASE
    WHEN jsonb_typeof(listing_guidance->'pricing'->'price_includes_vat') = 'boolean'
      THEN (listing_guidance->'pricing'->>'price_includes_vat')::boolean
    ELSE price_includes_vat
  END,
  vat_rate = CASE
    WHEN (listing_guidance->'pricing'->>'vat_rate') ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN GREATEST(0::numeric,
             LEAST(0.5000::numeric,
                   (listing_guidance->'pricing'->>'vat_rate')::numeric))
    ELSE vat_rate
  END,
  marketing_commission_kind = CASE
    WHEN (listing_guidance->'pricing'->>'marketing_commission_kind')
         IN ('none','percent','fixed')
      THEN listing_guidance->'pricing'->>'marketing_commission_kind'
    ELSE marketing_commission_kind
  END,
  marketing_commission_rate = CASE
    WHEN (listing_guidance->'pricing'->>'marketing_commission_rate')
         ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN GREATEST(0::numeric,
             LEAST(0.2500::numeric,
                   (listing_guidance->'pricing'->>'marketing_commission_rate')::numeric))
    ELSE marketing_commission_rate
  END,
  marketing_commission_amount = CASE
    WHEN (listing_guidance->'pricing'->>'marketing_commission_amount')
         ~ '^-?[0-9]+(\.[0-9]+)?$'
      THEN GREATEST(0::numeric,
                    (listing_guidance->'pricing'->>'marketing_commission_amount')::numeric)
    ELSE marketing_commission_amount
  END,
  default_cover_used = CASE
    WHEN jsonb_typeof(listing_guidance->'media'->'used_default_cover') = 'boolean'
      THEN (listing_guidance->'media'->>'used_default_cover')::boolean
    ELSE default_cover_used
  END
WHERE listing_guidance IS NOT NULL
  AND jsonb_typeof(listing_guidance) = 'object'
  AND (
    jsonb_typeof(listing_guidance->'pricing') = 'object'
    OR jsonb_typeof(listing_guidance->'media') = 'object'
  );


-- نفس الـ backfill على listing_requests إذا وُجِد لديها listing_guidance.
DO $req_backfill$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'listing_requests'
      AND column_name  = 'listing_guidance'
  ) THEN
    UPDATE public.listing_requests
    SET
      price_includes_vat = CASE
        WHEN jsonb_typeof(listing_guidance->'pricing'->'price_includes_vat') = 'boolean'
          THEN (listing_guidance->'pricing'->>'price_includes_vat')::boolean
        ELSE price_includes_vat
      END,
      vat_rate = CASE
        WHEN (listing_guidance->'pricing'->>'vat_rate') ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN GREATEST(0::numeric,
                 LEAST(0.5000::numeric,
                       (listing_guidance->'pricing'->>'vat_rate')::numeric))
        ELSE vat_rate
      END,
      marketing_commission_kind = CASE
        WHEN (listing_guidance->'pricing'->>'marketing_commission_kind')
             IN ('none','percent','fixed')
          THEN listing_guidance->'pricing'->>'marketing_commission_kind'
        ELSE marketing_commission_kind
      END,
      marketing_commission_rate = CASE
        WHEN (listing_guidance->'pricing'->>'marketing_commission_rate')
             ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN GREATEST(0::numeric,
                 LEAST(0.2500::numeric,
                       (listing_guidance->'pricing'->>'marketing_commission_rate')::numeric))
        ELSE marketing_commission_rate
      END,
      marketing_commission_amount = CASE
        WHEN (listing_guidance->'pricing'->>'marketing_commission_amount')
             ~ '^-?[0-9]+(\.[0-9]+)?$'
          THEN GREATEST(0::numeric,
                        (listing_guidance->'pricing'->>'marketing_commission_amount')::numeric)
        ELSE marketing_commission_amount
      END,
      default_cover_used = CASE
        WHEN jsonb_typeof(listing_guidance->'media'->'used_default_cover') = 'boolean'
          THEN (listing_guidance->'media'->>'used_default_cover')::boolean
        ELSE default_cover_used
      END
    WHERE listing_guidance IS NOT NULL
      AND jsonb_typeof(listing_guidance) = 'object'
      AND (
        jsonb_typeof(listing_guidance->'pricing') = 'object'
        OR jsonb_typeof(listing_guidance->'media') = 'object'
      );
  END IF;
END
$req_backfill$;


-- ---------------------------------------------------------------------------
-- (B) Trigger: مزامنة JSONB <-> الأعمدة المخصّصة على كل INSERT/UPDATE.
-- ---------------------------------------------------------------------------
--
-- آلية العمل (للقراءة قبل أي تعديل لاحق):
--   1. على INSERT: إن كانت الأعمدة المخصّصة عند قيمها الافتراضية
--      (true / 0.05 / 'none' / 0.025 / 0) ووُجِد في listing_guidance->'pricing'
--      مفتاح صحيح لها → نقرأ القيمة من JSONB ونملأ العمود. هذا يحفظ التوافق
--      مع أي عميل قديم لا يعرف الأعمدة الجديدة.
--   2. على INSERT/UPDATE معاً: نُحدِّث listing_guidance->'pricing' دائماً
--      ليعكس قيم الأعمدة الحالية، مع إضافة طابع زمني synced_at للتدقيق.
--
-- بهذا تكون لدينا قيم محفوظة في مكانين دائماً:
--   - الأعمدة المخصّصة (مصدر الحقيقة الأساسي للاستعلامات والتقارير).
--   - listing_guidance.pricing (نسخة احتياطية + قراءة العميل القديم).
--
CREATE OR REPLACE FUNCTION public.fn_listing_pricing_sync()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  pricing  jsonb := COALESCE(NEW.listing_guidance->'pricing', '{}'::jsonb);
  media    jsonb := COALESCE(NEW.listing_guidance->'media',   '{}'::jsonb);
  new_guidance jsonb;
BEGIN
  -- (1) JSONB → الأعمدة (على INSERT فقط، وعندما تكون الأعمدة عند قيمها الافتراضية)
  IF TG_OP = 'INSERT' AND jsonb_typeof(pricing) = 'object' THEN
    -- price_includes_vat (افتراضي true)
    IF NEW.price_includes_vat IS NOT DISTINCT FROM TRUE
       AND jsonb_typeof(pricing->'price_includes_vat') = 'boolean' THEN
      NEW.price_includes_vat := (pricing->>'price_includes_vat')::boolean;
    END IF;

    -- vat_rate (افتراضي 0.05)
    IF NEW.vat_rate IS NOT DISTINCT FROM 0.0500::numeric
       AND (pricing->>'vat_rate') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      NEW.vat_rate := GREATEST(0::numeric,
                        LEAST(0.5000::numeric,
                              (pricing->>'vat_rate')::numeric));
    END IF;

    -- marketing_commission_kind (افتراضي 'none')
    IF NEW.marketing_commission_kind IS NOT DISTINCT FROM 'none'
       AND (pricing->>'marketing_commission_kind')
           IN ('none','percent','fixed') THEN
      NEW.marketing_commission_kind := pricing->>'marketing_commission_kind';
    END IF;

    -- marketing_commission_rate (افتراضي 0.025)
    IF NEW.marketing_commission_rate IS NOT DISTINCT FROM 0.0250::numeric
       AND (pricing->>'marketing_commission_rate') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      NEW.marketing_commission_rate := GREATEST(0::numeric,
                                         LEAST(0.2500::numeric,
                                               (pricing->>'marketing_commission_rate')::numeric));
    END IF;

    -- marketing_commission_amount (افتراضي 0)
    IF NEW.marketing_commission_amount IS NOT DISTINCT FROM 0::numeric
       AND (pricing->>'marketing_commission_amount') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN
      NEW.marketing_commission_amount := GREATEST(0::numeric,
                                                  (pricing->>'marketing_commission_amount')::numeric);
    END IF;

    -- default_cover_used من media.used_default_cover إن وُجد
    IF NEW.default_cover_used IS NOT DISTINCT FROM FALSE
       AND jsonb_typeof(media->'used_default_cover') = 'boolean' THEN
      NEW.default_cover_used := (media->>'used_default_cover')::boolean;
    END IF;
  END IF;

  -- (2) الأعمدة → JSONB (دائماً، نسخة احتياطية)
  new_guidance := COALESCE(NEW.listing_guidance, '{}'::jsonb);
  new_guidance := jsonb_set(
    new_guidance,
    '{pricing}',
    COALESCE(new_guidance->'pricing', '{}'::jsonb)
      || jsonb_build_object(
        'price_includes_vat',         NEW.price_includes_vat,
        'vat_rate',                   NEW.vat_rate,
        'marketing_commission_kind',  NEW.marketing_commission_kind,
        'marketing_commission_rate',  NEW.marketing_commission_rate,
        'marketing_commission_amount',NEW.marketing_commission_amount,
        'synced_at',                  to_jsonb(now()::text)
      ),
    true
  );
  new_guidance := jsonb_set(
    new_guidance,
    '{media}',
    COALESCE(new_guidance->'media', '{}'::jsonb)
      || jsonb_build_object(
        'used_default_cover', NEW.default_cover_used
      ),
    true
  );
  NEW.listing_guidance := new_guidance;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_listing_pricing_sync() IS
  'Bi-directional sync between dedicated pricing columns and listing_guidance.pricing JSONB backup.';


-- ربط الـ trigger بـ properties (مع تحقّق دفاعي من وجود الأعمدة المخصّصة).
DO $prop_trigger$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'properties'
      AND column_name  = 'listing_guidance'
  )
  AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'properties'
      AND column_name  = 'price_includes_vat'
  ) THEN
    DROP TRIGGER IF EXISTS trg_properties_pricing_sync ON public.properties;
    CREATE TRIGGER trg_properties_pricing_sync
    BEFORE INSERT OR UPDATE ON public.properties
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_listing_pricing_sync();
  END IF;
END
$prop_trigger$;


-- ربط الـ trigger بـ listing_requests (مع تحقّق دفاعي من الأعمدة المطلوبة).
DO $req_trigger$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'listing_requests'
      AND column_name  = 'listing_guidance'
  )
  AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'listing_requests'
      AND column_name  = 'price_includes_vat'
  ) THEN
    DROP TRIGGER IF EXISTS trg_listing_requests_pricing_sync
      ON public.listing_requests;
    CREATE TRIGGER trg_listing_requests_pricing_sync
    BEFORE INSERT OR UPDATE ON public.listing_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_listing_pricing_sync();
  END IF;
END
$req_trigger$;


-- ---------------------------------------------------------------------------
-- (C) دالة مساعدة لإعادة المزامنة اليدوية (للديباغ/الإصلاح من service_role)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_resync_listing_pricing(
  p_table_name text,
  p_row_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tbl text := lower(trim(p_table_name));
  v_row jsonb;
BEGIN
  IF v_tbl NOT IN ('properties','listing_requests') THEN
    RAISE EXCEPTION 'Unsupported table: %', p_table_name;
  END IF;

  IF v_tbl = 'properties' THEN
    UPDATE public.properties
    SET updated_at = COALESCE(updated_at, now())
    WHERE id = p_row_id
    RETURNING to_jsonb(public.properties.*) INTO v_row;
  ELSE
    UPDATE public.listing_requests
    SET updated_at = COALESCE(updated_at, now())
    WHERE id = p_row_id
    RETURNING to_jsonb(public.listing_requests.*) INTO v_row;
  END IF;

  IF v_row IS NULL THEN
    RAISE EXCEPTION 'Row % not found in %', p_row_id, v_tbl;
  END IF;

  RETURN jsonb_build_object(
    'table',     v_tbl,
    'row_id',    p_row_id,
    'synced_at', now()::text,
    'pricing',   v_row->'listing_guidance'->'pricing'
  );
END;
$$;

COMMENT ON FUNCTION public.fn_resync_listing_pricing(text, uuid) IS
  'Manual re-sync helper: fires the BEFORE UPDATE trigger and returns refreshed pricing JSONB.';

REVOKE ALL ON FUNCTION public.fn_resync_listing_pricing(text, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.fn_resync_listing_pricing(text, uuid)
  TO service_role;


-- ---------------------------------------------------------------------------
-- (D) تقرير سريع: عدد الإعلانات المعدّلة بـ backfill (للتسجيل، يظهر في log)
-- ---------------------------------------------------------------------------
DO $report$
DECLARE
  c_props int;
  c_reqs  int;
BEGIN
  SELECT COUNT(*) INTO c_props
  FROM public.properties
  WHERE listing_guidance ? 'pricing'
    AND (listing_guidance->'pricing') ? 'synced_at';

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema='public'
      AND table_name='listing_requests'
      AND column_name='listing_guidance'
  ) THEN
    EXECUTE 'SELECT COUNT(*) FROM public.listing_requests
             WHERE listing_guidance ? ''pricing''
               AND (listing_guidance->''pricing'') ? ''synced_at'''
    INTO c_reqs;
  ELSE
    c_reqs := 0;
  END IF;

  RAISE NOTICE
    'pricing_sync_v10: properties with pricing.synced_at = %, listing_requests with pricing.synced_at = %',
    c_props, c_reqs;
END
$report$;


COMMIT;

-- =============================================================================
-- بعد تنفيذ هذا الترحيل:
--
--   ✅ كل الإعلانات (drafts + منشورة) في قاعدة البيانات صار لديها أعمدة فوترة
--      مملوءة بقيم صحيحة (من JSONB إن كانت محفوظة، أو افتراضية آمنة).
--
--   ✅ أي INSERT/UPDATE جديد على properties أو listing_requests يضمن تلقائياً:
--      — مزامنة قيم JSONB إلى الأعمدة المخصّصة (إن كانت الأعمدة افتراضية).
--      — مرآة محدّثة لقيم الأعمدة داخل listing_guidance.pricing مع طابع زمني.
--
--   ✅ يستطيع المالك تعديل أي إعلان (draft أو منشور) عبر شاشة «تعديل الإعلان»
--      التي تُظهر السؤالين (شامل ضريبة؟ + نوع العمولة) ويُحفظ تلقائياً في
--      المكانين معاً بفضل الـ trigger.
--
--   ✅ شاشة تفاصيل الإعلان والفاتورة في Flutter تعرض الفاتورة المفصّلة من
--      الأعمدة المخصّصة الجديدة فوراً، ولكل إعلان قديم بدون أن يلاحظ المستخدم
--      أي اضطراب في المبالغ.
-- =============================================================================
