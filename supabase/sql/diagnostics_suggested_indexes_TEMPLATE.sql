-- =============================================================================
-- قوالب فهارس مرشّحة — كلها معطّلة (تعليق). لا تُنفَّذ قبل EXPLAIN + موافقة يدوية.
-- =============================================================================
-- تُستخرج الأعمدة من مسارات التحميل في aqar_user (مثال):
--   properties: الرئيسية، إعلاناتي (owner_id)، فلتر status، ترتيب created_at/updated_at
--   reservations: property_id، user_id، status، created_at
--   listing_* (مسوّق): marketer_id + created_at
-- =============================================================================

-- مثال — تحقق من أسماء الأعمدة والقيود قبل الإلغاء من التعليق:
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_properties_owner_updated
--   ON public.properties (owner_id, updated_at DESC, created_at DESC)
--   WHERE status IS DISTINCT FROM 'deleted';

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservations_property_status_created
--   ON public.reservations (property_id, status, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reservations_user_status_created
--   ON public.reservations (user_id, status, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_listing_request_invites_marketer_created
--   ON public.listing_request_invites (marketer_id, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_listing_offers_marketer_created
--   ON public.listing_offers (marketer_id, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_listing_contracts_marketer_created
--   ON public.listing_contracts (marketer_id, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_listing_permits_marketer_created
--   ON public.listing_permits (marketer_id, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_listing_requests_owner_created
--   ON public.listing_requests (owner_id, created_at DESC);

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_market_property_requests_public_scan
--   ON public.market_property_requests (status, created_at DESC);
--   -- عدّل الأعمدة حسب فلاتر RLS الفعلية لطلبات السوق

-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_profiles_user_id
--   ON public.users_profiles (user_id);

-- بعد أي تغيير فهرس مهم على جداول كبيرة:
-- ANALYZE public.properties;
-- ANALYZE public.reservations;
