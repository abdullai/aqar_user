-- غلاف اختياري لطلب السوق (مسار داخل حاوية property-images).
-- نفّذ في Supabase → SQL Editor قبل الاعتماد على الحقل من التطبيق.

ALTER TABLE public.market_property_requests
  ADD COLUMN IF NOT EXISTS cover_image_storage_path text;

COMMENT ON COLUMN public.market_property_requests.cover_image_storage_path IS
  'مسار ملف في storage bucket property-images؛ عند الفراغ يعرض التطبيق شعاراً افتراضياً.';
