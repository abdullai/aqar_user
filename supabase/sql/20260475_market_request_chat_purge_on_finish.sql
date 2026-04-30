-- حذف رسائل ومحادثات طلب السوق (kind=market_request) عند إغلاق الطلب أو حذفه.
-- المحادثات الإدارية/الدعم (kind=support) لا تُمس.
-- طبّق بعد 20260411_market_request_chat_offers_v1.sql و 20260434_chat_receipts…

CREATE OR REPLACE FUNCTION public.purge_market_request_chat_data(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_request_id IS NULL THEN
    RETURN;
  END IF;

  DELETE FROM public.messages m
  USING public.conversations c
  WHERE m.conversation_id = c.id
    AND c.kind = 'market_request'
    AND c.market_request_id = p_request_id;

  DELETE FROM public.conversations
  WHERE kind = 'market_request'
    AND market_request_id = p_request_id;
END;
$$;

COMMENT ON FUNCTION public.purge_market_request_chat_data IS
  'حذف محادثة طلب السوق ورسائلها عند انتهاء الغرض (خصوصية).';

CREATE OR REPLACE FUNCTION public.trg_market_request_chat_cleanup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_done boolean;
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.purge_market_request_chat_data(OLD.id);
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_status := lower(trim(COALESCE(NEW.status::text, '')));
    -- حالات إنهاء متوافقة مع قيد الجدول (انظر 20260460_market_property_requests_status_check…)
    v_done := v_status IN ('closed', 'deleted');
    IF v_done THEN
      PERFORM public.purge_market_request_chat_data(NEW.id);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_request_chat_cleanup ON public.market_property_requests;
CREATE TRIGGER trg_market_request_chat_cleanup
  AFTER UPDATE OF status OR DELETE
  ON public.market_property_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_market_request_chat_cleanup();
