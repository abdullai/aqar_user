BEGIN;

WITH src AS (
  SELECT
    c.id,
    c.request_id,
    lr.city,
    lr.title,
    lo.price,
    lo.notes
  FROM public.listing_contracts c
  JOIN public.listing_requests lr ON lr.id = c.request_id
  LEFT JOIN public.listing_offers lo ON lo.id = c.offer_id
  WHERE nullif(trim(coalesce(c.contract_text, '')), '') IS NULL
)
UPDATE public.listing_contracts c
SET
  contract_text = concat_ws(E'\n\n',
    'عقد تسويق عقاري',
    'رقم الطلب: ' || src.request_id::text,
    'المدينة: ' || coalesce(nullif(trim(src.city::text), ''), 'غير محدد'),
    'العقار: ' || coalesce(nullif(trim(src.title::text), ''), 'غير محدد'),
    'أتعاب التسويق: ' || coalesce(src.price::text, '0') || ' SAR',
    CASE
      WHEN nullif(trim(coalesce(src.notes, '')), '') IS NOT NULL
        THEN 'ملاحظات العرض: ' || trim(src.notes)
      ELSE NULL
    END,
    'تم إنشاء هذه المسودة تلقائياً من العرض المقبول. يراجع الطرفان النص داخل التطبيق قبل التوقيع.'
  ),
  updated_at = now()
FROM src
WHERE c.id = src.id;

COMMIT;
