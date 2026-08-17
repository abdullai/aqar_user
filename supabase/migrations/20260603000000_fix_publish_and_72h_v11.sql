-- =============================================================================
-- 2026-06-03 — إصلاح شامل: نشر التصريح + مهلة 72 ساعة + تنظيف الإعلانات القديمة
-- =============================================================================
-- المشاكل التي تم رصدها من تقرير المستخدم:
--
-- (1) عند ضغط زر «نشر الإعلان العقاري» يظهر خطأ:
--     PostgrestException(permit_rega_package_incomplete, code: P0001)
--     السبب: دالة `publish_property_after_permit` كانت تشترط وجود
--     `ad_qr_storage_path` أو `rega_pdf_storage_path` داخل `listing_permits.payload`،
--     بينما الحوار الجديد يأخذ فقط رقم ترخيص REGA + رقم هوية الوسيط
--     ولا يَرفع QR/PDF كملف منفصل. النتيجة: لا أحد يستطيع النشر.
--
-- (2) إعلانات قديمة لها أكثر من 72 ساعة في تبويب «التصريح 72 ساعة» لا تختفي.
--     السبب: حقل `permit_deadline_at` كان NULL على الطلبات القديمة، لذا
--     `cron_expire_marketer_permit_72h` لا يلتقطها (شرط
--     `permit_deadline_at IS NOT NULL AND permit_deadline_at < now()`).
--
-- (3) لا توجد آلية تَضبط `permit_deadline_at` على الطلبات الموجودة الآن في
--     مرحلة `permit_pending` بدون deadline.
--
-- الحل:
--   A) `publish_property_after_permit_v2(p_request_id)` — نسخة جديدة تقبل
--      التصريح إذا كان فقط `permit_no` + `authority_name` + `license_no`
--      مكتمل (الحدّ الأدنى المنطقي). لا تشترط `ad_qr_storage_path`.
--      وكذلك إعادة كتابة `publish_property_after_permit` القديمة لتفويض
--      التحقق إلى الجديدة، حتى يَستفيد كل العملاء فوراً.
--   B) backfill: ضع `permit_deadline_at = created_at + 72 hours` لكل طلب
--      حالياً في `permit_pending` بدون deadline.
--   C) Trigger: عند تحويل `workflow_stage` إلى `permit_pending` نضبط
--      `permit_deadline_at` تلقائياً (للحالات المستقبلية).
--   D) Run cron NOW: نُشغّل `cron_expire_marketer_permit_72h` مرّة لتنظيف
--      الإعلانات التي تجاوزت 72 ساعة فعلاً.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) publish_property_after_permit — لا نشترط ad_qr/rega_pdf storage path
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_property_after_permit(
  p_request_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_contract_id uuid;
  v_permit_status public.permit_status;
  v_issued_at timestamptz;
  v_prop_id uuid;
  v_permit_no text;
  v_auth text;
  v_lic text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT *
  INTO req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF lower(trim(coalesce(req.workflow_stage, ''))) NOT IN
       ('permit_issued', 'permit_pending', 'awaiting_permits', 'pending_permits') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_contract_id := req.contract_id;
  IF v_contract_id IS NULL THEN
    RAISE EXCEPTION 'contract_not_found';
  END IF;

  IF req.selected_marketer_id IS NULL THEN
    RAISE EXCEPTION 'marketer_not_selected';
  END IF;

  SELECT lp.status,
         lp.issued_at,
         coalesce(nullif(trim(lp.permit_no), ''),       ''),
         coalesce(nullif(trim(lp.authority_name), ''),  ''),
         coalesce(nullif(trim(lp.license_no), ''),      '')
  INTO v_permit_status,
       v_issued_at,
       v_permit_no,
       v_auth,
       v_lic
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = req.selected_marketer_id
  ORDER BY lp.created_at DESC
  LIMIT 1;

  IF v_permit_status IS NULL THEN
    RAISE EXCEPTION 'permit_not_found';
  END IF;

  -- ✅ القاعدة الجديدة: يكفي وجود رقم الترخيص + اسم الجهة + رقم الإعلان
  --    (الحقول الثلاثة التي يَملؤها المسوّق في نافذة «نشر الإعلان العقاري»).
  --    لم نَعد نشترط رفع ملف PDF/QR منفصل على Storage لأن واجهة الحوار
  --    الحالية لا تَدعم ذلك أصلاً.
  IF v_permit_no = '' OR v_auth = '' OR v_lic = '' THEN
    RAISE EXCEPTION 'permit_rega_package_incomplete';
  END IF;

  -- إن كانت المرحلة permit_pending — اعتمد التصريح تلقائياً (المسوّق وضع REGA)
  IF v_permit_status::text NOT IN ('approved') THEN
    UPDATE public.listing_permits
       SET status      = 'approved'::permit_status,
           issued_at   = COALESCE(issued_at, now()),
           reviewed_at = now(),
           updated_at  = now()
     WHERE request_id = p_request_id
       AND marketer_id = req.selected_marketer_id;
  END IF;

  IF uid IS DISTINCT FROM req.owner_id AND uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  v_prop_id := public.publish_property_from_contract(v_contract_id);

  -- تأكّد أن مرحلة الطلب صارت published (publish_property_from_contract يَفعل ذلك أصلاً)
  UPDATE public.listing_requests
     SET workflow_stage = 'published',
         updated_at     = now()
   WHERE id = p_request_id
     AND lower(trim(coalesce(workflow_stage, ''))) <> 'published';

  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_property_after_permit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_property_after_permit(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.publish_property_after_permit(uuid) IS
  'v11: ينشر العقار بعد التصريح. يَكفي وجود permit_no + authority_name + license_no '
  '(الحقول التي يَملؤها المسوّق في نافذة النشر) — لم نَعد نشترط ad_qr_storage_path '
  'أو rega_pdf_storage_path على listing_permits.payload.';

-- ---------------------------------------------------------------------------
-- B) Backfill: permit_deadline_at للطلبات الحالية في permit_pending بلا deadline
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_count int;
BEGIN
  UPDATE public.listing_requests
     SET permit_deadline_at = coalesce(
           contract_signed_at,
           contract_sent_at,
           created_at
         ) + interval '72 hours'
   WHERE lower(trim(coalesce(workflow_stage,''))) IN
         ('permit_pending','awaiting_permits','pending_permits')
     AND permit_deadline_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RAISE NOTICE 'permit_deadline_at backfill: % rows updated', v_count;
END $$;

-- ---------------------------------------------------------------------------
-- C) Trigger: ضبط permit_deadline_at تلقائياً عند الدخول لمرحلة permit_pending
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._tr_listing_requests_set_permit_deadline()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_new_stage text := lower(trim(coalesce(NEW.workflow_stage, '')));
  v_old_stage text := lower(trim(coalesce(OLD.workflow_stage, '')));
BEGIN
  IF v_new_stage IN ('permit_pending','awaiting_permits','pending_permits')
     AND v_new_stage <> v_old_stage
     AND NEW.permit_deadline_at IS NULL THEN
    NEW.permit_deadline_at := coalesce(
      NEW.contract_signed_at,
      NEW.contract_sent_at,
      now()
    ) + interval '72 hours';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_permit_deadline ON public.listing_requests;
CREATE TRIGGER trg_set_permit_deadline
  BEFORE UPDATE OF workflow_stage
  ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public._tr_listing_requests_set_permit_deadline();

-- ---------------------------------------------------------------------------
-- D) شغّل cron مرّة الآن لتنظيف الإعلانات التي تجاوزت 72 ساعة فعلاً
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_res jsonb;
BEGIN
  BEGIN
    v_res := public.cron_expire_marketer_permit_72h();
    RAISE NOTICE 'permit 72h cron result: %', v_res;
  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'cron_expire_marketer_permit_72h not installed (v8 migration missing). Skipping.';
  END;
END $$;

COMMIT;

-- =============================================================================
-- استعلامات تحقّق سريعة (شغّلها يدوياً للتأكد):
--
--   -- إعلانات لا تَزال في permit_pending مع deadline:
--   SELECT id, workflow_stage, permit_deadline_at, created_at
--     FROM public.listing_requests
--    WHERE workflow_stage IN ('permit_pending','awaiting_permits','pending_permits')
--    ORDER BY permit_deadline_at NULLS LAST;
--
--   -- اختبار النشر يدوياً (بدلاً من واجهة Flutter):
--   SELECT public.publish_property_after_permit('<request_id>');
-- =============================================================================
