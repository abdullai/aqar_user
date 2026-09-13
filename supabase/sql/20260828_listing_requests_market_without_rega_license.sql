-- اختياري: أعمدة توافق مع التطبيق. الإدراج يعمل بدونها (تُحفظ في payload_json).
-- إن نفّذت هذا الملف: Settings → API → Reload schema في PostgREST إن لزم.

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS no_rega_ad_license boolean NOT NULL DEFAULT false;

ALTER TABLE public.listing_requests
  ADD COLUMN IF NOT EXISTS market_without_rega_license boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.listing_requests.market_without_rega_license IS
  'طلب/إعلان سوق بدون رخصة إعلان REGA — القيمة المعتمدة أيضاً داخل payload_json.';
