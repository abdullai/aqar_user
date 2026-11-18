BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_market_request_subscription_quota()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF lower(coalesce(NEW.status, '')) <> 'published' OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.requester_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'requester_not_authenticated_user';
  END IF;
  IF TG_OP = 'UPDATE' AND lower(coalesce(OLD.status, '')) = 'published' THEN
    NEW.request_quota_subscription_id := OLD.request_quota_subscription_id;
    RETURN NEW;
  END IF;

  NEW.request_quota_subscription_id := NULL;
  IF coalesce(NEW.request_priority, 'standard') = 'immediate'
     AND (
       NEW.instant_credit_id IS NULL
       OR NOT EXISTS (
         SELECT 1
         FROM public.market_request_instant_credits c
         WHERE c.id = NEW.instant_credit_id
           AND c.user_id = v_uid
           AND c.status = 'consumed'
           AND c.market_request_id = NEW.id
       )
     ) THEN
    RAISE EXCEPTION 'instant_credit_required'
      USING HINT = 'الطلب الفوري يتطلب رصيداً مدفوعاً ومستهلكاً.';
  END IF;

  NEW.published_at := timezone('utc', now());
  NEW.updated_at := NEW.published_at;
  RETURN NEW;
END;
$$;

COMMIT;
