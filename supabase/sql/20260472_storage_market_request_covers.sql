-- =============================================================================
-- Storage: السماح برفع غلاف طلب السوق تحت property-images/market-requests/{uid}/
-- يصلح StorageException 403 (RLS) عند رفع صورة اختيارية لطلب عقاري.
-- نفّذ في Supabase → SQL Editor.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "market_request_covers_insert_own" ON storage.objects;
CREATE POLICY "market_request_covers_insert_own"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('market-requests/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "market_request_covers_update_own" ON storage.objects;
CREATE POLICY "market_request_covers_update_own"
ON storage.objects
FOR UPDATE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('market-requests/' || (auth.uid())::text || '/%')
)
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('market-requests/' || (auth.uid())::text || '/%')
);

DROP POLICY IF EXISTS "market_request_covers_delete_own" ON storage.objects;
CREATE POLICY "market_request_covers_delete_own"
ON storage.objects
FOR DELETE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND name ~~ ('market-requests/' || (auth.uid())::text || '/%')
);

COMMIT;
