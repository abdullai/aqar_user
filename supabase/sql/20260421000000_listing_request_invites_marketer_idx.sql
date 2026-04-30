-- يدعم استعلام التطبيق: listing_request_invites حيث marketer_id = ? مع ترتيب created_at
-- طبّق على قاعدة الإنتاج عبر SQL Editor أو supabase db push حسب سير عملكم.
CREATE INDEX IF NOT EXISTS idx_listing_request_invites_marketer_created_at
  ON public.listing_request_invites (marketer_id, created_at DESC);
