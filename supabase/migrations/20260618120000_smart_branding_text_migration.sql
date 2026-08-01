-- Smart branding migration: replace legacy product names in static/platform text only.
-- Does NOT touch user-authored messages (messages, chat bodies, property descriptions).
-- Safe: uses REPLACE on matching rows only; idempotent when re-run.

BEGIN;

-- ---------------------------------------------------------------------------
-- Helper: longest-match-first text migration (Arabic + English legacy names)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.branding_migrate_text(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN p_text IS NULL OR btrim(p_text) = '' THEN p_text
    ELSE replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(
                    replace(
                      replace(
                        replace(p_text,
                          'منصة موثوق العقاري الإلكترونية',
                          'مؤسسة موثوق لاين العقارية'),
                        'منصة عقار موثوق',
                        'مؤسسة موثوق لاين العقارية'),
                      'تطبيق موثوق العقاري',
                      'تطبيق موثوق لاين العقاري'),
                    'عقار موثوق',
                    'موثوق لاين العقارية'),
                  'موثوق العقاري',
                  'موثوق لاين العقارية'),
                'Aqar Mawthuq Real Estate',
                'Mawthuq Line Real Estate Establishment'),
              'Aqar Mawthuq',
              'Mawthuq Line Real Estate'),
            'Aqar Reliable',
            'Mawthuq Line Real Estate'),
          'Motawoq Real Estate',
          'Mawthuq Line Real Estate'),
        'Trusted Aqar',
        'Mawthuq Line Real Estate'),
      'Motawoq',
      'Mawthuq Line')
  END;
$$;

COMMENT ON FUNCTION public.branding_migrate_text(text) IS
  'One-shot legacy brand name → Mawthuq Line (AR/EN). Used by migration + optional display RPC.';

-- ---------------------------------------------------------------------------
-- 1) Subscription catalog (static plan labels)
-- ---------------------------------------------------------------------------
UPDATE public.subscription_plans
SET
  name_ar = public.branding_migrate_text(name_ar),
  name_en = public.branding_migrate_text(name_en),
  description_ar = public.branding_migrate_text(description_ar),
  description_en = public.branding_migrate_text(description_en)
WHERE name_ar ~ 'عقار موثوق|موثوق العقاري|تطبيق موثوق العقاري'
   OR name_en ~* 'Aqar|Motawoq|Trusted'
   OR coalesce(description_ar, '') ~ 'عقار موثوق|موثوق العقاري'
   OR coalesce(description_en, '') ~* 'Aqar|Motawoq|Trusted';

-- ---------------------------------------------------------------------------
-- 2) Billing ledger titles (platform-generated receipts)
-- ---------------------------------------------------------------------------
UPDATE public.billing_transactions
SET
  title_ar = public.branding_migrate_text(title_ar),
  title_en = public.branding_migrate_text(title_en)
WHERE coalesce(title_ar, '') ~ 'عقار موثوق|موثوق العقاري'
   OR coalesce(title_en, '') ~* 'Aqar|Motawoq|Trusted';

-- ---------------------------------------------------------------------------
-- 3) In-app notifications (title/body + JSON data payloads)
-- ---------------------------------------------------------------------------
UPDATE public.in_app_notifications
SET
  title = public.branding_migrate_text(title),
  body = public.branding_migrate_text(body)
WHERE coalesce(title, '') ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted'
   OR coalesce(body, '') ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted';

UPDATE public.in_app_notifications
SET data = public.branding_migrate_text(data::text)::jsonb
WHERE data IS NOT NULL
  AND data::text ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted';

-- ---------------------------------------------------------------------------
-- 4) Push outbox queue (pending system pushes)
-- ---------------------------------------------------------------------------
UPDATE public.push_notification_outbox
SET
  title = public.branding_migrate_text(title),
  body = public.branding_migrate_text(body)
WHERE coalesce(title, '') ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted'
   OR coalesce(body, '') ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted';

UPDATE public.push_notification_outbox
SET data = public.branding_migrate_text(data::text)::jsonb
WHERE data IS NOT NULL
  AND data::text ~ 'عقار موثوق|موثوق العقاري|Aqar|Motawoq|Trusted';

-- ---------------------------------------------------------------------------
-- 5) Legal document versions (terms/privacy platform copy)
-- ---------------------------------------------------------------------------
UPDATE public.legal_documents_versions
SET
  title_ar = public.branding_migrate_text(title_ar),
  title_en = public.branding_migrate_text(title_en),
  body_ar = public.branding_migrate_text(body_ar),
  body_en = public.branding_migrate_text(body_en)
WHERE title_ar ~ 'موثوق العقاري|عقار موثوق'
   OR title_en ~* 'Motawoq|Aqar|Trusted'
   OR body_ar ~ 'موثوق العقاري|عقار موثوق'
   OR body_en ~* 'Motawoq|Aqar|Trusted';

-- ---------------------------------------------------------------------------
-- 6) Promotions / billing metadata (if table exists)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.subscription_promotions') IS NOT NULL THEN
    EXECUTE $sql$
      UPDATE public.subscription_promotions
      SET
        title_ar = public.branding_migrate_text(title_ar),
        title_en = public.branding_migrate_text(title_en)
      WHERE coalesce(title_ar, '') ~ 'عقار موثوق|موثوق العقاري'
         OR coalesce(title_en, '') ~* 'Aqar|Motawoq|Trusted'
    $sql$;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7) Push trigger fallback title (new notifications)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enqueue_push_for_in_app_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  payload jsonb;
  title_text text;
  body_text text;
BEGIN
  IF new.user_id IS NULL THEN
    RETURN new;
  END IF;

  payload := coalesce(new.data, '{}'::jsonb)
    || jsonb_build_object(
      'kind', coalesce(new.data->>'kind', 'workflow'),
      'type', new.type,
      'notification_id', new.id::text
    );

  title_text := coalesce(
    nullif(payload->>'title_ar', ''),
    nullif(payload->>'title_en', ''),
    nullif(new.title, ''),
    'موثوق لاين العقارية'
  );

  body_text := coalesce(
    nullif(payload->>'body_ar', ''),
    nullif(payload->>'body_en', ''),
    nullif(new.body, ''),
    title_text
  );

  INSERT INTO public.push_notification_outbox (
    notification_id,
    user_id,
    fcm_token,
    platform,
    title,
    body,
    data
  )
  SELECT
    new.id,
    new.user_id,
    t.fcm_token,
    t.platform,
    public.branding_migrate_text(title_text),
    public.branding_migrate_text(body_text),
    payload
  FROM public.user_push_tokens t
  WHERE t.user_id = new.user_id
    AND t.fcm_token IS NOT NULL
    AND btrim(t.fcm_token) <> '';

  RETURN new;
END;
$$;

COMMIT;
