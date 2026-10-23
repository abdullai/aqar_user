BEGIN;

CREATE OR REPLACE FUNCTION public._redact_moyasar_sensitive_jsonb(p_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF jsonb_typeof(p_value) = 'object' THEN
    SELECT coalesce(
      jsonb_object_agg(
        key,
        CASE
          WHEN lower(key) IN ('secret_token', 'token', 'card_token', 'cvv', 'password')
            THEN to_jsonb('[redacted]'::text)
          ELSE public._redact_moyasar_sensitive_jsonb(value)
        END
      ),
      '{}'::jsonb
    )
    INTO v_result
    FROM jsonb_each(p_value);
    RETURN v_result;
  ELSIF jsonb_typeof(p_value) = 'array' THEN
    SELECT coalesce(
      jsonb_agg(public._redact_moyasar_sensitive_jsonb(value)),
      '[]'::jsonb
    )
    INTO v_result
    FROM jsonb_array_elements(p_value);
    RETURN v_result;
  END IF;
  RETURN p_value;
END;
$$;

UPDATE public.moyasar_webhook_events
SET payload = public._redact_moyasar_sensitive_jsonb(payload)
WHERE payload IS NOT NULL
  AND payload::text ~* '"(secret_token|token|card_token|cvv|password)"';

UPDATE public.billing_transactions
SET gateway_response = public._redact_moyasar_sensitive_jsonb(gateway_response)
WHERE gateway_response IS NOT NULL
  AND gateway_response::text ~* '"(secret_token|token|card_token|cvv|password)"';

DROP FUNCTION public._redact_moyasar_sensitive_jsonb(jsonb);

COMMIT;
