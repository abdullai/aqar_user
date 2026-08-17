-- =============================================================================
-- حجز متعدد من السلة: أكثر من مستخدم يمكنه حجز نفس الإعلان المنشور دون تحويل
-- العقار إلى workflow_stage = reserved (يبقى published حتى إتمام البيع أو انتهاء
-- كل الحجوزات النشطة).
-- يمنع نفس المستخدم من امتلاك أكثر من حجز pending/paid فعّال لنفس العقار.
-- طبّق بعد 20260332_reservations_cart_flow_rpcs_v1.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.reserve_property(
  p_property_id uuid,
  p_base_price numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  v_expires_at timestamptz;
  v_reservation_id uuid;
  v_owner_id uuid;
  v_marketer_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT owner_id, published_by_marketer_id, workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  v_owner_id := prop.owner_id;
  v_marketer_id := prop.published_by_marketer_id;

  IF lower(trim(coalesce(prop.workflow_stage, ''))) <> 'published' THEN
    RAISE EXCEPTION 'property_not_published';
  END IF;

  IF uid = v_owner_id THEN
    RAISE EXCEPTION 'cannot_reserve_own_listing';
  END IF;

  IF v_marketer_id IS NOT NULL AND uid = v_marketer_id THEN
    RAISE EXCEPTION 'cannot_reserve_publisher_listing';
  END IF;

  UPDATE public.reservations
  SET status = 'expired'
  WHERE property_id = p_property_id
    AND user_id = uid
    AND status IN ('pending'::text, 'paid'::text)
    AND expires_at <= now();

  IF EXISTS (
    SELECT 1
    FROM public.reservations r
    WHERE r.property_id = p_property_id
      AND r.user_id = uid
      AND r.status IN ('pending'::text, 'paid'::text)
      AND r.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'user_already_has_active_reservation';
  END IF;

  v_expires_at := now() + interval '72 hours';

  INSERT INTO public.reservations (
    user_id,
    property_id,
    status,
    created_at,
    expires_at,
    base_price,
    platform_fee_amount,
    extra_fee_amount,
    total_amount
  )
  VALUES (
    uid,
    p_property_id,
    'pending'::text,
    now(),
    v_expires_at,
    p_base_price,
    0,
    0,
    0
  )
  RETURNING id INTO v_reservation_id;

  -- إبقاء الإعلان منشوراً؛ لا نغيّر workflow_stage إلى reserved.

  BEGIN
    IF v_owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        v_owner_id,
        'reservation_created',
        'تم حجز',
        'أضاف مستخدم جديد حجزاً مؤقتاً على إعلانك. يمكن أن يكون هناك أكثر من مهتم.',
        'property',
        p_property_id,
        jsonb_build_object('reservation_id', v_reservation_id, 'property_id', p_property_id)
      );
    END IF;

    IF v_marketer_id IS NOT NULL AND v_marketer_id <> v_owner_id THEN
      PERFORM public.workflow_create_notification(
        v_marketer_id,
        'reservation_created',
        'تم حجز',
        'حجز مؤقت جديد على إعلان منشور من جهتك.',
        'property',
        p_property_id,
        jsonb_build_object('reservation_id', v_reservation_id, 'property_id', p_property_id)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_reservation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_property(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_property(uuid, numeric) TO authenticated;

COMMIT;
