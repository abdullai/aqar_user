-- إصلاح إلغاء الحجز: تعارض اسم السجل r مع alias الجدول (PostgreSQL 55000).
-- إصلاح إتمام البيع: الحجز قائم لكن workflow_stage ليست reserved.

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

  SELECT
    res.id,
    res.property_id,
    res.user_id,
    p.owner_id AS owner_id,
    p.published_by_marketer_id AS marketer_id
  INTO r
  FROM public.reservations res
  JOIN public.properties p ON p.id = res.property_id
  WHERE res.id = p_reservation_id
  FOR UPDATE OF res, p;

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
    WHERE id = v_property_id
      AND lower(trim(coalesce(status, ''))) IS DISTINCT FROM 'sold';
  END IF;

  BEGIN
    IF prop_owner IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        prop_owner,
        CASE WHEN p_set_status = 'expired' THEN 'reservation_expired' ELSE 'reservation_cancelled' END,
        CASE WHEN p_set_status = 'expired' THEN 'انتهت مهلة إتمام الصفقة' ELSE 'عاد العقار للنشر' END,
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
        CASE WHEN p_set_status = 'expired' THEN 'انتهت مهلة إتمام الصفقة' ELSE 'عاد العقار للنشر' END,
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

CREATE OR REPLACE FUNCTION public.complete_property_sale(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  rsrv record;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO prop FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF lower(trim(coalesce(prop.status, ''))) = 'sold' THEN
    RETURN;
  END IF;

  SELECT * INTO rsrv
  FROM public.reservations res
  WHERE res.property_id = p_property_id
    AND res.status IN ('pending', 'paid')
    AND res.expires_at > now()
  ORDER BY res.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no_active_reservation';
  END IF;

  IF NOT (
    uid = rsrv.user_id
    OR uid = prop.owner_id
    OR (prop.published_by_marketer_id IS NOT NULL AND uid = prop.published_by_marketer_id)
  ) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF lower(trim(coalesce(prop.workflow_stage, ''))) IS DISTINCT FROM 'reserved' THEN
    UPDATE public.properties
    SET workflow_stage = 'reserved', updated_at = now()
    WHERE id = p_property_id;
  END IF;

  UPDATE public.properties p
  SET
    status = 'sold',
    workflow_stage = 'archived',
    sold_at = now(),
    sold_to_user_id = rsrv.user_id,
    reservation_expires_at = NULL,
    updated_at = now()
  WHERE p.id = p_property_id;

  UPDATE public.reservations
  SET status = 'paid', updated_at = now()
  WHERE id = rsrv.id;

  UPDATE public.reservations
  SET status = 'cancelled', updated_at = now()
  WHERE property_id = p_property_id
    AND id IS DISTINCT FROM rsrv.id
    AND status IN ('pending', 'paid');

  PERFORM public.workflow_create_notification(
    prop.owner_id,
    'property_sale_completed',
    'تم إتمام البيع',
    'تم تسجيل إتمام البيع على إعلانك.',
    'property',
    p_property_id,
    jsonb_build_object('property_id', p_property_id, 'reservation_id', rsrv.id)
  );

  IF rsrv.user_id IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      rsrv.user_id,
      'property_sale_completed',
      'تم إتمام البيع',
      'تم تسجيل إتمام البيع على العقار الذي في صفقاتك.',
      'property',
      p_property_id,
      jsonb_build_object('property_id', p_property_id, 'reservation_id', rsrv.id)
    );
  END IF;

  IF prop.published_by_marketer_id IS NOT NULL
     AND prop.published_by_marketer_id IS DISTINCT FROM prop.owner_id THEN
    PERFORM public.workflow_create_notification(
      prop.published_by_marketer_id,
      'property_sale_completed',
      'تم إتمام البيع',
      'تم تسجيل إتمام البيع لإعلان منشور من جهتك.',
      'property',
      p_property_id,
      jsonb_build_object('property_id', p_property_id, 'reservation_id', rsrv.id)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.release_or_expire_reservation(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.release_or_expire_reservation(uuid, text) TO authenticated;

REVOKE ALL ON FUNCTION public.complete_property_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;

COMMIT;
