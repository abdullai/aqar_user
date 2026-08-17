-- لقطة بيانات ترخيص الإعلان + مسار QR (من تقديم المسوق) للعرض في تفاصيل الإعلان
-- نفّذ على مشروع Supabase (SQL Editor أو CLI).

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS marketing_license_snapshot jsonb;

COMMENT ON COLUMN public.properties.marketing_license_snapshot IS
  'بيانات ترخيص الإعلان اليدوية/المؤقتة من مسار التسويق (REGA، فال، QR path، ملاحظات)';

CREATE INDEX IF NOT EXISTS idx_properties_marketing_license_snapshot
  ON public.properties USING gin (marketing_license_snapshot)
  WHERE marketing_license_snapshot IS NOT NULL;
