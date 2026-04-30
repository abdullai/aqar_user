-- تحديث نص إشعار المالك عند انتهاء مهلة التصريح (72 ساعة) ليطابق الصياغة النظامية.
BEGIN;

CREATE OR REPLACE FUNCTION public.cron_expire_permit_pending_72h()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT
      lr.id,
      lr.owner_id,
      lr.contract_id,
      lr.selected_marketer_id
    FROM public.listing_requests lr
    WHERE coalesce(lr.workflow_stage, '') IN (
        'permit_pending', 'awaiting_permits', 'pending_permits'
      )
      AND lr.permit_deadline_at IS NOT NULL
      AND lr.permit_deadline_at < now()
    FOR UPDATE OF lr SKIP LOCKED
  LOOP
    n := n + 1;

    UPDATE public.listing_offers o
    SET status = 'cancelled',
        updated_at = now()
    WHERE o.request_id = r.id
      AND o.status IN ('submitted', 'pending', 'expired');

    IF r.contract_id IS NOT NULL THEN
      UPDATE public.listing_contracts lc
      SET
        status = 'cancelled'::contract_status,
        cancelled_at = COALESCE(lc.cancelled_at, now()),
        cancelled_reason = COALESCE(
          nullif(trim(lc.cancelled_reason), ''),
          'permit_deadline_expired_72h'
        ),
        updated_at = now()
      WHERE lc.id = r.contract_id
        AND lc.status::text IS DISTINCT FROM 'signed';
    END IF;

    UPDATE public.listing_requests lr
    SET
      workflow_stage = 'waiting_marketers',
      status = 'waiting_marketers',
      marketing_round = coalesce(lr.marketing_round, 1) + 1,
      selected_offer_id = NULL,
      selected_marketer_id = NULL,
      contract_id = NULL,
      contract_sent_at = NULL,
      contract_signed_at = NULL,
      permit_deadline_at = NULL,
      inactive_72h_at = NULL,
      waiting_marketers_since = now(),
      owner_distinct_marketer_declines = 0,
      updated_at = now()
    WHERE lr.id = r.id;

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'permit_deadline_expired',
        'انتهت مهلة التصريح',
        'بسبب عدم التزام المسوق بالمدة النظامية (72 ساعة)، تم إتاحة العقار مرة أخرى لضمان سرعة تسويقه.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'contract_id', r.contract_id,
          'deep_route', 'listing_request_status',
          'main_tab', 'my_ads',
          'role', 'owner'
        )
      );
    END IF;

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'permit_deadline_expired',
        'انتهت مهلة التصريح',
        'انتهت مهلة إكمال التصريح لهذا الطلب. عُيد للتسويق مع مسوّقين آخرين.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'request_id', r.id,
          'deep_route', 'listing_request_status',
          'main_tab', 'my_ads',
          'role', 'marketer'
        )
      );
    END IF;
  END LOOP;

  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.cron_expire_permit_pending_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_expire_permit_pending_72h() TO service_role;

COMMIT;
