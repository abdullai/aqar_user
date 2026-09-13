-- Storage: listing image/license upload paths under property-images.
-- See supabase/sql/20260910_storage_listing_media_own_prefix.sql

BEGIN;

DROP POLICY IF EXISTS "listing_images_insert_own_uid_prefix" ON storage.objects;
CREATE POLICY "listing_images_insert_own_uid_prefix"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND (
    name ~~ ((auth.uid())::text || '/listings/%')
    OR name ~~ ((auth.uid())::text || '/requests/%')
    OR name ~~ ((auth.uid())::text || '/licenses/%')
    OR name ~~ ('listings/' || (auth.uid())::text || '/%')
    OR (
      split_part(name, '/', 1) = 'requests'
      AND split_part(name, '/', 3) = (auth.uid())::text
    )
    OR name ~~ ('licenses/' || (auth.uid())::text || '/%')
  )
);

DROP POLICY IF EXISTS "listing_images_update_own_uid_prefix" ON storage.objects;
CREATE POLICY "listing_images_update_own_uid_prefix"
ON storage.objects
FOR UPDATE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND (
    name ~~ ((auth.uid())::text || '/listings/%')
    OR name ~~ ((auth.uid())::text || '/requests/%')
    OR name ~~ ((auth.uid())::text || '/licenses/%')
    OR name ~~ ('listings/' || (auth.uid())::text || '/%')
    OR (
      split_part(name, '/', 1) = 'requests'
      AND split_part(name, '/', 3) = (auth.uid())::text
    )
    OR name ~~ ('licenses/' || (auth.uid())::text || '/%')
  )
)
WITH CHECK (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND (
    name ~~ ((auth.uid())::text || '/listings/%')
    OR name ~~ ((auth.uid())::text || '/requests/%')
    OR name ~~ ((auth.uid())::text || '/licenses/%')
    OR name ~~ ('listings/' || (auth.uid())::text || '/%')
    OR (
      split_part(name, '/', 1) = 'requests'
      AND split_part(name, '/', 3) = (auth.uid())::text
    )
    OR name ~~ ('licenses/' || (auth.uid())::text || '/%')
  )
);

DROP POLICY IF EXISTS "listing_images_delete_own_uid_prefix" ON storage.objects;
CREATE POLICY "listing_images_delete_own_uid_prefix"
ON storage.objects
FOR DELETE
TO public
USING (
  bucket_id = 'property-images'
  AND auth.role() = 'authenticated'
  AND (
    name ~~ ((auth.uid())::text || '/listings/%')
    OR name ~~ ((auth.uid())::text || '/requests/%')
    OR name ~~ ((auth.uid())::text || '/licenses/%')
    OR name ~~ ('listings/' || (auth.uid())::text || '/%')
    OR (
      split_part(name, '/', 1) = 'requests'
      AND split_part(name, '/', 3) = (auth.uid())::text
    )
    OR name ~~ ('licenses/' || (auth.uid())::text || '/%')
  )
);

COMMIT;
