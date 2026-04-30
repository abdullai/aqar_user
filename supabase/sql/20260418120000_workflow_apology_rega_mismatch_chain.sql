-- =============================================================================
-- سلسلة سير العمل: تمييز «اعتذار المالك» عن «الرفض» (لا يُحسب ضمن حد 3 رفض)
-- + تتبع محاولات عدم مطابقة ترخيص REGA مع فسخ العقد تلقائياً بعد 3 محاولات
-- نفّذ بعد: 20260451_owner_decline_cap_relist_ban_permit_reopen.sql
-- =============================================================================

BEGIN;

ALTER TABLE public.listing_offers
  ADD COLUMN IF NOT EXISTS decline_kind text NOT NULL DEFAULT 'reject';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listing_offers_decline_kind_check'
  ) THEN
    ALTER TABLE public.listing_offers
      ADD CONSTRAINT listing_offers_decline_kind_check
      CHECK (decline_kind IN ('reject', 'apology'));
  END IF;
END $$;

COMMENT ON COLUMN public.listing_offers.decline_kind IS
  'reject = رفض يُحسب في حد 3 مسوّقين؛ apology = اعتذار لا يُحسب ويُبلّغ المسوّق بلهجة أخف.';

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS rega_mismatch_attempts integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.listing_requests.rega_mismatch_attempts IS
  'عدد بلاغات عدم مطابقة ترخيص الإعلان مع فال/الهيئة؛ عند 3 يُفسَخ العقد غير الموقّع.';

-- ---------------------------------------------------------------------------
-- owner_decline_listing_offer — باراميتر نوع الإجراء (الوسيط الثالث له افتراضي = رفض)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.owner_decline_listing_offer(uuid, text);
DROP FUNCTION IF EXISTS public.owner_decline_listing_offer(uuid, text, text);

CREATE OR REPLACE FUNCTION public.owner_decline_listing_offer(
  p_offer_id uuid,
  p_reason text DEFAULT NULL,
  p_decline_kind text DEFAULT 'reject'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  off record;
  req record;
  v_reason text;
  body_ar text;
  v_round int;
  v_distinct int;
  v_kind text := lower(trim(coalesce(p_decline_kind, 'reject')));
  notif_title text;
  notif_type text;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF v_kind NOT IN ('reject', 'apology') THEN
    v_kind := 'reject';
  END IF;

  SELECT * INTO off FROM public.listing_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = off.request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_owner';
  END IF;

  IF coalesce(req.banned_under_review, false) THEN
    RAISE EXCEPTION 'listing_banned_under_review';
  END IF;

  IF coalesce(off.status, '') NOT IN ('submitted', 'pending', '') THEN
    RAISE EXCEPTION 'offer_not_pending';
  END IF;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');
  v_round := coalesce(req.marketing_round, 1);

  UPDATE public.listing_offers
  SET
    status = 'declined',
    decline_kind = v_kind,
    owner_decline_reason = v_reason,
    updated_at = now()
  WHERE id = p_offer_id;

  -- حد 3 رفض لمسوّقين مميزين: يُحسب «reject» فقط
  IF v_kind = 'reject' THEN
    SELECT COUNT(DISTINCT marketer_id)::int INTO v_distinct
    FROM public.listing_offers o
    WHERE o.request_id = off.request_id
      AND coalesce(o.round_no, 1) = v_round
      AND o.status = 'declined'
      AND coalesce(o.decline_kind, 'reject') = 'reject';

    IF v_distinct >= 3 THEN
      UPDATE public.listing_offers o
      SET
        status = 'owner_rejected',
        updated_at = now()
      WHERE o.request_id = off.request_id
        AND coalesce(o.round_no, 1) = v_round
        AND o.id <> p_offer_id
        AND o.status IN ('submitted', 'pending');

      UPDATE public.listing_requests lr
      SET
        owner_distinct_marketer_declines = v_distinct,
        workflow_stage = 'cancelled',
        status = 'cancelled',
        banned_under_review = true,
        needs_manual_review = true,
        updated_at = now()
      WHERE lr.id = off.request_id;

      PERFORM public.workflow_create_notification(
        uid,
        'listing_offer_decline_limit',
        'توقف الطلب بعد 3 رفض لمسوّقين',
        'رُفضت عروض ثلاثة مسوّقين مميزين في هذه الجولة. أُوقف الطلب للمراجعة.',
        'listing_request',
        off.request_id,
        jsonb_build_object(
          'request_id', off.request_id,
          'deep_route', 'listing_request_status',
          'main_tab', 'my_ads',
          'role', 'owner',
          'owner_distinct_marketer_declines', v_distinct
        )
      );
    ELSE
      UPDATE public.listing_requests lr
      SET
        owner_distinct_marketer_declines = v_distinct,
        updated_at = now()
      WHERE lr.id = off.request_id;
    END IF;
  ELSE
    -- اعتذار: لا يغيّر عدّاد الرفض
    UPDATE public.listing_requests lr
    SET updated_at = now()
    WHERE lr.id = off.request_id;
  END IF;

  IF v_kind = 'apology' THEN
    notif_title := 'اعتذار من المالك عن العرض';
    IF v_reason IS NULL THEN
      body_ar := 'اعتذر المالك عن عرضك على هذا الطلب. يمكنك مراجعة طلبات أخرى أو إعادة التقديم لاحقاً.';
    ELSE
      body_ar := 'اعتذر المالك عن عرضك. السبب: ' || v_reason;
    END IF;
    notif_type := 'offer_apology_from_owner';
  ELSE
    notif_title := 'تم رفض عرضك';
    IF v_reason IS NULL THEN
      body_ar := 'رفض المالك عرضك. يمكنك متابعة طلبات أخرى.';
    ELSE
      body_ar := 'رفض المالك عرضك. السبب: ' || v_reason;
    END IF;
    notif_type := 'offer_declined';
  END IF;

  PERFORM public.workflow_create_notification(
    off.marketer_id,
    notif_type,
    notif_title,
    body_ar,
    'listing_request',
    off.request_id,
    jsonb_build_object(
      'request_id', off.request_id,
      'offer_id', p_offer_id,
      'deep_route', 'listing_request_status',
      'main_tab', 'my_ads',
      'role', 'marketer',
      'owner_decline_reason', v_reason,
      'decline_kind', v_kind
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_decline_listing_offer(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_decline_listing_offer(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- بلاغ عدم مطابقة REGA — يزيد العداد وقد يُلغي العقد بعد 3 محاولات
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.report_rega_license_mismatch(p_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  req record;
  c record;
  v_n int;
  v_legal text :=
    'فسخ عقد التسويق لعدم مطابقة بيانات ترخيص الإعلان مع رخصة فال وفق بلاغات متكررة (3). '
    || 'يحق للمعلن المطالبة بالتعويض أمام الجهات المختصة حسب الأنظمة المعمول بها.';
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT * INTO req FROM public.listing_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF req.owner_id IS DISTINCT FROM uid AND req.selected_marketer_id IS DISTINCT FROM uid THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;

  UPDATE public.listing_requests
  SET
    rega_mismatch_attempts = coalesce(rega_mismatch_attempts, 0) + 1,
    updated_at = now()
  WHERE id = p_request_id
  RETURNING * INTO req;

  v_n := coalesce(req.rega_mismatch_attempts, 0);

  IF v_n < 3 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'attempts', v_n,
      'contract_voided', false
    );
  END IF;

  -- ثلاث محاولات: إلغاء عقد غير موقّع إن وُجد
  IF req.contract_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok', true,
      'attempts', v_n,
      'contract_voided', false,
      'note', 'no_contract'
    );
  END IF;

  SELECT * INTO c FROM public.listing_contracts WHERE id = req.contract_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'attempts', v_n, 'contract_voided', false, 'note', 'contract_missing');
  END IF;

  IF c.status::text = 'signed' THEN
    RAISE EXCEPTION 'contract_already_signed';
  END IF;

  UPDATE public.listing_contracts
  SET
    status = 'cancelled'::contract_status,
    cancelled_at = now(),
    cancelled_reason = v_legal,
    updated_at = now()
  WHERE id = c.id;

  UPDATE public.listing_requests lr
  SET
    workflow_stage = 'contract_cancelled',
    contract_id = NULL,
    selected_offer_id = NULL,
    selected_marketer_id = NULL,
    permit_deadline_at = NULL,
    rega_mismatch_attempts = 0,
    updated_at = now()
  WHERE lr.id = p_request_id;

  PERFORM public.workflow_create_notification(
    req.owner_id,
    'rega_mismatch_contract_voided',
    'إنهاء عقد التسويق — عدم مطابقة REGA',
    v_legal,
    'listing_request',
    p_request_id,
    jsonb_build_object('request_id', p_request_id, 'void_reason', 'rega_mismatch_3')
  );

  IF c.marketer_id IS NOT NULL THEN
    PERFORM public.workflow_create_notification(
      c.marketer_id,
      'rega_mismatch_contract_voided',
      'إنهاء عقد التسويق — عدم مطابقة REGA',
      v_legal,
      'listing_request',
      p_request_id,
      jsonb_build_object('request_id', p_request_id, 'void_reason', 'rega_mismatch_3')
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'attempts', v_n,
    'contract_voided', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.report_rega_license_mismatch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.report_rega_license_mismatch(uuid) TO authenticated;

COMMIT;
