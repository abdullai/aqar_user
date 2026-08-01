-- =============================================================================
-- 2026-05-30 — أتمتة النشر للمسوّق بعد ربط ترخيص REGA صحيح
-- =============================================================================
-- السياق:
--   • تدفّق التصاريح القياسي يتطلّب:
--      1) المسوّق ينشئ صف تصريح (status=pending)
--      2) المالك يضغط «إصدار التصريح» (issue_listing_permit) لتحويله إلى approved
--      3) أحدهما يضغط «نشر» (publish_property_after_permit)
--   • طلب المستخدم: عند رفع التصريح الصحيح من REGA يجب أن ينتقل تلقائياً إلى
--     «منشور/محجوز» للمسوّق والمالك ويظهر في الرئيسية، دون انتظار خطوة يدوية.
--
-- الحل:
--   RPC مُحكم: marketer_finalize_rega_permit_and_publish(p_request_id)
--   - يفحص أن المستدعي هو المسوّق المختار (selected_marketer_id)
--   - يفحص أن التصريح مكتمل البيانات (permit_no/authority_name/license_no موجودة)
--   - يُحدّث listing_permits → status='approved' + issued_at
--   - يُحدّث listing_requests.workflow_stage='permit_issued'
--   - ثم يستدعي publish_property_after_permit لإكمال النشر
--   - يُرجع uuid للعقار المنشور
-- =============================================================================

BEGIN;

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

  IF lower(trim(coalesce(req.workflow_stage,''))) NOT IN
       ('permit_pending','awaiting_permits','pending_permits','permit_issued') THEN
    RAISE EXCEPTION 'invalid_request_stage';
  END IF;

  -- آخر تصريح للمسوّق على هذا الطلب
  SELECT lp.id,
         coalesce(nullif(trim(lp.permit_no),''), ''),
         coalesce(nullif(trim(lp.authority_name),''), ''),
         coalesce(nullif(trim(lp.license_no),''), '')
    INTO v_permit_id, v_permit_no, v_auth_name, v_license_no
  FROM public.listing_permits lp
  WHERE lp.request_id = p_request_id
    AND lp.marketer_id = uid
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

  -- تحويل مرحلة الطلب
  UPDATE public.listing_requests
     SET workflow_stage = 'permit_issued',
         updated_at     = now()
   WHERE id = p_request_id
     AND lower(trim(coalesce(workflow_stage,''))) <> 'published';

  -- استدعاء النشر القياسي (يتحقق هو من بقية الشروط)
  SELECT public.publish_property_after_permit(p_request_id) INTO v_prop_id;

  RETURN v_prop_id;
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.marketer_finalize_rega_permit_and_publish(uuid) IS
  'يُؤتمت تدفّق ما بعد ربط ترخيص REGA: اعتماد التصريح + ضبط مرحلة الطلب على permit_issued + نشر العقار. للمسوّق المختار فقط ومع تصريح مكتمل البيانات.';

COMMIT;
