-- بيانات الصك ورقم المبنى للإعلانات
-- نفّذ على مشروع Supabase (SQL Editor أو CLI).

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS deed_number text,
  ADD COLUMN IF NOT EXISTS deed_date date,
  ADD COLUMN IF NOT EXISTS deed_issuer text,
  ADD COLUMN IF NOT EXISTS building_number text;

COMMENT ON COLUMN public.properties.deed_number IS 'رقم الصك (يُطبّع في التطبيق عند الحفظ والبحث)';
COMMENT ON COLUMN public.properties.deed_date IS 'تاريخ إصدار الصك';
COMMENT ON COLUMN public.properties.deed_issuer IS 'الجهة المصدرة للصك';
COMMENT ON COLUMN public.properties.building_number IS 'رقم المبنى (فيلا/شقة/محل ...)';

CREATE INDEX IF NOT EXISTS idx_properties_deed_number_lookup
  ON public.properties (deed_number)
  WHERE deed_number IS NOT NULL AND btrim(deed_number) <> '';
