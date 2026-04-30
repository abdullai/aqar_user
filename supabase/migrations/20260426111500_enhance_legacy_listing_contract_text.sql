BEGIN;

WITH src AS (
  SELECT
    c.id,
    c.request_id,
    c.created_at,
    c.owner_signed_at,
    c.marketer_signed_at,
    lr.title,
    lr.city,
    lo.price,
    lo.notes,
    owner_p.full_name_ar AS owner_full_name_ar,
    owner_p.full_name AS owner_full_name,
    owner_p.full_name_en AS owner_full_name_en,
    marketer_p.office_name AS marketer_office_name,
    marketer_p.full_name_ar AS marketer_full_name_ar,
    marketer_p.full_name AS marketer_full_name,
    marketer_p.full_name_en AS marketer_full_name_en,
    marketer_p.license_no AS marketer_license_no
  FROM public.listing_contracts c
  JOIN public.listing_requests lr ON lr.id = c.request_id
  LEFT JOIN public.listing_offers lo ON lo.id = c.offer_id
  LEFT JOIN public.users_profiles owner_p ON owner_p.user_id = c.owner_id
  LEFT JOIN public.users_profiles marketer_p ON marketer_p.user_id = c.marketer_id
  WHERE
    nullif(trim(coalesce(c.contract_text, '')), '') IS NULL
    OR c.contract_text LIKE 'اتفاقية تسويق عقاري (مسودة إلكترونية)%'
    OR c.contract_text LIKE 'عقد تسويق عقاري%رقم الطلب:%تم إنشاء هذه المسودة تلقائياً%'
)
UPDATE public.listing_contracts c
SET
  contract_text = concat_ws(E'\n\n',
    'عقد تسويق عقاري إلكتروني',
    'رقم العقد: ' || src.id::text,
    'تاريخ العقد: ' || to_char(coalesce(src.created_at, now()), 'YYYY-MM-DD'),
    'رقم الطلب: ' || src.request_id::text,
    'عنوان الإعلان: ' || coalesce(nullif(trim(src.title::text), ''), 'غير محدد'),
    'المدينة: ' || coalesce(nullif(trim(src.city::text), ''), 'غير محدد'),
    'أتعاب التسويق المتفق عليها: ' || coalesce(src.price::text, '0') || ' SAR',
    'أولاً: أطراف العقد',
    'الطرف الأول: مالك / معلن العقار' ||
      CASE WHEN nullif(trim(coalesce(src.owner_full_name_ar, src.owner_full_name, src.owner_full_name_en, '')), '') IS NOT NULL
        THEN ' (' || trim(coalesce(src.owner_full_name_ar, src.owner_full_name, src.owner_full_name_en)) || ')'
        ELSE ''
      END || '، ويُعرَف بهوية حسابه وسجلاته في المنصة.',
    'الطرف الثاني: المسوق العقاري المعتمد' ||
      CASE WHEN nullif(trim(coalesce(src.marketer_office_name, src.marketer_full_name_ar, src.marketer_full_name, src.marketer_full_name_en, '')), '') IS NOT NULL
        THEN ' (' || trim(coalesce(src.marketer_office_name, src.marketer_full_name_ar, src.marketer_full_name, src.marketer_full_name_en)) || ')'
        ELSE ''
      END ||
      CASE WHEN nullif(trim(coalesce(src.marketer_license_no, '')), '') IS NOT NULL
        THEN '، رقم رخصته: ' || trim(src.marketer_license_no)
        ELSE ''
      END || '.',
    'ثانياً: موضوع العقد',
    'يفوّض الطرف الأول الطرف الثاني بتسويق العقار محل الطلب داخل المنصة، ومتابعة إجراءات عرض الإعلان وتجهيز المتطلبات النظامية اللازمة لاستخراج تصاريح الإعلان العقاري من منصة عقار/الجهات المختصة خلال مدة لا تتجاوز 72 ساعة من اكتمال التوقيع وتوفر البيانات والمستندات الصحيحة.',
    'ثالثاً: الالتزامات',
    '1. يقر الطرف الأول بصحة بيانات العقار والملكية أو التفويض، ويلتزم بتقديم أي بيانات أو مستندات تطلبها المنصة أو الجهة المختصة.',
    '2. يلتزم الطرف الثاني ببذل العناية المهنية في التسويق، وعدم نشر الإعلان إلا بعد اكتمال التصاريح والمطابقة النظامية.',
    '3. لا يجوز للطرف الثاني تمثيل بيانات غير صحيحة أو مخالفة لبيانات الترخيص أو رخصة فال أو ما يعادلها.',
    '4. في حال عدم اكتمال التصريح خلال 72 ساعة لأسباب راجعة لعدم توفر البيانات أو رفض الجهة المختصة، يعاد الطلب للمراجعة أو يعرض على مسوقين آخرين وفق سير العمل داخل المنصة.',
    'رابعاً: الإثبات الإلكتروني',
    'يقر الطرفان بأن التوقيع الإلكتروني، وسجل التدقيق، ورمز الاستجابة السريع للتحقق، ورقم العقد، تعد قرائن إثبات معتبرة داخل المنصة.',
    CASE
      WHEN nullif(trim(coalesce(src.notes, '')), '') IS NOT NULL
        THEN 'ملاحظات العرض:' || E'\n' || trim(src.notes)
      ELSE NULL
    END,
    'خامساً: التوقيع',
    'توقيع الطرف الأول (المعلن/المالك): ' || CASE WHEN src.owner_signed_at IS NOT NULL THEN 'وُقِع إلكترونياً بتاريخ ' || to_char(src.owner_signed_at, 'YYYY-MM-DD') ELSE 'بانتظار التوقيع الإلكتروني' END,
    'توقيع الطرف الثاني (المسوق العقاري/المنشأة): ' || CASE WHEN src.marketer_signed_at IS NOT NULL THEN 'وُقِع إلكترونياً بتاريخ ' || to_char(src.marketer_signed_at, 'YYYY-MM-DD') ELSE 'يكتمل من داخل التطبيق' END
  ),
  updated_at = now()
FROM src
WHERE c.id = src.id;

COMMIT;
