-- =============================================================================
-- اختبار السوق المفتوح بهوية مسوّق/مكتب حقيقي (محاكاة auth.uid)
-- =============================================================================

-- أ) مسوّق 1010101011
SELECT set_config('request.jwt.claim.sub', '7a67cec4-ab17-40ff-8168-8901fb658d29', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT auth.uid() AS simulated_uid;

SELECT
  public.marketer_can_read_listing_request('02ae7a9c-fbff-4507-afad-de828e5c5d9a')
    AS can_read_jazan,
  public.marketer_can_read_listing_request('e26e3bc2-c422-4fcd-8135-1f0fe94d24ce')
    AS can_read_haqu;

SELECT id, title, workflow_stage
FROM public.listing_requests
WHERE workflow_stage = 'waiting_marketers'
  AND owner_id <> auth.uid()
  AND selected_marketer_id IS NULL
ORDER BY created_at DESC
LIMIT 20;

-- ب) مكتب 1073743757
SELECT set_config('request.jwt.claim.sub', '5e5044c7-a2e0-4277-9700-9d4777b66724', true);

SELECT auth.uid() AS simulated_office_uid;

SELECT
  public.marketer_can_read_listing_request('02ae7a9c-fbff-4507-afad-de828e5c5d9a')
    AS office_can_read_jazan;

SELECT id, title
FROM public.listing_requests
WHERE workflow_stage = 'waiting_marketers'
  AND owner_id <> auth.uid()
  AND selected_marketer_id IS NULL
LIMIT 20;

-- ج) صاحب الطلب نفسه — يجب أن يكون false / قائمة فارغة من السوق
SELECT set_config('request.jwt.claim.sub', '96bad4d0-8463-46b5-9525-575f477b7c88', true);

SELECT
  public.marketer_can_read_listing_request('02ae7a9c-fbff-4507-afad-de828e5c5d9a')
    AS owner_can_read_own_via_open_market;
