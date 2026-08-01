-- =============================================================================
-- 2026-06-02 — تجهيز نشر إعلان المسوّق:
--   1) قبول مرحلة contract_signed داخل marketer_finalize_rega_permit_and_publish
--      مع نقل أوتوماتيكي إلى permit_pending قبل اعتماد التصريح.
--   2) إضافة فهرس فريد جزئي على listing_permits(request_id, marketer_id)
--      لمنع تكرار صفوف التصاريح من سباقات الإدخال.
--   3) تنظيف الصفوف المكرّرة الموجودة (إن وُجدت): الإبقاء على الأحدث/المعتمد.
--   4) RPC مساعد: marketer_set_request_to_permit_pending — لتحريك المرحلة
--      من contract_signed إلى permit_pending عبر SECURITY DEFINER بدون التصادم
--      مع RLS، يستدعى من العميل قبل النشر إن لزم.
-- =============================================================================

BEGIN;

-- (1) تنظيف التكرارات الحالية لكل (request_id, marketer_id):
--     نختار صفاً واحداً (الأحدث، أو المعتمد إن وُجد) ونوقف الباقي بحالة void.
DO $$
DECLARE r record;
BEGIN
  -- نضيف قيمة 'void' إلى enum إن لم تكن موجودة (آمن إن كانت موجودة سابقاً).
  IF NOT EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    WHERE t.typname = 'permit_status' AND e.enumlabel = 'void'
  ) THEN
    BEGIN
      ALTER TYPE public.permit_status ADD VALUE 'void';
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
END $$;

-- نُعطّل (status='rejected') الصفوف الزائدة لنفس (request_id, marketer_id)
WITH ranked AS (
  SELECT
    id,
    request_id,
    marketer_id,
    status,
    issued_at,
    created_at,
    row_number() OVER (
      PARTITION BY request_id, marketer_id
      ORDER BY
        CASE WHEN status::text = 'approved' THEN 0 ELSE 1 END,
        issued_at DESC NULLS LAST,
        created_at DESC NULLS LAST,
        id DESC
    ) AS rn
  FROM public.listing_permits
  WHERE request_id IS NOT NULL AND marketer_id IS NOT NULL
)
UPDATE public.listing_permits p
SET status = 'rejected'::permit_status,
    notes  = coalesce(p.notes, '') || ' [auto-deduped 2026-06-02]'
FROM ranked r
WHERE p.id = r.id
  AND r.rn > 1
  AND p.status NOT IN ('approved'::permit_status, 'rejected'::permit_status);

-- (2) فهرس فريد جزئي يمنع التكرار مستقبلاً.
--     ملاحظة: يجب استخدام مقارنة enum مباشرة (immutable) بدل `status::text` —
--     PostgreSQL يرفض الـpredicate إذا احتوى دوال غير IMMUTABLE.
DROP INDEX IF EXISTS public.listing_permits_unique_request_marketer_active;
CREATE UNIQUE INDEX listing_permits_unique_request_marketer_active
  ON public.listing_permits (request_id, marketer_id)
  WHERE status <> 'rejected'::permit_status;

-- (3) RPC مساعد: تحريك المرحلة من contract_signed إلى permit_pending
--     يستدعى من العميل قبل النشر إن كان الطلب لا يزال في contract_signed.
CREATE OR REPLACE FUNCTION public.marketer_set_request_to_permit_pending(
  p_request_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  v_due timestamptz;
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

  IF req.selected_marketer_id IS NULL OR uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_selected_marketer';
  END IF;

  -- إن كانت المرحلة بالفعل صالحة للنشر، لا حاجة لأي تحديث.
  IF lower(trim(coalesce(req.workflow_stage,''))) IN
       ('permit_pending','awaiting_permits','pending_permits','permit_issued','published') THEN
    RETURN coalesce(req.workflow_stage::text, '');
  END IF;

  -- يقبل التحريك فقط من contract_signed (للحفاظ على سلامة التدفق).
  IF lower(trim(coalesce(req.workflow_stage,''))) <> 'contract_signed' THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  v_due := coalesce(req.permit_deadline_at, now() + interval '72 hours');

  UPDATE public.listing_requests
     SET workflow_stage      = 'permit_pending',
         permit_deadline_at  = v_due,
         updated_at          = now()
   WHERE id = p_request_id;

  RETURN 'permit_pending';
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_set_request_to_permit_pending(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_set_request_to_permit_pending(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.marketer_set_request_to_permit_pending(uuid) IS
  'يحرّك المرحلة من contract_signed إلى permit_pending للمسوّق المختار قبل النشر — SECURITY DEFINER لتجاوز قيود RLS بحدود المسوّق المختار فقط.';

-- (4) إعادة تعريف marketer_finalize_rega_permit_and_publish لتقبل
--     contract_signed والانتقال أوتوماتيكياً إلى permit_pending.
CREATE OR REPLACE FUNCTION public.marketer_finalize_rega_permit_and_publish(
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
  v_permit_id uuid;
  v_permit_no text;
  v_auth_name text;
  v_license_no text;
  v_prop_id uuid;
  v_stage text;
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

  IF req.selected_marketer_id IS NULL OR uid IS DISTINCT FROM req.selected_marketer_id THEN
    RAISE EXCEPTION 'not_selected_marketer';
  END IF;

  v_stage := lower(trim(coalesce(req.workflow_stage,'')));

  -- اقبل contract_signed أيضاً وحرّك المرحلة فوراً إلى permit_pending.
  IF v_stage = 'contract_signed' THEN
    UPDATE public.listing_requests
       SET workflow_stage      = 'permit_pending',
           permit_deadline_at  = coalesce(permit_deadline_at, now() + interval '72 hours'),
           updated_at          = now()
     WHERE id = p_request_id;
    v_stage := 'permit_pending';
  END IF;

  IF v_stage NOT IN
       ('permit_pending','awaiting_permits','pending_permits','permit_issued') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  -- آخر تصريح للمسوّق على هذا الطلب (نتجاهل المرفوض)
  SELECT lp.id,
         coalesce(nullif(trim(lp.permit_no),''), ''),
         coalesce(nullif(trim(lp.authority_name),''), ''),
         coalesce(nullif(trim(lp.license_no),''), '')
    INTO v_permit_id, v_permit_no, v_auth_name, v_license_no
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = uid
    AND lp.status <> 'rejected'::permit_status
  ORDER BY lp.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_permit_id IS NULL THEN
    RAISE EXCEPTION 'permit_not_found';
  END IF;

  IF v_permit_no = '' OR v_auth_name = '' OR v_license_no = '' THEN
    RAISE EXCEPTION 'permit_data_incomplete';
  END IF;

  -- اعتماد التصريح
  UPDATE public.listing_permits
     SET status      = 'approved'::permit_status,
         issued_at   = COALESCE(issued_at, now()),
         reviewed_at = now(),
         updated_at  = now()
   WHERE id = v_permit_id;

  -- تحويل مرحلة الطلب إلى permit_issued (دون لمس المنشورة)
  UPDATE public.listing_requests
     SET workflow_stage = 'permit_issued',
         updated_at     = now()
   WHERE id = p_request_id
     AND lower(trim(coalesce(workflow_stage,''))) <> 'published';

  -- استدعاء النشر القياسي (يفحص التحقق التلقائي وبقية الشروط)
  SELECT public.publish_property_after_permit(p_request_id) INTO v_prop_id;

  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid) IS
  'يُؤتمت تدفّق ما بعد ربط ترخيص REGA: يقبل contract_signed كذلك، يحرّك المرحلة، يعتمد التصريح، يُحدّث permit_issued، ثم ينشر العقار. للمسوّق المختار فقط مع تصريح مكتمل.';

COMMIT;

-- =============================================================================
-- تحقق سريع بعد التشغيل:
--   SELECT request_id, marketer_id, count(*)
--     FROM public.listing_permits
--    WHERE status::text <> 'rejected'
--    GROUP BY 1,2
--   HAVING count(*) > 1;     -- يجب أن يكون فارغاً
-- =============================================================================
