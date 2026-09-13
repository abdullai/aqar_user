-- Auto-renew failure: in-app notice (push via send_push webhook on INSERT).
-- data.sms_body_* is stored for a future SMS provider without changing this RPC.

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_subscription_auto_renew_failed(
  p_user_id uuid,
  p_subscription_id uuid,
  p_billing_transaction_id uuid DEFAULT NULL,
  p_reason text DEFAULT 'insufficient_funds'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_username text;
  v_plan_ar text;
  v_plan_en text;
  v_title_ar text := 'تعذّر التجديد التلقائي';
  v_title_en text := 'Auto-renewal failed';
  v_body_ar text;
  v_body_en text;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT nullif(trim(up.username), '')
  INTO v_username
  FROM public.users_profiles up
  WHERE up.user_id = p_user_id
  LIMIT 1;
  IF v_username IS NULL THEN
    v_username := p_user_id::text;
  END IF;

  SELECT
    coalesce(nullif(trim(sp.name_ar), ''), nullif(trim(sp.name_en), ''), '—'),
    coalesce(nullif(trim(sp.name_en), ''), nullif(trim(sp.name_ar), ''), '—')
  INTO v_plan_ar, v_plan_en
  FROM public.user_subscriptions us
  JOIN public.subscription_plans sp ON sp.id = us.plan_id
  WHERE us.id = p_subscription_id
  LIMIT 1;

  v_plan_ar := coalesce(v_plan_ar, '—');
  v_plan_en := coalesce(v_plan_en, '—');

  v_body_ar := format(
    'عزيزنا العميل، تعذر تجديد اشتراكك التلقائي لباقة %s نظراً لعدم توفر رصيد كافٍ في بطاقتك. يرجى تحديث بيانات الدفع لتجنب انقطاع الخدمة.',
    v_plan_ar
  );
  v_body_en := format(
    'Dear customer, we could not automatically renew your %s plan because there was not enough balance on your card. Please update your payment details to avoid service interruption.',
    v_plan_en
  );

  INSERT INTO public.in_app_notifications (
    user_id, username, type, title, body, data, created_at, is_read
  ) VALUES (
    p_user_id,
    v_username,
    'billing_auto_renew_failed',
    v_title_ar,
    v_body_ar,
    jsonb_build_object(
      'title_ar', v_title_ar,
      'title_en', v_title_en,
      'body_ar', v_body_ar,
      'body_en', v_body_en,
      'sms_body_ar', v_body_ar,
      'sms_body_en', v_body_en,
      'sms_ready', true,
      'deep_route', 'subscriptions_hub',
      'entity_type', 'billing_transaction',
      'entity_id', p_billing_transaction_id,
      'subscription_id', p_subscription_id,
      'reason', coalesce(nullif(trim(p_reason), ''), 'insufficient_funds'),
      'channel', 'in_app'
    ),
    timezone('utc', now()),
    false
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_subscription_auto_renew_failed(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_subscription_auto_renew_failed(uuid, uuid, uuid, text)
  TO service_role;

COMMIT;
