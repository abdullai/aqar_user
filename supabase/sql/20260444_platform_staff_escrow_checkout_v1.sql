-- =============================================================================
-- 1) مسؤول المنصة (منفصل عن المالك/المنشّر)
-- 2) أحداث مدفوعات/ضمان (سجل تدقيق) + تسجيل نية دفع
-- 3) تحديث RPC جلسة المزاد لتشمل مسؤول المنصة
--
-- يُشغَّل بعد: 20260442 + 20260443
--
-- تعيين مسؤول:
--   أ) عمود users_profiles.platform_staff = true (لوحة Supabase / SQL يدوي)
--   ب) JWT: app_metadata.platform_staff = "true" على المستخدم (Auth → User → metadata)
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- A) platform_staff على الملف الشخصي
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users_profiles'
      AND column_name = 'platform_staff'
  ) THEN
    ALTER TABLE public.users_profiles
      ADD COLUMN platform_staff boolean NOT NULL DEFAULT false;
  END IF;
END $$;

COMMENT ON COLUMN public.users_profiles.platform_staff IS
  'صلاحيات تشغيل/مراقبة المنصة (جلسات مزاد، سجل مدفوعات). لا يُمنح تلقائياً.';

-- ---------------------------------------------------------------------------
-- B) هل المستخدم الحالي مسؤول منصة؟
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.app_current_user_is_platform_staff()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  jwt_ok boolean;
  prof boolean;
BEGIN
  IF uid IS NULL THEN
    RETURN false;
  END IF;

  jwt_ok := lower(trim(coalesce(
    auth.jwt() -> 'app_metadata' ->> 'platform_staff',
    ''
  ))) IN ('true', '1', 'yes');

  SELECT coalesce(up.platform_staff, false)
  INTO prof
  FROM public.users_profiles up
  WHERE up.user_id = uid;

  prof := coalesce(prof, false);

  RETURN jwt_ok OR prof;
END;
$$;

COMMENT ON FUNCTION public.app_current_user_is_platform_staff() IS
  'JWT app_metadata.platform_staff أو users_profiles.platform_staff.';

GRANT EXECUTE ON FUNCTION public.app_current_user_is_platform_staff() TO authenticated;

-- ---------------------------------------------------------------------------
-- C) سجل أحداث المدفوعات / الضمان (لا ينفّذ خصماً — تدقيق + تكامل لاحق)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.listing_payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  auction_session_id uuid REFERENCES public.property_auction_sessions (id) ON DELETE SET NULL,
  initiator_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  recorded_as_role text NOT NULL DEFAULT 'other'::text
    CHECK (
      recorded_as_role = ANY (
        ARRAY[
          'platform_staff'::text,
          'owner'::text,
          'publishing_marketer'::text,
          'buyer'::text,
          'other'::text
        ]
      )
    ),
  kind text NOT NULL
    CHECK (
      kind = ANY (
        ARRAY[
          'auction_escrow_hold'::text,
          'bidder_good_faith'::text,
          'marketer_service_fee'::text,
          'platform_fee'::text,
          'manual_ledger'::text,
          'other'::text
        ]
      )
    ),
  provider text NOT NULL DEFAULT 'manual'::text
    CHECK (
      provider = ANY (
        ARRAY[
          'moyasar'::text,
          'stripe'::text,
          'manual'::text,
          'none'::text
        ]
      )
    ),
  amount_sar numeric NOT NULL CHECK (amount_sar > 0::numeric),
  status text NOT NULL DEFAULT 'recorded'::text
    CHECK (
      status = ANY (
        ARRAY[
          'recorded'::text,
          'pending_gateway'::text,
          'requires_action'::text,
          'succeeded'::text,
          'failed'::text,
          'cancelled'::text,
          'refunded'::text
        ]
      )
    ),
  external_payment_id text,
  escrow_notes text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_listing_payment_events_property
  ON public.listing_payment_events (property_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_listing_payment_events_initiator
  ON public.listing_payment_events (initiator_id, created_at DESC);

ALTER TABLE public.listing_payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS listing_payment_events_select_involved
  ON public.listing_payment_events;

CREATE POLICY listing_payment_events_select_involved
  ON public.listing_payment_events
  FOR SELECT
  TO authenticated
  USING (
    initiator_id = auth.uid()
    OR public.app_current_user_is_platform_staff()
    OR EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = listing_payment_events.property_id
        AND p.owner_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = listing_payment_events.property_id
        AND p.published_by_marketer_id IS NOT NULL
        AND p.published_by_marketer_id = auth.uid()
    )
  );

COMMENT ON TABLE public.listing_payment_events IS
  'سجل تدقيق للعربون/الضمان/الرسوم؛ التحصيل عبر Moyasar/Stripe/يدوي خارج هذا الجدول.';

GRANT SELECT ON public.listing_payment_events TO authenticated;

-- ---------------------------------------------------------------------------
-- D) تسجيل حدث (SECURITY DEFINER)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_listing_payment_event(
  p_property_id uuid,
  p_kind text,
  p_provider text,
  p_amount_sar numeric,
  p_auction_session_id uuid DEFAULT NULL,
  p_escrow_notes text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  role text := 'other'::text;
  staff boolean;
  new_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_amount_sar IS NULL OR p_amount_sar <= 0::numeric THEN
    RAISE EXCEPTION 'invalid_payment_amount';
  END IF;

  staff := public.app_current_user_is_platform_staff();

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF staff THEN
    role := 'platform_staff'::text;
  ELSIF uid = prop.owner_id THEN
    role := 'owner'::text;
  ELSIF prop.published_by_marketer_id IS NOT NULL
        AND uid = prop.published_by_marketer_id THEN
    role := 'publishing_marketer'::text;
  ELSIF p_kind = 'bidder_good_faith'::text
        AND coalesce(prop.is_auction, false) IS TRUE
        AND uid <> prop.owner_id
        AND (
          prop.published_by_marketer_id IS NULL
          OR uid <> prop.published_by_marketer_id
        )
        AND (
          prop.selected_marketer_id IS NULL
          OR uid <> prop.selected_marketer_id
        ) THEN
    role := 'buyer'::text;
  ELSE
    RAISE EXCEPTION 'not_authorized_to_record_payment_event';
  END IF;

  IF p_auction_session_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.property_auction_sessions s
      WHERE s.id = p_auction_session_id
        AND s.property_id = p_property_id
    ) THEN
      RAISE EXCEPTION 'auction_session_mismatch';
    END IF;
  END IF;

  INSERT INTO public.listing_payment_events (
    property_id,
    auction_session_id,
    initiator_id,
    recorded_as_role,
    kind,
    provider,
    amount_sar,
    status,
    escrow_notes,
    metadata
  )
  VALUES (
    p_property_id,
    p_auction_session_id,
    uid,
    role,
    p_kind,
    coalesce(nullif(trim(p_provider), ''), 'manual'::text),
    p_amount_sar,
    CASE
      WHEN p_provider IN ('moyasar'::text, 'stripe'::text) THEN 'pending_gateway'::text
      ELSE 'recorded'::text
    END,
    nullif(trim(p_escrow_notes), ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

COMMENT ON FUNCTION public.register_listing_payment_event IS
  'يسجّل حدث دفع/ضمان؛ المسوّق غير المنشّر لا يسجّل لعقار لا يخصه.';

GRANT EXECUTE ON FUNCTION public.register_listing_payment_event(
  uuid, text, text, numeric, uuid, text, jsonb
) TO authenticated;

-- ---------------------------------------------------------------------------
-- E) تحديث إدارة جلسة المزاد — يشمل مسؤول المنصة
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.open_property_auction_session(
  p_property_id uuid,
  p_ends_at timestamptz DEFAULT NULL,
  p_min_increment_sar numeric DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  new_id uuid;
  inc numeric;
  staff boolean;
  authorized boolean;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  staff := public.app_current_user_is_platform_staff();

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF coalesce(prop.is_auction, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'not_auction_listing';
  END IF;

  IF NOT (
    lower(trim(coalesce(prop.workflow_stage, ''))) = 'published'
    OR lower(trim(coalesce(prop.status, ''))) = ANY (
      ARRAY[
        'active'::text,
        'available'::text,
        'published'::text,
        'live'::text,
        'approved'::text
      ]
    )
  ) THEN
    RAISE EXCEPTION 'listing_not_open_for_bids';
  END IF;

  authorized := staff
    OR uid = prop.owner_id
    OR (
      prop.published_by_marketer_id IS NOT NULL
      AND uid = prop.published_by_marketer_id
    );

  IF NOT authorized THEN
    RAISE EXCEPTION 'not_authorized_to_manage_auction';
  END IF;

  IF p_ends_at IS NOT NULL AND p_ends_at <= now() THEN
    RAISE EXCEPTION 'auction_end_must_be_future';
  END IF;

  inc := coalesce(p_min_increment_sar, 100::numeric);
  IF inc < 1::numeric THEN
    RAISE EXCEPTION 'invalid_min_increment';
  END IF;

  UPDATE public.property_auction_sessions
  SET
    status = 'cancelled'::text,
    updated_at = now()
  WHERE property_id = p_property_id
    AND status = 'open'::text;

  INSERT INTO public.property_auction_sessions (
    property_id,
    status,
    ends_at,
    min_increment_sar
  )
  VALUES (
    p_property_id,
    'open'::text,
    p_ends_at,
    inc
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.close_property_auction_session(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  prop record;
  staff boolean;
  authorized boolean;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  staff := public.app_current_user_is_platform_staff();

  SELECT
    id,
    owner_id,
    published_by_marketer_id,
    is_auction,
    status,
    workflow_stage
  INTO prop
  FROM public.properties
  WHERE id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF coalesce(prop.is_auction, false) IS NOT TRUE THEN
    RAISE EXCEPTION 'not_auction_listing';
  END IF;

  authorized := staff
    OR uid = prop.owner_id
    OR (
      prop.published_by_marketer_id IS NOT NULL
      AND uid = prop.published_by_marketer_id
    );

  IF NOT authorized THEN
    RAISE EXCEPTION 'not_authorized_to_manage_auction';
  END IF;

  UPDATE public.property_auction_sessions
  SET
    status = 'closed'::text,
    updated_at = now()
  WHERE property_id = p_property_id
    AND status = 'open'::text;
END;
$$;

-- ---------------------------------------------------------------------------
-- F) ربط حدث بدفع خارجي (بعد نجاح Stripe/Moyasar — استدعاء من Edge أو موظف)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.attach_listing_payment_external_ref(
  p_event_id uuid,
  p_external_id text,
  p_new_status text DEFAULT 'succeeded'::text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  staff boolean;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  staff := public.app_current_user_is_platform_staff();

  IF NOT staff THEN
    RAISE EXCEPTION 'not_authorized_to_attach_payment_ref';
  END IF;

  IF p_external_id IS NULL OR trim(p_external_id) = '' THEN
    RAISE EXCEPTION 'invalid_external_id';
  END IF;

  UPDATE public.listing_payment_events
  SET
    external_payment_id = trim(p_external_id),
    status = p_new_status,
    updated_at = now()
  WHERE id = p_event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.attach_listing_payment_external_ref(uuid, text, text)
  TO authenticated;

COMMIT;
