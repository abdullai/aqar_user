-- صفقاتي: قراءة طلب السوق للمشارك، حد 10 متقدمين لكل بطاقة،
-- وإعادة تفعيل العروض المعلّقة إن لم يُتمّ الشريك المختار خلال 72 ساعة.

BEGIN;

-- دالة أقدم بمعامل p_request_id: CREATE OR REPLACE لا يغيّر اسم المعامل.
DROP FUNCTION IF EXISTS public.market_property_request_for_participant(uuid);

CREATE OR REPLACE FUNCTION public.market_property_request_for_participant(
  p_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r public.market_property_requests%ROWTYPE;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO r FROM public.market_property_requests WHERE id = p_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF r.requester_id = uid THEN
    RETURN to_jsonb(r);
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.market_request_offers o
    WHERE o.market_request_id = p_id
      AND o.offerer_id = uid
  ) THEN
    RETURN to_jsonb(r);
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.market_property_request_for_participant(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.market_property_request_for_participant(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_item_complete_deal_applicant_cap()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  n int := 0;
BEGIN
  IF TG_TABLE_NAME = 'market_request_offers' THEN
    IF lower(trim(coalesce(NEW.status, ''))) NOT IN (
         'submitted', 'pending', 'accepted', 'approved', 'selected', ''
       ) THEN
      RETURN NEW;
    END IF;
    SELECT count(*)::int INTO n
    FROM public.market_request_offers o
    WHERE o.market_request_id = NEW.market_request_id
      AND o.id IS DISTINCT FROM NEW.id
      AND lower(trim(coalesce(o.status, ''))) IN (
        'submitted', 'pending', 'accepted', 'approved', 'selected', ''
      );
    IF n >= 10 THEN
      RAISE EXCEPTION 'deal_applicants_cap';
    END IF;
  ELSIF TG_TABLE_NAME = 'reservations' THEN
    IF lower(trim(coalesce(NEW.status, ''))) NOT IN (
         'pending', 'paid', 'accepted'
       ) THEN
      RETURN NEW;
    END IF;
    SELECT count(*)::int INTO n
    FROM public.reservations r
    WHERE r.property_id = NEW.property_id
      AND r.id IS DISTINCT FROM NEW.id
      AND lower(trim(coalesce(r.status, ''))) IN ('pending', 'paid', 'accepted');
    IF n >= 10 THEN
      RAISE EXCEPTION 'deal_applicants_cap';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_offers_applicant_cap ON public.market_request_offers;
CREATE TRIGGER trg_market_offers_applicant_cap
BEFORE INSERT OR UPDATE OF status ON public.market_request_offers
FOR EACH ROW
EXECUTE FUNCTION public.enforce_item_complete_deal_applicant_cap();

DROP TRIGGER IF EXISTS trg_reservations_applicant_cap ON public.reservations;
CREATE TRIGGER trg_reservations_applicant_cap
BEFORE INSERT OR UPDATE OF status ON public.reservations
FOR EACH ROW
EXECUTE FUNCTION public.enforce_item_complete_deal_applicant_cap();

CREATE OR REPLACE FUNCTION public.cron_reactivate_parked_deals_after_72h()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n_req int := 0;
  n_res int := 0;
  r record;
BEGIN
  FOR r IN
    SELECT req.id, req.selected_offer_id
    FROM public.market_property_requests req
    JOIN public.market_request_offers o ON o.id = req.selected_offer_id
    WHERE lower(trim(coalesce(req.status, ''))) NOT IN ('completed', 'closed', 'cancelled', 'canceled')
      AND req.completed_at IS NULL
      AND req.selected_offer_id IS NOT NULL
      AND coalesce(o.updated_at, o.created_at) < now() - interval '72 hours'
      AND lower(trim(coalesce(o.status, ''))) IN ('accepted', 'approved', 'selected')
    LIMIT 200
  LOOP
    UPDATE public.market_request_offers
       SET status = 'expired', updated_at = now()
     WHERE id = r.selected_offer_id;
    UPDATE public.market_property_requests
       SET selected_offer_id = NULL, updated_at = now()
     WHERE id = r.id;
    UPDATE public.market_request_offers
       SET status = 'submitted', updated_at = now()
     WHERE market_request_id = r.id
       AND id IS DISTINCT FROM r.selected_offer_id
       AND lower(trim(coalesce(status, ''))) IN ('submitted', 'pending', '');
    n_req := n_req + 1;
  END LOOP;

  UPDATE public.reservations res
     SET status = 'expired', updated_at = now()
   WHERE lower(trim(coalesce(res.status, ''))) = 'accepted'
     AND res.deal_completed_at IS NULL
     AND coalesce(res.expires_at, res.updated_at, res.created_at) < now()
     AND EXISTS (
       SELECT 1 FROM public.properties p
       WHERE p.id = res.property_id
         AND lower(trim(coalesce(p.status, ''))) NOT IN ('sold', 'completed', 'closed')
     );
  GET DIAGNOSTICS n_res = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'requests', n_req, 'reservations', n_res);
END;
$$;

REVOKE ALL ON FUNCTION public.cron_reactivate_parked_deals_after_72h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cron_reactivate_parked_deals_after_72h()
  TO authenticated, service_role;

DO $$
BEGIN
  PERFORM cron.unschedule('reactivate_parked_deals_72h');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'reactivate_parked_deals_72h',
    '*/20 * * * *',
    $job$SELECT public.cron_reactivate_parked_deals_after_72h();$job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not enabled on this project: %', SQLERRM;
END $$;

COMMIT;
