-- موثوق لاين — قفل الربط والاستقرار (مصدر حقيقة: migrations فقط)
-- • دفع: لا إدراج مبلغ من العميل؛ كتالوج رسوم؛ فاتورة من validate_payment_intent
-- • get_chat_list2 توقيع واحد (لا يصفّر الشارات)
-- • owner_edit_property + RLS تعديل العقار
-- • بلاغات بحدّ خادم + طابور موظفين
-- • إتمام بيع ≠ دفع بوابة
-- • موظف منصة: تدقيق + رد تذكرة + لا قرار مالي من العميل
-- لا تطبّق نسخ supabase/sql يدوياً بعد هذا الملف.

BEGIN;

-- =============================================================================
-- 0) is_admin = موظفو المنصة (منح آمن حتى لا تُكسر سياسات RLS القديمة)
-- =============================================================================
-- الوسيط في الإنتاج اسمه uid — CREATE OR REPLACE يرفض تغيير الاسم (42P13).
CREATE OR REPLACE FUNCTION public.is_admin(uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_platform_staff(uid);
$$;

REVOKE ALL ON FUNCTION public.is_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO anon, authenticated, service_role;

ALTER TABLE public.platform_staff
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'staff',
  ADD COLUMN IF NOT EXISTS can_finance boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS can_moderate boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS can_support boolean NOT NULL DEFAULT true;

ALTER TABLE public.platform_staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS platform_staff_select_self ON public.platform_staff;
CREATE POLICY platform_staff_select_self ON public.platform_staff
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.platform_staff_audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  staff_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE SET NULL,
  action text NOT NULL,
  target_table text,
  target_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_platform_staff_audit_created
  ON public.platform_staff_audit_log (created_at DESC);

ALTER TABLE public.platform_staff_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS platform_staff_audit_staff_read ON public.platform_staff_audit_log;
CREATE POLICY platform_staff_audit_staff_read ON public.platform_staff_audit_log
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

CREATE OR REPLACE FUNCTION public._staff_audit(
  p_action text,
  p_target_table text DEFAULT NULL,
  p_target_id text DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.platform_staff_audit_log (staff_id, action, target_table, target_id, payload)
  VALUES (auth.uid(), p_action, p_target_table, p_target_id, coalesce(p_payload, '{}'::jsonb));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_platform_staff_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  r public.platform_staff%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  SELECT * INTO r FROM public.platform_staff s WHERE s.user_id = v_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'is_staff', false);
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'is_staff', true,
    'role', r.role,
    'can_finance', r.can_finance,
    'can_moderate', r.can_moderate,
    'can_support', r.can_support
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_platform_staff_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_platform_staff_profile() TO authenticated;

-- =============================================================================
-- 1) كتالوج رسوم المنصة + طلب فوري من الصف لا من رقم ثابت في الواجهة
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.platform_fee_catalog (
  fee_key text PRIMARY KEY,
  amount_sar numeric(10,2) NOT NULL CHECK (amount_sar > 0),
  title_ar text,
  title_en text,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.platform_fee_catalog (fee_key, amount_sar, title_ar, title_en)
VALUES
  ('instant_market_request', 30.00, N'طلب عقاري فوري', 'Instant property request'),
  ('save_card_verify', 1.00, N'حفظ بطاقة — تحقق', 'Save card — verification')
ON CONFLICT (fee_key) DO NOTHING;

ALTER TABLE public.platform_fee_catalog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS platform_fee_catalog_read ON public.platform_fee_catalog;
CREATE POLICY platform_fee_catalog_read ON public.platform_fee_catalog
  FOR SELECT TO authenticated, anon
  USING (true);

CREATE OR REPLACE FUNCTION public.create_instant_market_request_checkout()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bid uuid;
  v_cid uuid;
  v_amt numeric(10,2);
  v_ar text;
  v_en text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  SELECT amount_sar, title_ar, title_en
    INTO v_amt, v_ar, v_en
  FROM public.platform_fee_catalog
  WHERE fee_key = 'instant_market_request';

  IF v_amt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fee_catalog_missing');
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, amount, currency, status, payment_method,
    title_ar, title_en, gateway_response
  ) VALUES (
    v_uid, v_amt, 'SAR', 'pending', 'card',
    coalesce(v_ar, N'طلب عقاري فوري') || N' — ' || v_amt::text || N' ر.س',
    coalesce(v_en, 'Instant property request') || ' — SAR ' || v_amt::text,
    jsonb_build_object(
      'purpose', 'instant_market_request',
      'product', 'aqar_reliable',
      'unit_price_sar', v_amt,
      'fee_key', 'instant_market_request'
    )
  )
  RETURNING id INTO v_bid;

  INSERT INTO public.market_request_instant_credits (
    user_id, billing_transaction_id, amount_sar, status
  ) VALUES (
    v_uid, v_bid, v_amt, 'pending_payment'
  )
  RETURNING id INTO v_cid;

  RETURN jsonb_build_object(
    'ok', true,
    'credit_id', v_cid,
    'billing_transaction_id', v_bid,
    'amount_sar', v_amt,
    'purpose', 'instant_market_request'
  );
END;
$$;

-- =============================================================================
-- 2) منع إدراج/تغيير مبلغ الفاتورة من العميل
-- =============================================================================
DROP POLICY IF EXISTS billing_transactions_insert_own ON public.billing_transactions;

CREATE OR REPLACE FUNCTION public.trg_billing_tx_immutable_amount()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.amount IS DISTINCT FROM OLD.amount THEN
      RAISE EXCEPTION 'amount_immutable';
    END IF;
    -- العميل المسجّل لا يعلّم الفاتورة مدفوعة؛ service_role/webhook يتجاوز (auth.uid() فارغ).
    IF auth.uid() IS NOT NULL
       AND NOT public.is_platform_staff(auth.uid())
       AND OLD.status = 'pending'
       AND NEW.status IN ('paid', 'success', 'completed', 'captured', 'succeeded') THEN
      RAISE EXCEPTION 'status_server_only';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_billing_tx_immutable_amount ON public.billing_transactions;
CREATE TRIGGER tr_billing_tx_immutable_amount
  BEFORE UPDATE ON public.billing_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_billing_tx_immutable_amount();

CREATE OR REPLACE FUNCTION public.create_pending_billing_from_intent(
  p_plan_id uuid,
  p_period text,
  p_with_auto_pay boolean DEFAULT false,
  p_upgrade_subscription_id uuid DEFAULT NULL,
  p_subscription_id uuid DEFAULT NULL,
  p_payment_method text DEFAULT 'card',
  p_card_id uuid DEFAULT NULL,
  p_purpose text DEFAULT 'subscribe',
  p_title_ar text DEFAULT NULL,
  p_title_en text DEFAULT NULL,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_intent jsonb;
  v_charge jsonb;
  v_amt numeric(10,2);
  v_bid uuid;
  v_period text := lower(trim(coalesce(p_period, 'monthly')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  v_charge := public.compute_canonical_charge(
    p_plan_id, v_period, coalesce(p_with_auto_pay, false), p_upgrade_subscription_id
  );
  IF (v_charge->>'ok')::boolean IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('ok', false, 'error',
      coalesce(v_charge->>'error', 'plan_invalid'), 'detail', v_charge);
  END IF;
  v_amt := (v_charge->>'final_amount')::numeric(10,2);

  v_intent := public.validate_payment_intent(
    p_plan_id,
    v_period,
    v_amt,
    coalesce(p_with_auto_pay, false),
    p_upgrade_subscription_id,
    p_idempotency_key
  );

  IF coalesce(v_intent->>'ok', '') IS DISTINCT FROM 'true' THEN
    RETURN v_intent;
  END IF;

  v_amt := coalesce((v_intent->>'expected_amount')::numeric(10,2), v_amt);
  IF v_amt IS NULL OR v_amt < 0.01 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_expected_amount', 'detail', v_intent);
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, subscription_id, amount, currency, status, payment_method, card_id,
    title_ar, title_en, gateway_response
  ) VALUES (
    v_uid,
    p_subscription_id,
    v_amt,
    'SAR',
    'pending',
    coalesce(nullif(trim(p_payment_method), ''), 'card'),
    p_card_id,
    p_title_ar,
    p_title_en,
    jsonb_build_object(
      'pending_gateway', 'moyasar',
      'purpose', coalesce(nullif(trim(p_purpose), ''), 'subscribe'),
      'plan_id', p_plan_id,
      'period', v_period,
      'validated', true,
      'expected_amount', v_amt
    )
  )
  RETURNING id INTO v_bid;

  RETURN jsonb_build_object(
    'ok', true,
    'transaction_id', v_bid,
    'amount', v_amt,
    'expected_amount', v_amt,
    'intent', v_intent
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pending_billing_from_intent(
  uuid, text, boolean, uuid, uuid, text, uuid, text, text, text, text)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_pending_billing_catalog_fee(
  p_fee_key text,
  p_payment_method text DEFAULT 'card',
  p_card_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_amt numeric(10,2);
  v_ar text;
  v_en text;
  v_bid uuid;
  v_key text := lower(trim(coalesce(p_fee_key, '')));
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF v_key NOT IN ('save_card_verify') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fee_key_not_allowed');
  END IF;

  SELECT amount_sar, title_ar, title_en INTO v_amt, v_ar, v_en
  FROM public.platform_fee_catalog WHERE fee_key = v_key;
  IF v_amt IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'fee_catalog_missing');
  END IF;

  INSERT INTO public.billing_transactions (
    user_id, amount, currency, status, payment_method, card_id,
    title_ar, title_en, gateway_response
  ) VALUES (
    v_uid, v_amt, 'SAR', 'pending',
    coalesce(nullif(trim(p_payment_method), ''), 'card'),
    p_card_id, v_ar, v_en,
    jsonb_build_object('purpose', v_key, 'fee_key', v_key, 'validated', true)
  )
  RETURNING id INTO v_bid;

  RETURN jsonb_build_object('ok', true, 'transaction_id', v_bid, 'amount', v_amt);
END;
$$;

REVOKE ALL ON FUNCTION public.create_pending_billing_catalog_fee(text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pending_billing_catalog_fee(text, text, uuid)
  TO authenticated, service_role;

-- =============================================================================
-- 3) بلاغات الإعلان — جدول + حد خادم + تصعيد (كان sql-only)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.listing_user_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties (id) ON DELETE CASCADE,
  reporter_user_id uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  reason_keys jsonb NOT NULL DEFAULT '[]'::jsonb,
  note text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reviewing', 'accepted', 'rejected', 'dismissed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS listing_user_reports_property_id_idx
  ON public.listing_user_reports (property_id);
CREATE INDEX IF NOT EXISTS listing_user_reports_reporter_idx
  ON public.listing_user_reports (reporter_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS listing_user_reports_one_open_per_user_property
  ON public.listing_user_reports (property_id, reporter_user_id)
  WHERE status IN ('pending', 'reviewing') AND reporter_user_id IS NOT NULL;

ALTER TABLE public.listing_user_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS listing_user_reports_insert_own ON public.listing_user_reports;
DROP POLICY IF EXISTS listing_user_reports_select_own ON public.listing_user_reports;
DROP POLICY IF EXISTS listing_user_reports_delete_own_pending ON public.listing_user_reports;
CREATE POLICY listing_user_reports_select_own ON public.listing_user_reports
  FOR SELECT TO authenticated
  USING (
    reporter_user_id = auth.uid()
    OR public.is_platform_staff(auth.uid())
  );
CREATE POLICY listing_user_reports_delete_own_pending ON public.listing_user_reports
  FOR DELETE TO authenticated
  USING (reporter_user_id = auth.uid() AND status = 'pending');
-- الإدراج حصراً عبر RPC submit_listing_report

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS home_feed_suppressed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS report_escalated_at timestamptz,
  ADD COLUMN IF NOT EXISTS report_distinct_reporters_7d integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS permit_issued_at timestamptz,
  ADD COLUMN IF NOT EXISTS selected_marketer_id uuid,
  ADD COLUMN IF NOT EXISTS edit_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_edits integer NOT NULL DEFAULT 3;

CREATE TABLE IF NOT EXISTS public.listing_moderation_escalations (
  property_id uuid PRIMARY KEY REFERENCES public.properties (id) ON DELETE CASCADE,
  distinct_reporters_7d integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved')),
  first_escalated_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.listing_moderation_escalations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS listing_moderation_escalations_staff ON public.listing_moderation_escalations;
CREATE POLICY listing_moderation_escalations_staff ON public.listing_moderation_escalations
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));

CREATE OR REPLACE FUNCTION public.refresh_listing_report_aggregate_for_property(p_property_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  distinct_count integer;
  should_suppress boolean;
BEGIN
  IF p_property_id IS NULL THEN
    RETURN;
  END IF;

  SELECT count(distinct r.reporter_user_id) INTO distinct_count
  FROM public.listing_user_reports r
  WHERE r.property_id = p_property_id
    AND r.reporter_user_id IS NOT NULL
    AND r.status IN ('pending', 'reviewing')
    AND r.created_at > (now() - interval '7 days');

  should_suppress := distinct_count >= 3;

  UPDATE public.properties p
  SET
    report_distinct_reporters_7d = coalesce(distinct_count, 0),
    home_feed_suppressed = should_suppress,
    report_escalated_at = CASE
      WHEN should_suppress THEN coalesce(p.report_escalated_at, now())
      ELSE p.report_escalated_at
    END
  WHERE p.id = p_property_id;

  IF should_suppress THEN
    INSERT INTO public.listing_moderation_escalations (
      property_id, distinct_reporters_7d, status, first_escalated_at, updated_at
    ) VALUES (
      p_property_id, coalesce(distinct_count, 0), 'open', now(), now()
    )
    ON CONFLICT (property_id) DO UPDATE SET
      distinct_reporters_7d = excluded.distinct_reporters_7d,
      status = 'open',
      updated_at = now();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_listing_report(
  p_property_id uuid,
  p_reason_keys jsonb DEFAULT '[]'::jsonb,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid;
  v_hour int;
  v_day int;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;
  IF p_property_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_property');
  END IF;

  SELECT count(*) INTO v_hour
  FROM public.listing_user_reports
  WHERE reporter_user_id = v_uid
    AND created_at > now() - interval '1 hour';
  IF v_hour >= 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'hourly_limit');
  END IF;

  SELECT count(*) INTO v_day
  FROM public.listing_user_reports
  WHERE reporter_user_id = v_uid
    AND created_at > now() - interval '24 hours';
  IF v_day >= 12 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'daily_limit');
  END IF;

  INSERT INTO public.listing_user_reports (
    property_id, reporter_user_id, reason_keys, note, status
  ) VALUES (
    p_property_id, v_uid, coalesce(p_reason_keys, '[]'::jsonb),
    nullif(trim(coalesce(p_note, '')), ''), 'pending'
  )
  RETURNING id INTO v_id;

  PERFORM public.refresh_listing_report_aggregate_for_property(p_property_id);

  RETURN jsonb_build_object(
    'ok', true,
    'id', v_id,
    'stern_warning', v_day >= 4
  );
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'duplicate_open');
END;
$$;

REVOKE ALL ON FUNCTION public.submit_listing_report(uuid, jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_listing_report(uuid, jsonb, text) TO authenticated;

-- =============================================================================
-- 4) RLS تعديل العقار + owner_edit_property
-- =============================================================================
CREATE OR REPLACE FUNCTION public.properties_owner_may_update_listing_body(p public.properties)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    (p).owner_id = auth.uid()
    AND (p).published_at IS NULL
    AND COALESCE(lower(trim((p).status)), '') NOT IN (
      'published', 'active', 'live', 'available', 'approved', 'sold'
    )
    AND COALESCE(lower(trim((p).workflow_stage)), '') NOT IN (
      'permit_pending', 'permit_issued', 'published', 'reserved',
      'cancelled', 'terminated', 'archived', 'inactive_72h', 'contract_cancelled'
    )
    AND (
      (p).edit_count IS NULL
      OR (p).edit_count < COALESCE((p).max_edits, 3)
    );
$$;

DROP POLICY IF EXISTS "properties_owner_admin_update" ON public.properties;
DROP POLICY IF EXISTS "properties_update_owner_marketer_workflow_v1" ON public.properties;
CREATE POLICY "properties_update_owner_marketer_workflow_v1"
  ON public.properties
  FOR UPDATE
  TO authenticated
  USING (
    public.properties_owner_may_update_listing_body(properties)
    OR public.is_platform_staff(auth.uid())
  )
  WITH CHECK (
    public.properties_owner_may_update_listing_body(properties)
    OR public.is_platform_staff(auth.uid())
  );

CREATE OR REPLACE FUNCTION public.owner_edit_property(
  p_property_id uuid,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_city text DEFAULT NULL,
  p_region text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_address_line text DEFAULT NULL,
  p_type text DEFAULT NULL,
  p_price numeric DEFAULT NULL,
  p_area numeric DEFAULT NULL,
  p_currency text DEFAULT NULL,
  p_negotiable boolean DEFAULT NULL,
  p_bedrooms int DEFAULT NULL,
  p_bathrooms int DEFAULT NULL,
  p_parking_spots int DEFAULT NULL,
  p_furnished boolean DEFAULT NULL,
  p_year_built int DEFAULT NULL,
  p_floor int DEFAULT NULL,
  p_total_floors int DEFAULT NULL,
  p_is_auction boolean DEFAULT NULL,
  p_current_bid numeric DEFAULT NULL,
  p_amenities jsonb DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_video_url text DEFAULT NULL,
  p_virtual_tour_url text DEFAULT NULL,
  p_contact_phone text DEFAULT NULL,
  p_reason text DEFAULT NULL,
  p_governorate text DEFAULT NULL,
  p_deed_number text DEFAULT NULL,
  p_deed_date date DEFAULT NULL,
  p_deed_issuer text DEFAULT NULL,
  p_building_number text DEFAULT NULL,
  p_owner_requests_public_name boolean DEFAULT NULL,
  p_listing_guidance jsonb DEFAULT NULL,
  p_extra_details jsonb DEFAULT NULL,
  p_price_includes_vat boolean DEFAULT NULL,
  p_vat_rate numeric DEFAULT NULL,
  p_marketing_commission_kind text DEFAULT NULL,
  p_marketing_commission_rate numeric DEFAULT NULL,
  p_marketing_commission_amount numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  prop public.properties%ROWTYPE;
  v_max int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_property_id IS NULL THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  SELECT * INTO prop FROM public.properties WHERE id = p_property_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'property_not_found';
  END IF;

  IF prop.owner_id IS DISTINCT FROM v_uid
     AND coalesce(prop.published_by_marketer_id, '00000000-0000-0000-0000-000000000000'::uuid)
         IS DISTINCT FROM v_uid
     AND NOT public.is_platform_staff(v_uid) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  IF lower(trim(coalesce(prop.status, ''))) IN ('sold') THEN
    RAISE EXCEPTION 'listing_sold';
  END IF;

  v_max := coalesce(prop.max_edits, 3);
  IF coalesce(prop.edit_count, 0) >= v_max AND NOT public.is_platform_staff(v_uid) THEN
    RAISE EXCEPTION 'EDIT_LIMIT_REACHED';
  END IF;

  UPDATE public.properties SET
    title = coalesce(nullif(trim(p_title), ''), title),
    description = coalesce(p_description, description),
    city = coalesce(nullif(trim(p_city), ''), city),
    region = coalesce(p_region, region),
    location = coalesce(p_location, location),
    address_line = coalesce(p_address_line, address_line),
    type = coalesce(nullif(trim(p_type), ''), type),
    price = coalesce(p_price, price),
    area = coalesce(p_area, area),
    currency = coalesce(nullif(trim(p_currency), ''), currency),
    negotiable = coalesce(p_negotiable, negotiable),
    bedrooms = coalesce(p_bedrooms, bedrooms),
    bathrooms = coalesce(p_bathrooms, bathrooms),
    parking_spots = coalesce(p_parking_spots, parking_spots),
    furnished = coalesce(p_furnished, furnished),
    year_built = coalesce(p_year_built, year_built),
    floor = coalesce(p_floor, floor),
    total_floors = coalesce(p_total_floors, total_floors),
    is_auction = coalesce(p_is_auction, is_auction),
    current_bid = coalesce(p_current_bid, current_bid),
    amenities = coalesce(p_amenities, amenities),
    latitude = coalesce(p_latitude, latitude),
    longitude = coalesce(p_longitude, longitude),
    video_url = coalesce(p_video_url, video_url),
    virtual_tour_url = coalesce(p_virtual_tour_url, virtual_tour_url),
    contact_phone = NULL,
    governorate = coalesce(p_governorate, governorate),
    deed_number = coalesce(p_deed_number, deed_number),
    deed_date = coalesce(p_deed_date, deed_date),
    deed_issuer = coalesce(p_deed_issuer, deed_issuer),
    building_number = coalesce(p_building_number, building_number),
    owner_requests_public_name = coalesce(p_owner_requests_public_name, owner_requests_public_name),
    listing_guidance = coalesce(p_listing_guidance, listing_guidance),
    extra_details = coalesce(p_extra_details, extra_details),
    price_includes_vat = coalesce(p_price_includes_vat, price_includes_vat),
    vat_rate = coalesce(p_vat_rate, vat_rate),
    marketing_commission_kind = coalesce(p_marketing_commission_kind, marketing_commission_kind),
    marketing_commission_rate = coalesce(p_marketing_commission_rate, marketing_commission_rate),
    marketing_commission_amount = coalesce(p_marketing_commission_amount, marketing_commission_amount),
    edit_count = coalesce(edit_count, 0) + 1,
    updated_at = now()
  WHERE id = p_property_id;

  RETURN jsonb_build_object(
    'ok', true,
    'edit_count', coalesce(prop.edit_count, 0) + 1,
    'max_edits', v_max,
    'reason', nullif(trim(coalesce(p_reason, '')), '')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_edit_property(
  uuid, text, text, text, text, text, text, text, numeric, numeric, text, boolean,
  int, int, int, boolean, int, int, int, boolean, numeric, jsonb, double precision,
  double precision, text, text, text, text, text, text, date, text, text, boolean,
  jsonb, jsonb, boolean, numeric, text, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_edit_property(
  uuid, text, text, text, text, text, text, text, numeric, numeric, text, boolean,
  int, int, int, boolean, int, int, int, boolean, numeric, jsonb, double precision,
  double precision, text, text, text, text, text, text, date, text, text, boolean,
  jsonb, jsonb, boolean, numeric, text, numeric, numeric) TO authenticated;

-- =============================================================================
-- 5) get_chat_list2 — إسقاط كل التواقيع ثم توقيع واحد
-- =============================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'get_chat_list2'
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
  END LOOP;
END $$;

CREATE FUNCTION public.get_chat_list2(
  p_limit integer DEFAULT 80,
  p_archived_only boolean DEFAULT false
)
RETURNS TABLE (
  conversation_id uuid,
  kind text,
  title text,
  other_user_id uuid,
  other_full_name text,
  other_phone text,
  other_avatar_url text,
  last_message text,
  last_message_at timestamptz,
  unread_count bigint,
  org_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH me AS (
    SELECT auth.uid() AS uid
  ),
  base_direct AS (
    SELECT
      c.id AS cid,
      c.kind AS k,
      c.title AS ttl,
      c.created_at AS c_created,
      CASE
        WHEN c.user_id = (SELECT uid FROM me) THEN c.counterparty_id
        ELSE c.user_id
      END AS oid,
      c.org_id AS org_pk
    FROM public.conversations c,
         me
    WHERE me.uid IS NOT NULL
      AND c.kind IS DISTINCT FROM 'org_team_channel'
      AND (c.user_id = me.uid OR c.counterparty_id = me.uid)
      AND NOT EXISTS (
        SELECT 1 FROM public.conversation_user_states cus
        WHERE cus.user_id = me.uid
          AND cus.conversation_id = c.id
          AND cus.is_hidden = true
      )
      AND (
        p_archived_only = COALESCE((
          SELECT cus2.is_archived
          FROM public.conversation_user_states cus2
          WHERE cus2.user_id = me.uid AND cus2.conversation_id = c.id
        ), false)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_chat_blocks blk
        WHERE blk.blocker_id = me.uid
          AND blk.blocked_id = CASE
            WHEN c.user_id = me.uid THEN c.counterparty_id
            ELSE c.user_id
          END
      )
  ),
  base_org_channel AS (
    SELECT
      c.id AS cid,
      c.kind AS k,
      c.title AS ttl,
      c.created_at AS c_created,
      ou.owner_user_id AS oid,
      c.org_id AS org_pk
    FROM public.conversations c
    JOIN public.org_memberships m ON m.org_id = c.org_id
    JOIN public.org_units ou ON ou.id = c.org_id,
         me
    WHERE me.uid IS NOT NULL
      AND c.kind = 'org_team_channel'
      AND c.org_id IS NOT NULL
      AND m.user_id = me.uid
      AND m.status = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.org_chat_member_suspensions s
        WHERE s.org_id = c.org_id
          AND s.user_id = me.uid
          AND s.suspended_until > now()
      )
      AND p_archived_only = false
  ),
  base AS (
    SELECT * FROM base_direct
    UNION ALL
    SELECT * FROM base_org_channel
  ),
  last_msg AS (
    SELECT DISTINCT ON (m.conversation_id)
      m.conversation_id AS cid,
      CASE
        WHEN m.deleted_for_everyone_at IS NOT NULL THEN '…'
        ELSE m.content
      END AS body,
      m.created_at AS ts
    FROM public.messages m,
         me
    WHERE m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1 FROM public.message_user_hides h
        WHERE h.message_id = m.id AND h.user_id = me.uid
      )
    ORDER BY m.conversation_id, m.created_at DESC NULLS LAST
  ),
  unread AS (
    SELECT m.conversation_id AS cid, COUNT(*)::bigint AS n
    FROM public.messages m, me
    WHERE me.uid IS NOT NULL
      AND m.receiver_id = me.uid
      AND m.read_at IS NULL
      AND m.deleted_for_everyone_at IS NULL
      AND m.conversation_id IN (SELECT b.cid FROM base b)
      AND NOT EXISTS (
        SELECT 1 FROM public.message_user_hides h
        WHERE h.message_id = m.id AND h.user_id = me.uid
      )
    GROUP BY m.conversation_id
  )
  SELECT
    b.cid AS conversation_id,
    b.k::text AS kind,
    NULLIF(btrim(b.ttl::text), '') AS title,
    b.oid AS other_user_id,
    NULLIF(btrim(COALESCE(up.full_name_ar::text, up.full_name_en::text, up.full_name::text, up.username::text, '')), '') AS other_full_name,
    NULLIF(btrim(up.phone::text), '') AS other_phone,
    NULLIF(btrim(up.avatar_url::text), '') AS other_avatar_url,
    LEFT(btrim(COALESCE(lm.body::text, '')), 500) AS last_message,
    lm.ts AS last_message_at,
    COALESCE(u.n, 0::bigint) AS unread_count,
    b.org_pk AS org_id
  FROM base b
  LEFT JOIN last_msg lm ON lm.cid = b.cid
  LEFT JOIN unread u ON u.cid = b.cid
  LEFT JOIN public.users_profiles up ON up.user_id = b.oid
  ORDER BY COALESCE(lm.ts, b.c_created) DESC NULLS LAST, b.cid DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 80), 200));
$$;

REVOKE ALL ON FUNCTION public.get_chat_list2(integer, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_chat_list2(integer, boolean) TO authenticated;

COMMENT ON FUNCTION public.get_chat_list2(integer, boolean) IS
  'صندوق المحادثات الموحّد — unread_count لا يُصفَّر. لا تُعاد كتابة التواقيع من supabase/sql.';

-- =============================================================================
-- 6) إتمام البيع: completed ≠ paid (دفع بوابة)
-- =============================================================================
ALTER TABLE public.reservations
  ADD COLUMN IF NOT EXISTS deal_completed_at timestamptz;

DO $$
DECLARE cname text;
BEGIN
  FOR cname IN
    SELECT con.conname
    FROM pg_constraint con
    WHERE con.conrelid = 'public.reservations'::regclass
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.reservations DROP CONSTRAINT IF EXISTS %I', cname);
  END LOOP;
  ALTER TABLE public.reservations
    ADD CONSTRAINT reservations_status_check
    CHECK (status IN ('pending', 'paid', 'cancelled', 'expired', 'completed'));
EXCEPTION WHEN others THEN
  RAISE NOTICE 'reservations status check: %', SQLERRM;
END $$;

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
  v_next_status text;
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

  -- صفقة مكتملة ≠ دفع بوابة: paid يبقى إن وُجد تحصيل؛ وإلا completed
  v_next_status := CASE
    WHEN lower(trim(coalesce(rsrv.status, ''))) = 'paid' THEN 'completed'
    ELSE 'completed'
  END;

  UPDATE public.reservations
  SET
    status = v_next_status,
    deal_completed_at = now(),
    updated_at = now()
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
    jsonb_build_object(
      'property_id', p_property_id,
      'reservation_id', rsrv.id,
      'deal_completed', true,
      'gateway_paid', lower(trim(coalesce(rsrv.status, ''))) = 'paid'
    )
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

REVOKE ALL ON FUNCTION public.complete_property_sale(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_property_sale(uuid) TO authenticated;

-- =============================================================================
-- 7) تجديد فال: يتطلب اشتراكاً مدفوعاً فعّالاً — ليس مجاناً
-- =============================================================================
CREATE OR REPLACE FUNCTION public.org_renew_fal_license()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_org uuid;
  v_code text;
  v_paid boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;
  SELECT id INTO v_org FROM public.org_units WHERE owner_user_id = v_uid LIMIT 1;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_org_owner');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_subscriptions s
    JOIN public.subscription_plans p ON p.id = s.plan_id
    WHERE s.user_id = v_uid
      AND s.status IN ('active')
      AND coalesce(s.end_date, current_date) >= current_date
      AND coalesce(p.is_trial_plan, false) = false
      AND coalesce(p.sort_order, 0) NOT IN (11, 12, 13, 21, 22, 23)
  ) INTO v_paid;

  IF NOT v_paid THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'paid_subscription_required',
      'message_ar', 'تجديد رخصة فال المعروضة يتطلب اشتراكاً مدفوعاً فعّالاً.',
      'message_en', 'Display FAL renewal requires an active paid subscription.'
    );
  END IF;

  v_code := public.gen_org_fal_public_code();
  UPDATE public.org_units SET
    fal_public_code = v_code,
    fal_license_expires_at = now() + interval '1 year',
    updated_at = now()
  WHERE id = v_org;

  PERFORM public._staff_audit(
    'org_renew_fal_license', 'org_units', v_org::text,
    jsonb_build_object('self_renew', true)
  );

  RETURN jsonb_build_object('ok', true, 'fal_public_code', v_code);
END;
$$;

-- مقاعد إضافية تبقى معطّلة وفق السياسة التجارية (حساب واحد لكل باقة)
CREATE OR REPLACE FUNCTION public.org_purchase_extra_seats_priced(
  p_extra int,
  p_billing_transaction_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'ok', false,
    'error', 'seats_disabled',
    'message_ar', 'إضافة أعضاء/مقاعد غير متاحة — كل باقة لحساب واحد.',
    'message_en', 'Extra seats are disabled — one account per subscription.'
  );
END;
$$;

-- =============================================================================
-- 8) موظف المنصة: رد تذكرة + طابور بلاغات + حالة اشتراك (تدقيق، بلا تعديل صف مباشر)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.platform_staff_reply_complaint(
  p_complaint_id uuid,
  p_reply text,
  p_status text DEFAULT 'awaiting_user'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_reply text := trim(coalesce(p_reply, ''));
  v_status text := lower(trim(coalesce(p_status, 'awaiting_user')));
  r public.regc_user_complaints%ROWTYPE;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_support FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_support');
  END IF;
  IF length(v_reply) < 2 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reply_required');
  END IF;
  IF v_status NOT IN ('open', 'awaiting_user', 'escalated', 'resolved', 'closed') THEN
    v_status := 'awaiting_user';
  END IF;

  SELECT * INTO r FROM public.regc_user_complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  UPDATE public.regc_user_complaints
  SET
    status = v_status,
    details = coalesce(details, '{}'::jsonb) || jsonb_build_object(
      'admin_reply', v_reply,
      'admin_reply_at', to_jsonb(now()),
      'admin_reply_by', v_staff
    )
  WHERE id = p_complaint_id;

  PERFORM public._staff_audit(
    'support_reply', 'regc_user_complaints', p_complaint_id::text,
    jsonb_build_object('status', v_status)
  );

  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_complaints(p_limit int DEFAULT 80)
RETURNS SETOF public.regc_user_complaints
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT *
    FROM public.regc_user_complaints
    ORDER BY created_at DESC
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 80), 200));
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_list_listing_reports(p_limit int DEFAULT 80)
RETURNS SETOF public.listing_user_reports
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_staff(auth.uid()) THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT *
    FROM public.listing_user_reports
    WHERE status IN ('pending', 'reviewing')
    ORDER BY created_at DESC
    LIMIT GREATEST(1, LEAST(coalesce(p_limit, 80), 200));
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_review_listing_report(
  p_report_id uuid,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_dec text := lower(trim(coalesce(p_decision, '')));
  r public.listing_user_reports%ROWTYPE;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_moderate FROM public.platform_staff s WHERE s.user_id = v_staff), true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_moderate');
  END IF;
  IF v_dec NOT IN ('accepted', 'rejected', 'dismissed', 'reviewing') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_decision');
  END IF;

  SELECT * INTO r FROM public.listing_user_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  UPDATE public.listing_user_reports
  SET status = v_dec, note = CASE
    WHEN nullif(trim(coalesce(p_note, '')), '') IS NULL THEN note
    ELSE coalesce(note || E'\n', '') || trim(p_note)
  END
  WHERE id = p_report_id;

  PERFORM public.refresh_listing_report_aggregate_for_property(r.property_id);
  PERFORM public._staff_audit(
    'listing_report_review', 'listing_user_reports', p_report_id::text,
    jsonb_build_object('decision', v_dec)
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_staff_set_subscription_status(
  p_subscription_id uuid,
  p_status text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff uuid := auth.uid();
  v_status text := lower(trim(coalesce(p_status, '')));
  r public.user_subscriptions%ROWTYPE;
BEGIN
  IF v_staff IS NULL OR NOT public.is_platform_staff(v_staff) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF NOT coalesce((SELECT s.can_finance FROM public.platform_staff s WHERE s.user_id = v_staff), false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden_finance');
  END IF;
  IF v_status NOT IN ('active', 'cancelled', 'expired') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'bad_status');
  END IF;
  IF length(trim(coalesce(p_reason, ''))) < 4 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reason_required');
  END IF;

  SELECT * INTO r FROM public.user_subscriptions WHERE id = p_subscription_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;

  UPDATE public.user_subscriptions
  SET
    status = v_status,
    cancelled_at = CASE WHEN v_status = 'cancelled' THEN now() ELSE cancelled_at END,
    updated_at = now()
  WHERE id = p_subscription_id;

  PERFORM public._staff_audit(
    'subscription_status', 'user_subscriptions', p_subscription_id::text,
    jsonb_build_object('from', r.status, 'to', v_status, 'reason', trim(p_reason))
  );
  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.platform_staff_reply_complaint(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_list_complaints(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_list_listing_reports(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_review_listing_report(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.platform_staff_set_subscription_status(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.platform_staff_reply_complaint(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_complaints(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_list_listing_reports(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_review_listing_report(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_staff_set_subscription_status(uuid, text, text) TO authenticated;

COMMIT;
