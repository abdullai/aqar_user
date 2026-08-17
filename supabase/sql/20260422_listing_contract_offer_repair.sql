-- =============================================================================
-- إصلاح اختياري: PostgrestException contract_offer_mismatch عند publish_property_from_contract
--
-- الشرط في الدالة: listing_contracts.offer_id يساوي listing_requests.selected_offer_id
-- ولا يكون offer_id فارغاً. إن وُقّع العقد قبل مزامنة العرض المختار، يحدث الخطأ.
--
-- راجع الصفوف أولاً، ثم نفّذ التحديث المناسب (نسخة واحدة حسب وضعك).
-- =============================================================================

-- معاينة عقود موقعة بعرض غير متطابق أو NULL
-- SELECT c.id, c.request_id, c.offer_id AS contract_offer, r.selected_offer_id AS request_offer, c.status
-- FROM public.listing_contracts c
-- JOIN public.listing_requests r ON r.id = c.request_id
-- WHERE c.status::text = 'signed'
--   AND (
--     c.offer_id IS NULL
--     OR c.offer_id IS DISTINCT FROM r.selected_offer_id
--   );

-- إصلاح شائع: تعبئة offer_id في العقد من الطلب إذا كان العقد NULL والطلب له selected_offer_id
-- UPDATE public.listing_contracts c
-- SET offer_id = r.selected_offer_id
-- FROM public.listing_requests r
-- WHERE r.id = c.request_id
--   AND c.status::text = 'signed'
--   AND c.offer_id IS NULL
--   AND r.selected_offer_id IS NOT NULL;

-- أو عكسياً: مزامنة الطلب مع العقد إذا كان العقد يحمل العرض الصحيح
-- UPDATE public.listing_requests r
-- SET selected_offer_id = c.offer_id
-- FROM public.listing_contracts c
-- WHERE c.request_id = r.id
--   AND c.status::text = 'signed'
--   AND c.offer_id IS NOT NULL
--   AND r.selected_offer_id IS DISTINCT FROM c.offer_id;

-- =============================================================================
-- حالة خاصة: العقد موقّع و offer_id = NULL و selected_offer_id = NULL
-- (مثال: 5afb5c66-a2c3-4ea1-b6af-3af85866395d / request 97ccf2a6-e444-443c-b229-6d1532515d63)
-- لا يمكن «نسخ» العرض من الطلب أو العقد؛ يلزم ربط يدوي من listing_offers.
--
-- إن كان العرض الوحيد للطلب بحالة cancelled (أو غير مقبول): لا تربط العقد به —
-- publish_property_from_contract والمنطق التجاري يفترضان عرضاً مقبولاً.
-- الخيارات: حذف العقد إن كان اختباراً، أو إعادة فتح مسار عرض جديد ثم ربط صحيح.
-- =============================================================================

-- 1) اعرض عروض هذا الطلب (اختر id العرض الصحيح — غالباً accepted/selected)
-- SELECT id, request_id, marketer_id, status, created_at, updated_at, round_no
-- FROM public.listing_offers
-- WHERE request_id = '97ccf2a6-e444-443c-b229-6d1532515d63'
-- ORDER BY updated_at DESC NULLS LAST, created_at DESC;

-- 2) إن وافق marketer_id في العقد عرضاً واحداً فقط، يمكن الربط بهذا العرض (استبدل UUID العرض)
-- WITH c AS (
--   SELECT id, request_id, marketer_id FROM public.listing_contracts
--   WHERE id = '5afb5c66-a2c3-4ea1-b6af-3af85866395d'
-- ),
-- pick AS (
--   SELECT o.id AS offer_id
--   FROM public.listing_offers o
--   JOIN c ON c.request_id = o.request_id AND c.marketer_id = o.marketer_id
--   ORDER BY o.updated_at DESC NULLS LAST
--   LIMIT 1
-- )
-- UPDATE public.listing_contracts lc
-- SET offer_id = pick.offer_id
-- FROM c, pick
-- WHERE lc.id = c.id AND pick.offer_id IS NOT NULL;

-- UPDATE public.listing_requests lr
-- SET selected_offer_id = pick.offer_id
-- FROM c, pick
-- WHERE lr.id = c.request_id AND pick.offer_id IS NOT NULL;

-- 3) إن كان الصف اختباراً فقط: حذف العقد (احذر CASCADE/مراجع أخرى)
-- DELETE FROM public.listing_contracts WHERE id = '5afb5c66-a2c3-4ea1-b6af-3af85866395d';
