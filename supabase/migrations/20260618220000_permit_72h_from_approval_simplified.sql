-- =============================================================================
-- 72 ساعة من موافقة المالك حتى النشر: انتهاء المهلة لكل المراحل بعد القبول
-- (contract_signed / marketer_selected / permit_* / permit_issued) وليس permit_pending فقط.
-- =============================================================================

BEGIN;

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
     WHERE lower(trim(coalesce(workflow_stage,''))) IN (
           'marketer_selected',
           'contract_signed',
           'permit_pending',
           'awaiting_permits',
           'pending_permits',
           'permit_issued'
         )
       AND permit_deadline_at IS NOT NULL
       AND permit_deadline_at < now()
       AND owner_action_required_at IS NULL
     LIMIT 500
  LOOP
    UPDATE public.listing_requests
       SET workflow_stage = 'owner_action_required',
           owner_action_required_at = now(),
           owner_action_reason = 'publish_72h_expired',
           inactive_72h_at = now(),
           prev_selected_marketer_id = coalesce(prev_selected_marketer_id, selected_marketer_id),
           selected_marketer_id = NULL,
           auto_expired_at = now(),
           updated_at = now()
     WHERE id = r.id;

    UPDATE public.listing_permits
       SET status = 'rejected',
           notes = coalesce(notes,'') || ' [auto-expired-72h]',
           updated_at = now()
     WHERE request_id = r.id
       AND status::text NOT IN ('approved','rejected');

    IF r.owner_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.owner_id,
        'workflow.permit.expired_72h',
        'انتهت مهلة 72 ساعة',
        'لم يُنشر الإعلان خلال 72 ساعة من الموافقة. يمكنك إعادة الطلب للسوق الآن.',
        'listing_request',
        r.id,
        jsonb_build_object(
          'reason', 'publish_72h_expired',
          'priority', 'high',
          'my_ads_sub_tab', '3',
          'hub_tab_schema_v', '4'
        )
      );
    END IF;

    IF r.selected_marketer_id IS NOT NULL THEN
      PERFORM public.workflow_create_notification(
        r.selected_marketer_id,
        'workflow.permit.lost_72h',
        'انتهت مهلة 72 ساعة',
        'انتهت مهلة 72 ساعة للنشر ونُقل الطلب إلى «لم يتخذ إجراء 72 ساعة».',
        'listing_request',
        r.id,
        jsonb_build_object(
          'reason', 'publish_72h_expired',
          'my_ads_sub_tab', '3',
          'hub_tab_schema_v', '4'
        )
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

COMMENT ON FUNCTION public.cron_expire_marketer_permit_72h() IS
  'انتهاء 72 ساعة من موافقة المالك حتى النشر: يحرّك الطلب إلى owner_action_required ويُبقي prev_selected_marketer_id للمسوّق السابق.';

COMMIT;
