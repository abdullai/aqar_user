-- جزء broker_nid لخطأ نشر الإعلان / تحقق التصريح
-- شغّله إن ظهر سابقاً: column lp.broker_nid does not exist

ALTER TABLE IF EXISTS public.listing_permits
  ADD COLUMN IF NOT EXISTS broker_nid text;

UPDATE public.listing_permits
   SET broker_nid = nullif(
         trim(substring(notes from 'broker_nid:[[:space:]]*(.+)$')),
         ''
       )
 WHERE coalesce(nullif(trim(broker_nid), ''), '') = ''
   AND notes IS NOT NULL
   AND notes ~* 'broker_nid:';
