-- توافق PostgREST مع تطبيق aqar_user (فلاتر + علاقات) — نفّذ على مشروع Supabase إن ظهر 400
-- على properties رغم استخدام select=* في التطبيق (مثلاً عند غياب request_id أو is_featured).

BEGIN;

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS request_id uuid,
  ADD COLUMN IF NOT EXISTS workflow_stage text,
  ADD COLUMN IF NOT EXISTS is_featured boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_properties_request_id
  ON public.properties (request_id)
  WHERE request_id IS NOT NULL;

COMMIT;

-- إن وُجدت listing_requests، يمكنك لاحقاً إضافة:
-- ALTER TABLE public.properties
--   ADD CONSTRAINT properties_request_id_fkey
--   FOREIGN KEY (request_id) REFERENCES public.listing_requests(id) ON DELETE SET NULL;
-- (تخطّى إذا كان الاسم أو المخطط مختلفاً.)
