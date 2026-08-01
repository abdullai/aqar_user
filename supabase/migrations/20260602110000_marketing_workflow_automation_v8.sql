-- =============================================================================
-- 2026-06-02 — أتمتة وحوكمة دورة حياة العرض/التصريح/العقد (v8)
-- =============================================================================
-- يضيف هذا الترحيل خمس دوائر آلية متكاملة:
--
--   (1) زر «إشعار آخر» للمسوّق على عرضه إذا لم يَردّ المالك خلال 48 ساعة:
--       • RPC marketer_send_offer_last_call(p_offer_id) — يُرسل إشعاراً
--         صوتيّاً للمالك ويُجدّد expires_at للعرض. ممنوع إن كان المالك
--         اختار مسوّقاً آخر، أو إن مَضى أقل من 48h على آخر إشعار.
--
--   (2) أتمتة 72 ساعة للتصاريح (permit_pending):
--       • cron_expire_marketer_permit_72h() يُحوّل المرحلة من permit_pending
--         (مع انتهاء permit_deadline_at) إلى owner_action_required ويُسجّل
--         inactive_72h_at على listing_requests. التصاريح تختفي تلقائياً من
--         تبويب المسوّق ويَظهر على لوحة المالك زر «إعادة للسوق».
--
--   (3) أتمتة 72 ساعة للعقود (contract_sent بدون توقيع):
--       • cron_expire_marketer_contract_72h() يفسخ العقد تلقائياً ويَدخل
--         الطلب في owner_action_required. يَترك بصمة قانونية على العقد.
--
--   (4) RPC owner_return_request_to_market(p_request_id, p_allow_same_marketer):
--       • يُعيد الطلب لحالة waiting_marketers، ويَستثني المسوّق السابق إن
--         اختار المالك ذلك. يَفسخ أي عقد قائم.
--
--   (5) إخفاء العروض الخاسرة بعد اختيار مسوّق ونشر العقار:
--       • الدالة _mark_losing_offers_after_selection() تَضع status='lost'
--         لكل العروض غير المختارة بعد marketer_selected/published.
--       • View public.v_visible_marketer_offers يَستثني lost للمسوّق
--         غير المختار.
--
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- (A) أعمدة جديدة على listing_offers
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_offers
  ADD COLUMN IF NOT EXISTS last_call_count int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_call_at timestamptz,
  ADD COLUMN IF NOT EXISTS lost_at timestamptz,
  ADD COLUMN IF NOT EXISTS lost_reason text;

CREATE INDEX IF NOT EXISTS idx_listing_offers_last_call
  ON public.listing_offers (request_id, last_call_at);

CREATE INDEX IF NOT EXISTS idx_listing_offers_lost
  ON public.listing_offers (request_id, lost_at);

-- ---------------------------------------------------------------------------
-- (B) أعمدة جديدة على listing_requests للأتمتة
-- ---------------------------------------------------------------------------
ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS owner_action_required_at timestamptz,
  ADD COLUMN IF NOT EXISTS owner_action_reason text,
  ADD COLUMN IF NOT EXISTS contract_deadline_at timestamptz,
  ADD COLUMN IF NOT EXISTS prev_selected_marketer_id uuid,
  ADD COLUMN IF NOT EXISTS auto_expired_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_listing_requests_owner_action
  ON public.listing_requests (owner_action_required_at)
  WHERE owner_action_required_at IS NOT NULL;

-- ---------------------------------------------------------------------------
-- (C) RPC: marketer_send_offer_last_call
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketer_send_offer_last_call(
  p_offer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer record;
  v_req record;
  v_min_gap interval := interval '48 hours';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_offer
  FROM public.listing_offers
  WHERE id = p_offer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  -- مالك العرض هو المسوّق الذي قدّمه
  IF v_offer.marketer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'not_offer_owner';
  END IF;

  -- العرض يجب أن يكون submitted فقط
  IF lower(coalesce(v_offer.status,'')) NOT IN ('submitted','pending') THEN
    RAISE EXCEPTION 'offer_not_active';
  END IF;

  SELECT * INTO v_req
  FROM public.listing_requests
  WHERE id = v_offer.request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  -- إن اختار المالك مسوّقاً آخر → ممنوع
  IF v_req.selected_marketer_id IS NOT NULL
     AND v_req.selected_marketer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'owner_selected_other_marketer';
  END IF;

  -- 48 ساعة بين كل إشعارَين
  IF v_offer.last_call_at IS NOT NULL
     AND (now() - v_offer.last_call_at) < v_min_gap THEN
    RAISE EXCEPTION 'last_call_cooldown: %',
      to_char(v_offer.last_call_at + v_min_gap, 'YYYY-MM-DD HH24:MI');
  END IF;

  -- جدّد العرض + سجّل الإشعار
  UPDATE public.listing_offers
     SET expires_at = now() + interval '48 hours',
         last_call_count = coalesce(last_call_count,0) + 1,
         last_call_at = now(),
         updated_at = now()
   WHERE id = p_offer_id;

  -- إشعار صوتي للمالك (sound=last_call → الواجهة تختار chime مميّزاً)
  PERFORM public.workflow_create_notification(
    v_req.owner_id,
    'marketing.offer.last_call',
    'تذكير عاجل بعرض جديد',
    'لديك عرض من مسوّق ينتظر ردك خلال 48 ساعة.',
    'listing_request',
    v_req.id,
    jsonb_build_object(
      'offer_id', p_offer_id,
      'marketer_id', v_uid,
      'sound', 'last_call',
      'priority', 'high'
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'offer_id', p_offer_id,
    'expires_at', now() + interval '48 hours',
    'last_call_count', coalesce(v_offer.last_call_count,0) + 1
  );
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_send_offer_last_call(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_send_offer_last_call(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (D) RPC: marketer_can_send_last_call (للواجهة لإظهار/إخفاء الزر)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marketer_can_send_last_call(
  p_offer_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer record;
  v_req record;
  v_next_at timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'allow', false, 'reason', 'auth_required');
  END IF;

  SELECT * INTO v_offer FROM public.listing_offers WHERE id = p_offer_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'allow', false, 'reason', 'offer_not_found');
  END IF;

  IF v_offer.marketer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('ok', false, 'allow', false, 'reason', 'not_owner');
  END IF;

  IF lower(coalesce(v_offer.status,'')) NOT IN ('submitted','pending') THEN
    RETURN jsonb_build_object('ok', false, 'allow', false, 'reason', 'offer_not_active');
  END IF;

  SELECT * INTO v_req FROM public.listing_requests WHERE id = v_offer.request_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'allow', false, 'reason', 'request_not_found');
  END IF;

  IF v_req.selected_marketer_id IS NOT NULL
     AND v_req.selected_marketer_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('ok', true, 'allow', false, 'reason', 'owner_selected_other');
  END IF;

  v_next_at := coalesce(v_offer.last_call_at, v_offer.created_at) + interval '48 hours';

  IF v_offer.last_call_at IS NOT NULL AND now() < v_next_at THEN
    RETURN jsonb_build_object(
      'ok', true,
      'allow', false,
      'reason', 'cooldown',
      'next_at', v_next_at,
      'last_call_count', coalesce(v_offer.last_call_count,0)
    );
  END IF;

  -- نسمح ببداية العدّ بعد 48 ساعة من تقديم العرض
  IF v_offer.last_call_at IS NULL
     AND now() < (v_offer.created_at + interval '48 hours') THEN
    RETURN jsonb_build_object(
      'ok', true,
      'allow', false,
      'reason', 'before_first_window',
      'next_at', v_offer.created_at + interval '48 hours',
      'last_call_count', 0
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'allow', true,
    'last_call_count', coalesce(v_offer.last_call_count,0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.marketer_can_send_last_call(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marketer_can_send_last_call(uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (E) دالة مساعدة: تعليم العروض الخاسرة بعد اختيار مسوّق
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._mark_losing_offers_for_request(
  p_request_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req record;
  v_n int := 0;
BEGIN
  SELECT * INTO v_req FROM public.listing_requests WHERE id = p_request_id;
  IF NOT FOUND OR v_req.selected_marketer_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.listing_offers
     SET status = 'rejected',
         lost_at = now(),
         lost_reason = 'owner_selected_other_marketer',
         updated_at = now()
   WHERE request_id = p_request_id
     AND marketer_id IS DISTINCT FROM v_req.selected_marketer_id
     AND lower(coalesce(status,'')) IN ('submitted','pending');

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public._mark_losing_offers_for_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._mark_losing_offers_for_request(uuid)
  TO authenticated, service_role;

-- Trigger: عند ضبط selected_marketer_id لأول مرة، علّم الباقي خاسراً
CREATE OR REPLACE FUNCTION public._tr_listing_requests_mark_losing()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.selected_marketer_id IS NOT NULL
     AND (OLD.selected_marketer_id IS NULL
          OR OLD.selected_marketer_id IS DISTINCT FROM NEW.selected_marketer_id) THEN
    PERFORM public._mark_losing_offers_for_request(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_listing_requests_mark_losing
  ON public.listing_requests;

CREATE TRIGGER tr_listing_requests_mark_losing
  AFTER UPDATE OF selected_marketer_id
  ON public.listing_requests
  FOR EACH ROW
  EXECUTE FUNCTION public._tr_listing_requests_mark_losing();

-- ---------------------------------------------------------------------------
-- (F) Cron: انتهاء 72 ساعة للتصاريح (permit_pending)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_marketer_permit_72h()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT id, owner_id, selected_marketer_id, permit_deadline_at
      FROM public.listing_requests
     WHERE lower(trim(coalesce(workflow_stage,''))) IN
           ('permit_pending','awaiting_permits','pending_permits')
       AND permit_deadline_at IS NOT NULL
       AND permit_deadline_at < now()
       AND owner_action_required_at IS NULL
     LIMIT 500
  LOOP
    UPDATE public.listing_requests
       SET workflow_stage = 'owner_action_required',
           owner_action_required_at = now(),
           owner_action_reason = 'permit_72h_expired',
           inactive_72h_at = now(),
           prev_selected_marketer_id = selected_marketer_id,
           selected_marketer_id = NULL,
           auto_expired_at = now(),
           updated_at = now()
     WHERE id = r.id;

    -- ألغِ التصاريح المعلّقة لهذا الطلب
    UPDATE public.listing_permits
       SET status = 'rejected',
           notes = coalesce(notes,'') || ' [auto-expired-72h]',
           updated_at = now()
     WHERE request_id = r.id
       AND status::text NOT IN ('approved','rejected');

    -- إشعار للمالك بزر «إعادة للسوق»
    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'workflow.permit.expired_72h',
        'انتهت مهلة التصريح 72 ساعة',
        'لم يُرفع التصريح خلال 72 ساعة. يمكنك إعادة الطلب للسوق الآن.',
        'listing_request',
        r.id,
        jsonb_build_object('reason','permit_72h_expired','priority','high')
      );
    END IF;

    -- إشعار للمسوّق السابق (لتنبيهه أن البطاقة اختفت من قائمته)
    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'workflow.permit.lost_72h',
        'انتهت مهلتك للتصريح',
        'انتهت مهلة 72 ساعة لرفع التصريح ولن يَظهر هذا الطلب في قوائمك.',
        'listing_request',
        r.id,
        jsonb_build_object('reason','permit_72h_expired')
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'expired_count', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_marketer_permit_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_marketer_permit_72h()
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (G) Cron: انتهاء 72 ساعة للعقد (contract_sent بدون توقيع)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_expire_marketer_contract_72h()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT lr.id, lr.owner_id, lr.selected_marketer_id, lr.contract_sent_at
      FROM public.listing_requests lr
     WHERE lower(trim(coalesce(lr.workflow_stage,''))) IN
           ('contract_sent','awaiting_contract','pending_owner')
       AND lr.contract_sent_at IS NOT NULL
       AND (now() - lr.contract_sent_at) > interval '72 hours'
       AND lr.contract_signed_at IS NULL
       AND lr.owner_action_required_at IS NULL
     LIMIT 500
  LOOP
    UPDATE public.listing_requests
       SET workflow_stage = 'owner_action_required',
           owner_action_required_at = now(),
           owner_action_reason = 'contract_72h_expired',
           inactive_72h_at = now(),
           prev_selected_marketer_id = selected_marketer_id,
           selected_marketer_id = NULL,
           auto_expired_at = now(),
           updated_at = now()
     WHERE id = r.id;

    -- فسخ أي عقد قائم لم يُوقَّع: نَستخدم status='cancelled' (contract_status)
    -- ونَترك بصمة قانونية في extra_margin_notes.
    UPDATE public.listing_contracts
       SET status = 'cancelled'::contract_status,
           cancelled_at = now(),
           cancelled_reason = 'auto_expired_72h_unsigned',
           extra_margin_notes = coalesce(extra_margin_notes,'') ||
             E'\n— هامش قانوني: فُسخ هذا العقد تلقائياً نظراً لانقضاء 72 ساعة دون توقيع من المالك.',
           updated_at = now()
     WHERE request_id = r.id
       AND cancelled_at IS NULL
       AND status::text NOT IN ('signed','cancelled','terminated');

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'workflow.contract.expired_72h',
        'انتهت مهلة توقيع العقد',
        'لم يُوقَّع العقد خلال 72 ساعة. يمكنك إعادة الطلب للسوق الآن.',
        'listing_request',
        r.id,
        jsonb_build_object('reason','contract_72h_expired','priority','high')
      );
    END IF;

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'workflow.contract.lost_72h',
        'انتهت مهلة العقد',
        'لم يُوقَّع العقد خلال 72 ساعة وتم إخفاؤه من قائمتك.',
        'listing_request',
        r.id,
        jsonb_build_object('reason','contract_72h_expired')
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'expired_count', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_marketer_contract_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_marketer_contract_72h()
  TO authenticated, service_role;

-- مُجمِّع: ينفّذ الكلّ (يَستدعى من Edge Function أو pg_cron)
CREATE OR REPLACE FUNCTION public.cron_run_72h_workflow_expirations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p jsonb;
  v_c jsonb;
BEGIN
  v_p := public.cron_expire_marketer_permit_72h();
  v_c := public.cron_expire_marketer_contract_72h();
  RETURN jsonb_build_object(
    'ok', true,
    'permits', v_p,
    'contracts', v_c,
    'ran_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.cron_run_72h_workflow_expirations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_run_72h_workflow_expirations()
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (H) RPC: owner_return_request_to_market — المالك يُعيد الطلب للسوق
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_return_request_to_market(
  p_request_id uuid,
  p_allow_same_marketer boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req record;
  v_round int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth_required';
  END IF;

  SELECT * INTO v_req
  FROM public.listing_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found';
  END IF;

  IF v_req.owner_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'not_request_owner';
  END IF;

  IF v_req.owner_action_required_at IS NULL THEN
    RAISE EXCEPTION 'no_owner_action_pending';
  END IF;

  v_round := coalesce(v_req.marketing_round, 1) + 1;

  -- استثنِ المسوّق السابق إن لم يَسمح المالك بإعادة محاولته
  IF v_req.prev_selected_marketer_id IS NOT NULL AND NOT coalesce(p_allow_same_marketer, false) THEN
    INSERT INTO public.listing_request_marketer_exclusions (
      listing_request_id, marketer_id, round_no, reason, can_retry
    )
    VALUES (
      p_request_id, v_req.prev_selected_marketer_id, v_round,
      coalesce(v_req.owner_action_reason, 'owner_excluded'), false
    )
    ON CONFLICT (listing_request_id, marketer_id, round_no) DO NOTHING;
  END IF;

  -- أعِد الطلب لحالة waiting_marketers
  UPDATE public.listing_requests
     SET workflow_stage = 'waiting_marketers',
         marketing_round = v_round,
         relist_count = coalesce(relist_count,0) + 1,
         waiting_marketers_since = now(),
         owner_action_required_at = NULL,
         owner_action_reason = NULL,
         inactive_72h_at = NULL,
         contract_started_at = NULL,
         contract_sent_at = NULL,
         contract_signed_at = NULL,
         contract_deadline_at = NULL,
         permit_deadline_at = NULL,
         selected_offer_id = NULL,
         selected_marketer_id = NULL,
         allow_previous_marketers_retry = coalesce(p_allow_same_marketer, false),
         updated_at = now()
   WHERE id = p_request_id;

  -- علّم العروض المعلّقة كـ withdrawn (المالك أعاد للسوق)
  UPDATE public.listing_offers
     SET status = 'withdrawn',
         lost_at = now(),
         lost_reason = 'returned_to_market',
         updated_at = now()
   WHERE request_id = p_request_id
     AND lower(coalesce(status,'')) IN ('submitted','pending');

  RETURN jsonb_build_object(
    'ok', true,
    'request_id', p_request_id,
    'round_no', v_round,
    'allow_same_marketer', coalesce(p_allow_same_marketer, false),
    'excluded_marketer_id',
      CASE WHEN p_allow_same_marketer THEN NULL ELSE v_req.prev_selected_marketer_id END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.owner_return_request_to_market(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.owner_return_request_to_market(uuid, boolean)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- (I) View: العروض المرئية لكل مسوّق (يستثني الخاسرة عن غير المختار)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_marketer_visible_offers AS
SELECT lo.*,
       lr.selected_marketer_id AS req_selected_marketer_id,
       lr.workflow_stage       AS req_workflow_stage
  FROM public.listing_offers lo
  JOIN public.listing_requests lr ON lr.id = lo.request_id
 WHERE lo.lost_at IS NULL
    OR lr.selected_marketer_id = lo.marketer_id;

GRANT SELECT ON public.v_marketer_visible_offers TO authenticated;

-- ---------------------------------------------------------------------------
-- (J) تشخيص نهائي
-- ---------------------------------------------------------------------------
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'marketer_send_offer_last_call',
      'marketer_can_send_last_call',
      'cron_expire_marketer_permit_72h',
      'cron_expire_marketer_contract_72h',
      'cron_run_72h_workflow_expirations',
      'owner_return_request_to_market',
      '_mark_losing_offers_for_request'
    );
  RAISE NOTICE '== v8 functions installed: %/7', v_n;
END $$;

COMMIT;

-- =============================================================================
-- جدولة Cron (يدوياً عبر Supabase pg_cron — أو من Edge Function كل 10 دقائق):
--
--   SELECT cron.schedule(
--     'workflow-expirations-72h',
--     '*/10 * * * *',
--     $$ SELECT public.cron_run_72h_workflow_expirations(); $$
--   );
--
-- بدون pg_cron: استدعِ public.cron_run_72h_workflow_expirations() من Edge
-- Function تَعمل كل 10 دقائق عبر Supabase Scheduled Functions.
-- =============================================================================
