-- =============================================================================
-- Flutter يستدعي: rpc('release_or_expire_reservation', { p_reservation_id, p_set_status })
-- إن ظهرت عندك فقط: cancel_reservation / expire_reservations / cron_expire_reservations
-- فغالباً اسم الدالة في PostgREST لا يطابق التطبيق → 404 أو PGRST202.
-- هذا الملف يضيف (أو يستبدل) الدالة بالاسم الذي يتوقعه العميل، دون حذف دوالك الحالية.
-- المصدر: نفس منطق supabase/sql/20260332_reservations_cart_flow_rpcs_v1.sql (قسم B).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.release_or_expire_reservation(
  p_reservation_id uuid,
  p_set_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r record;
  prop_owner uuid;
  prop_marketer uuid;
  v_property_id uuid;
BEGIN
  IF p_set_status NOT IN ('cancelled', 'expired') THEN
    RAISE EXCEPTION 'invalid_status';
  END IF;

  SELECT r.*, p.owner_id AS owner_id, p.published_by_marketer_id AS marketer_id
  INTO r
  FROM public.reservations r
  JOIN public.properties p ON p.id = r.property_id
  WHERE r.id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reservation_not_found';
  END IF;

  v_property_id := r.property_id;
  prop_owner := r.owner_id;
  prop_marketer := r.marketer_id;

  IF p_set_status = 'cancelled' THEN
    IF uid IS NULL THEN
      RAISE EXCEPTION 'not_authenticated';
    END IF;
    IF uid IS DISTINCT FROM r.user_id THEN
      RAISE EXCEPTION 'not_reservation_owner';
    END IF;
  END IF;

  UPDATE public.reservations
  SET status = p_set_status
  WHERE id = p_reservation_id;

  IF NOT EXISTS (
    SELECT 1
    FROM public.reservations r2
    WHERE r2.property_id = v_property_id
      AND r2.status IN ('pending'::text, 'paid'::text)
      AND r2.expires_at > now()
  ) THEN
    UPDATE public.properties
    SET
      workflow_stage = 'published',
      reservation_expires_at = NULL,
      updated_at = now()
    WHERE id = v_property_id;
  END IF;

  BEGIN
    IF prop_owner IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        prop_owner,
        CASE WHEN p_set_status = 'expired' THEN 'reservation_expired' ELSE 'reservation_cancelled' END,
        CASE WHEN p_set_status = 'expired' THEN 'انتهت مهلة الحجز' ELSE 'عاد العقار للنشر' END,
        'تم إنهاء حجز الإعلان.',
        'property',
        v_property_id,
        jsonb_build_object('reservation_id', p_reservation_id, 'property_id', v_property_id)
      );
    END IF;

    IF prop_marketer IS NOT NULL AND prop_marketer <> prop_owner THEN
      PERFORM public.workflow_create_notification(
        prop_marketer,
        CASE WHEN p_set_status = 'expired' THEN 'reservation_expired' ELSE 'reservation_cancelled' END,
        CASE WHEN p_set_status = 'expired' THEN 'انتهت مهلة الحجز' ELSE 'عاد العقار للنشر' END,
        'تم إنهاء حجز الإعلان المنشور من جهتك.',
        'property',
        v_property_id,
        jsonb_build_object('reservation_id', p_reservation_id, 'property_id', v_property_id)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

END;
$$;

REVOKE ALL ON FUNCTION public.release_or_expire_reservation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_or_expire_reservation(uuid, text) TO authenticated;

COMMIT;
