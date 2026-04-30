-- =============================================================================
-- Reservations / Cart Flow RPCs
-- - reserve_property: published -> reserved (72h)
-- - release_or_expire_reservation: reserved -> published
-- - cron_expire_reservations: auto-expire 72h
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- A) reserve_property
-- -----------------------------------------------------------------------------
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

  -- Cleanup expired reservations to avoid UNIQUE(pending) conflicts.
  UPDATE public.reservations
  SET status = 'expired'
  WHERE property_id = p_property_id
    AND status IN ('pending'::text, 'paid'::text)
    AND expires_at <= now();

  -- Prevent active reservations.
  IF EXISTS (
    SELECT 1
    FROM public.reservations r
    WHERE r.property_id = p_property_id
      AND r.status IN ('pending'::text, 'paid'::text)
      AND r.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'property_already_reserved';
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

  UPDATE public.properties
  SET
    workflow_stage = 'reserved',
    reservation_expires_at = v_expires_at,
    updated_at = now()
  WHERE id = p_property_id;

  -- Notifications (best-effort; do not fail the reservation)
  BEGIN
    IF v_owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        v_owner_id,
        'reservation_created',
        'تم الحجز',
        'تم حجز إعلانك. ستتابع التفاصيل عبر صفحة الإعلان.',
        'property',
        p_property_id,
        jsonb_build_object('reservation_id', v_reservation_id, 'property_id', p_property_id)
      );
    END IF;

    IF v_marketer_id IS NOT NULL AND v_marketer_id <> v_owner_id THEN
      PERFORM public.workflow_create_notification(
        v_marketer_id,
        'reservation_created',
        'تم الحجز',
        'تم حجز إعلان منشور من جهتك. راجع الإعلان لمتابعة الحالة.',
        'property',
        p_property_id,
        jsonb_build_object('reservation_id', v_reservation_id, 'property_id', p_property_id)
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- ignore notification failures
    NULL;
  END;

  RETURN v_reservation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_property(uuid, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reserve_property(uuid, numeric) TO authenticated;

-- -----------------------------------------------------------------------------
-- B) release_or_expire_reservation
-- -----------------------------------------------------------------------------
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

  -- Manual cancel requires the reservation owner.
  IF p_set_status = 'cancelled' THEN
    IF uid IS NULL THEN
      RAISE EXCEPTION 'not_authenticated';
    END IF;
    IF uid IS DISTINCT FROM r.user_id THEN
      RAISE EXCEPTION 'not_reservation_owner';
    END IF;
  END IF;

  -- Update reservation status if still active.
  UPDATE public.reservations
  SET status = p_set_status
  WHERE id = p_reservation_id;

  -- Only move property back to published if no active reservation remains.
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
    -- Best-effort notifications.
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

-- -----------------------------------------------------------------------------
-- C) cron_expire_reservations
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_reservations()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
BEGIN
  WITH moved AS (
    UPDATE public.reservations r
    SET status = 'expired'
    WHERE r.status IN ('pending'::text, 'paid'::text)
      AND r.expires_at <= now()
    RETURNING r.property_id
  )
  UPDATE public.properties p
  SET
    workflow_stage = 'published',
    reservation_expires_at = NULL,
    updated_at = now()
  WHERE p.id IN (
    SELECT DISTINCT m.property_id
    FROM moved m
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.reservations r2
      WHERE r2.property_id = m.property_id
        AND r2.status IN ('pending'::text, 'paid'::text)
        AND r2.expires_at > now()
    )
  );

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN coalesce(n, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_reservations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_reservations() TO service_role;

COMMIT;

