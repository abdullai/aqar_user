-- عمود اختياري لإعلانات الجدول ads (شريط جانبي تسجيل الدخول / لوحة).
-- إن لم يكن العمود موجوداً، PostgREST قد يرفض select الذي يذكر video_url — نفّذ هذا أولاً.

BEGIN;

ALTER TABLE public.ads
  ADD COLUMN IF NOT EXISTS video_url text;

COMMENT ON COLUMN public.ads.video_url IS
  'رابط فيديو اختياري للمعاينة (URL عام أو مسار تخزين حسب الواجهة).';

COMMIT;
