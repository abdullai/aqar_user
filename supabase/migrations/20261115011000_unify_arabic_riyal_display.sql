BEGIN;

DO $$
DECLARE
  v_definition text;
  v_updated text;
  v_signature regprocedure;
BEGIN
  v_signature := to_regprocedure(
    'public.set_subscription_auto_pay(uuid,boolean,uuid,uuid)'
  );
  IF v_signature IS NULL THEN
    RAISE EXCEPTION 'set_subscription_auto_pay function was not found';
  END IF;

  v_definition := pg_get_functiondef(v_signature);
  IF position('ر.س' IN v_definition) > 0 THEN
    v_updated := replace(v_definition, 'ر.س', '﷼');
    EXECUTE v_updated;
  ELSIF position('﷼' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected set_subscription_auto_pay currency text';
  END IF;

  v_signature := to_regprocedure('public.notify_saved_search_matches()');
  IF v_signature IS NULL THEN
    RAISE EXCEPTION 'notify_saved_search_matches function was not found';
  END IF;

  v_definition := pg_get_functiondef(v_signature);
  IF position('ر.س' IN v_definition) > 0 THEN
    v_updated := replace(v_definition, 'ر.س', '﷼');
    EXECUTE v_updated;
  ELSIF position('﷼' IN v_definition) = 0 THEN
    RAISE EXCEPTION 'Unexpected notify_saved_search_matches currency text';
  END IF;
END;
$$;

UPDATE public.in_app_notifications
SET body = regexp_replace(
      body,
      '(ر[.]س|ر/س|س[.]ر|س/ر|ريال)',
      '﷼',
      'g'
    ),
    data = CASE
      WHEN jsonb_typeof(data) = 'object' AND data ? 'body_ar' THEN
        jsonb_set(
          data,
          '{body_ar}',
          to_jsonb(regexp_replace(
            data ->> 'body_ar',
            '(ر[.]س|ر/س|س[.]ر|س/ر|ريال)',
            '﷼',
            'g'
          )),
          true
        )
      ELSE data
    END
WHERE type = 'saved_search_match'
  AND (
    coalesce(body, '') ~ '(ر[.]س|ر/س|س[.]ر|س/ر|ريال)'
    OR coalesce(data ->> 'body_ar', '') ~ '(ر[.]س|ر/س|س[.]ر|س/ر|ريال)'
  );

COMMIT;
