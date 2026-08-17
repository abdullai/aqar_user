-- توسعات مسار المسوق العقاري: إشعارات، تصاريح، طلبات إطلاع على الدردشة
-- راجع التطبيق: marketing_flow_service، user_dashboard.my_ads_hub، submit_permits_page

-- 1) عمود اختياري على الطلبات: موعد انتهاء مهلة التصاريح (يُحدَّث من التطبيق عند اكتمال التوقيع)
-- ALTER TABLE public.listing_requests
--   ADD COLUMN IF NOT EXISTS permits_due_at timestamptz;

-- 2) تخزين لقطة ترخيص REGA (بعد موافقة المالك على النشر) — يمكن دمجها في properties.extra_details أو JSON منفصل
-- ALTER TABLE public.properties
--   ADD COLUMN IF NOT EXISTS rega_license_snapshot jsonb;

-- 3) طلب المعلن لمراقبة دردشات المسوق (موافقة ثنائية)
CREATE TABLE IF NOT EXISTS public.listing_chat_visibility_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_request_id uuid NOT NULL REFERENCES public.listing_requests(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL,
  marketer_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE (listing_request_id, owner_id)
);

COMMENT ON TABLE public.listing_chat_visibility_requests IS
  'طلب من المعلن لإظهار محادثات المسوق؛ لا يُفعّل إلا بعد status=approved من المسوق';

-- 4) (اختياري) تفعيل إشعار تلقائي عند إدراج listing_offers — يتطلب دالة و trigger
-- CREATE OR REPLACE FUNCTION public.notify_owner_on_listing_offer()
-- RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- BEGIN
--   INSERT INTO public.in_app_notifications (user_id, type, title, body, entity_type, entity_id, data)
--   SELECT lr.owner_id, 'offer_submitted', 'وصلك عرض تسويق جديد', 'راجع العروض في لوحة إعلاناتي.',
--          'listing_offer', NEW.request_id, jsonb_build_object('request_id', NEW.request_id);
--   RETURN NEW;
-- END;
-- $$;
-- CREATE TRIGGER trg_listing_offers_notify_owner
--   AFTER INSERT ON public.listing_offers
--   FOR EACH ROW EXECUTE FUNCTION public.notify_owner_on_listing_offer();

-- ملاحظة: فعّل RLS وGRANT حسب نموذجك. التطبيق يرسل إشعارًا أيضًا من marketer_request_details لتغطية مسار RPC.
