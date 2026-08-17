# 2026-06-02 — شفافية الفاتورة (الضريبة 5% + عمولة التسويق) + قفل النشر + صورة افتراضية (v9)

## ملخّص تنفيذي

أُضيفت قدرة كاملة لإظهار الفاتورة على نحو يتطابق مع متطلبات هيئة الزكاة والضريبة
والجمارك (ZATCA) والهيئة العامة للعقار (REGA) داخل تطبيق المعلن:

- سؤالان واضحان عند إنشاء أو تعديل أي إعلان عقاري:
  1. هل الإجمالي **شامل** ضريبة القيمة المضافة 5%؟ (نعم / لا)
  2. هل إجمالي السعر يحوي **عمولة التسويق العقاري**؟ (لا توجد / 2.5% / مبلغ مقطوع)
- تفصيل فاتورة حيّ يظهر تحت الحقول مباشرةً ويُحدَّث مع كل تغيير.
- تفصيل الفاتورة يظهر **فقط** داخل صفحة تفاصيل الإعلان عند الضغط على البطاقة،
  وفي شاشات الإيصالات والمشاركة. **كل بطاقات الإعلان العقاري** في التطبيق
  (الرئيسية، صفحتي، إعلاناتي/طلباتي للمسوّق، السلة، صفقاتي، نتائج البحث، …)
  تعرض «السعر الأساسي» الذي أدخله المعلن مباشرةً — دون إضافة أو خصم أي
  ضريبة أو عمولة.
- صورة افتراضية (شعار التطبيق) تُحقن تلقائياً عند عدم رفع المعلن لأي وسائط،
  وتُسجَّل علامة `default_cover_used = true` في قاعدة البيانات.
- قفل زر النشر (لا يُسمح بالنشر مرتين) وحماية الرجوع/الخروج أثناء عملية النشر
  حتى ظهور رقم الإعلان/الطلب — مطبَّق على صفحة إضافة الإعلان وصفحة طلب التسويق.
- جميع المبالغ ترسم باستخدام `AppMoneyLine` مع رمز الريال السعودي الذكي
  (`SaudiRiyalSymbolIcon`) الذي يتكيّف حجمه مع المبلغ في النصوص العربية.

---

## 1. ملف الترحيل

- المسار: `supabase/migrations/20260602120000_listing_pricing_vat_commission_v9.sql`
- جداول متأثرة:
  - `public.properties` ← الأعمدة الستة الجديدة + قيود تحقق.
  - `public.listing_requests` ← الأعمدة الخمسة الأولى (بدون `default_cover_used`).
  - `public.market_property_requests` ← العمود `default_cover_used` فقط.
- دالة مساعدة: `public.fn_listing_invoice_breakdown(...)` تُرجع
  `(base_price, vat_amount, total_with_vat, commission_amount, final_total)`.
- View للتقارير: `public.v_property_invoice_breakdown` ← يربط كل عقار بحسابه
  المفصّل، مفيد لتقارير ZATCA و REGA.
- backfill: لا يحتاج لـ UPDATE صريح؛ القيم الافتراضية على الأعمدة الجديدة تجعل
  الإعلانات السابقة تظهر «شاملة الضريبة + بدون عمولة» (قرار محافظ متفق عليه).

### الأعمدة الجديدة

| العمود | النوع | الافتراضي | الوصف |
|--------|------|-----------|------|
| `price_includes_vat` | bool | `true` | هل `price` شامل الضريبة؟ |
| `vat_rate` | numeric(5,4) | `0.0500` | نسبة الضريبة (للحفظ التاريخي) |
| `marketing_commission_kind` | text | `'none'` | `none` \| `percent` \| `fixed` |
| `marketing_commission_rate` | numeric(5,4) | `0.0250` | نسبة العمولة عند `percent` |
| `marketing_commission_amount` | numeric(14,2) | `0` | المبلغ المقطوع عند `fixed` |
| `default_cover_used` | bool | `false` | استُخدمت صورة افتراضية للغلاف؟ |

### قيود التحقق

- `marketing_commission_kind ∈ {none, percent, fixed}`.
- `0 ≤ vat_rate ≤ 0.5`.
- `0 ≤ marketing_commission_rate ≤ 0.25`.
- `marketing_commission_amount ≥ 0`.

---

## 2. منطق احتساب الفاتورة (مركزي وموحّد)

```
base   = price_includes_vat ? price / (1 + vat_rate) : price
vat    = base * vat_rate
total_with_vat = base + vat   // = price إن كان شامل، وإلا price + vat
commission = kind == 'percent' ? base * commission_rate
            : kind == 'fixed'   ? commission_amount
            : 0
final_total = total_with_vat + commission
```

نُفِّذ هذا المنطق في **ثلاثة أماكن متطابقة**:

1. SQL: `fn_listing_invoice_breakdown(...)` و View `v_property_invoice_breakdown`.
2. Dart (نموذج العقار): `Property.effectiveBasePrice` / `vatAmount` /
   `totalWithVat` / `marketingCommissionTotal` / `finalTotalPrice` /
   `displayTotalPrice` في `lib/models/property.dart`.
3. Dart (واجهة المستخدم): `ListingInvoiceModel` في
   `lib/widgets/listing_pricing_breakdown.dart` للمعاينة الحيّة دون الحاجة لحفظ.

---

## 3. ملفات Flutter المتأثّرة

### نموذج البيانات

- `lib/models/property.dart`:
  - إضافة الحقول الستة + قراءتها في كلٍ من `fromJson` و `fromDbRow`.
  - تحديث `copyWith` لتمرير الحقول الجديدة.
  - إضافة `_normalizeCommissionKind` (حارس قيم النصّ).
  - إضافة getters للحساب: `effectiveBasePrice`, `vatAmount`, `totalWithVat`,
    `marketingCommissionTotal`, `finalTotalPrice`, `displayTotalPrice`,
    `homeCardPrice`, `hasInvoiceDetails`.

### Widget مشترك

- `lib/widgets/listing_pricing_breakdown.dart` (ملف جديد):
  - `ListingInvoiceModel`: نموذج خفيف بحسابات مطابقة لجدول الترحيل.
  - `ListingPricingBreakdown`: بطاقة تعرض تفصيل الفاتورة بترتيب:
    1. السعر الأساسي.
    2. ضريبة القيمة المضافة (مع توضيح: محتسبة ضمن المبلغ / مضافة على المبلغ).
    3. الإجمالي مع الضريبة.
    4. عمولة التسويق (نسبة أو مبلغ مقطوع) — إن وُجدت.
    5. المجموع النهائي (مظلَّل ومميَّز).
  - يستخدم `AppMoneyLine` لكل سطر مبلغ ⇒ رمز الريال الذكي تلقائياً.

### صفحة إضافة الإعلان

- `lib/screens/add_property_page.dart`:
  - حقول حالة جديدة: `_priceIncludesVat (bool?)`, `_commissionKind (String)`,
    `_commissionFixedCtrl (TextEditingController)`, `_publishLock`,
    `_usedDefaultCover`.
  - widgetان جديدان داخل الملف: `_VatInclusionQuestion` و
    `_CommissionKindQuestion`. الأول يحمر إن لم يُجَب عليه قبل النشر.
  - معاينة فاتورة حيّة `ListingPricingBreakdown` أسفل أسئلة الفوترة مباشرة.
  - تحديث `_canSubmit` ليطلب الإجابة على السؤال الأول وقيمة موجبة عند `fixed`.
  - إضافة `default_cover_used: true` عند حقن الصورة الافتراضية.
  - تمرير الأعمدة الجديدة في:
    - `_buildPayload(...)` (إعلان مباشر للمسوّقين).
    - `_buildRequestPayload(...)` (طلب فردي قبل التحقق من فال).
    - `_listingGuidanceForInsert()` كنسخة احتياطية داخل JSONB.
  - معالجة احتياطية تُسقط الأعمدة الجديدة عند الـ INSERT إن كان الترحيل لم
    يُطبَّق بعد على البيئة (`column ... does not exist`).
  - قفل النشر: `_publishLock=true` عند بدء `_submit` ولا يُحرَّر إلا بعد إغلاق
    `_showSuccessChoice` / `_showRequestSuccess` (ظهور رقم الإعلان) أو فشل.
  - زر «نشر الإعلان» يتبدّل إلى «جاري النشر…» مع مؤشّر تحميل.
  - `PopScope` يمنع الرجوع/الخروج وأعمدة AppBar `automaticallyImplyLeading=false`
    أثناء `_publishLock || _saving` لمنع إعادة الإرسال.
  - إعادة ضبط القيم في `_resetForm()`.

### صفحة تعديل الإعلان

- `lib/screens/edit_property_page.dart`:
  - حقول حالة جديدة مشابهة لصفحة الإضافة، مع تحميل القيم من `Property`.
  - widgetان `_EditVatQuestion` و `_EditCommissionQuestion` (مكافئان لصفحة
    الإضافة).
  - معاينة فاتورة حيّة أسفل الأسئلة.
  - حفظ القيم في عمل `update` مستقل بعد `owner_edit_property` RPC، مع تجاهل
    صامت إن لم تكن الأعمدة موجودة بعد على البيئة.
  - مرآة احتياطية ضمن `_listingGuidancePayloadForSave().pricing`.

### صفحة تفاصيل الإعلان

- `lib/screens/property_details_page.dart`:
  - استبدال الحسابات الثابتة (`* 0.05` و `* 0.025`) بـ `ListingInvoiceModel`
    المشتقّ من حقول `Property` الجديدة.
  - استبدال بلوك `_PriceRow * 5` ببطاقة موحّدة `ListingPricingBreakdown`.
  - تحديث نص المشاركة `_shareText` ليعكس وجود/غياب العمولة وحالة الضريبة.

### صفحة طلب التسويق (Property Request)

- `lib/screens/create_market_property_request_page.dart`:
  - حقول `_publishLock` و `_usedDefaultCover`.
  - دالة `_injectDefaultCoverIfMissing()` تحقن `assets/logo.png` كغلاف
    افتراضي إن لم يختر المستخدم صورة.
  - تمرير `default_cover_used: true` للـ INSERT، مع fallback صامت إن لم يكن
    العمود موجوداً (الترحيل غير مطبَّق).
  - `PopScope` يمنع الرجوع أثناء `_saving || _publishLock` ويعرض
    `SnackBar` تنبيهي بدلاً من السماح بالإغلاق.
  - زر «نشر الطلب» يتبدّل إلى «جاري النشر…» مع مؤشّر.
  - تحرير `_publishLock` على الخطأ، ويبقى مرفوعاً حتى إغلاق حوار النجاح
    (`Navigator.pop` يدمّر الصفحة فيُحرَّر تلقائياً).

### قاعدة عرض البطاقات (سياسة موحَّدة)

> **قاعدة ذهبية**: كل بطاقة إعلان عقاري — في أي مكان داخل المشروع — تعرض
> **السعر الأساسي** الذي أدخله المعلن (`property.price`)، **دون** أي إضافة
> أو خصم لضريبة القيمة المضافة أو لعمولة التسويق. أي تفصيل للفاتورة
> (الأساسي/الضريبة/العمولة/المجموع النهائي) لا يظهر إلا داخل **صفحة تفاصيل
> الإعلان** عند الضغط على البطاقة، وداخل الإيصالات وأدوات المشاركة.

تطبيقات هذه القاعدة:

- `lib/models/property.dart`:
  - `Property.displayTotalPrice` يعود `price.toDouble()` (وليس
    `finalTotalPrice`).
  - `Property.homeCardPrice` يبقى مرادفاً مباشراً لقيمة الإدخال.
  - `Property.finalTotalPrice` لم تتغيّر دلالته (الأساسي ± الضريبة + العمولة)
    ويُستخدم حصراً داخل بطاقات الفاتورة في الشاشات التفصيلية والإيصالات.
- `lib/screens/user_dashboard.widgets.dart`:
  - `_unifiedListCard` يبني المبلغ من `property.price.toDouble()` لكل
    البطاقات (الرئيسية، صفحتي، نتائج البحث، …) بصرف النظر عن `ownerHubListingCard`.
- `lib/screens/user_dashboard.my_ads_hub.dart`:
  - بطاقات تبويبات «صفحتي» للمالك (`p.price`).
  - بطاقات تبويبات «إعلاناتي/طلباتي» للمسوّق + شريط
    `_hubMarketerPriceStrip` + شيب السعر المصغّر: جميعها تستدعي
    `_buildMarketingPriceLine(..., displayListingTotalIncVatAndFee: false)`
    لإجبار العرض على السعر الأساسي.
- بطاقات السلة وصفقاتي:
  - بطاقة العقار الموحّدة (`_unifiedListCard`) تخضع للقاعدة أعلاه.
  - بطاقات الحجز (`_buildCartMarketOfferCard` و `_buildCompletedPurchaseCard`)
    تبقى كما هي لأنها تعرض **مبالغ الحجز الفعلية** المسجَّلة في صفّ الحجز
    (`base_price`/`platform_fee_amount`/`extra_fee_amount`/`total_amount`)
    وليست أسعار العقار.

---

## 4. تأثير على البطاقات والمعاينة

| الموقع | المبلغ المعروض | الملاحظات |
|--------|---------------|-----------|
| بطاقات الصفحة الرئيسية | `property.price` (كما أدخله المعلن) | لا حسابات. |
| بطاقات «صفحتي» (المالك) | `property.price` | لا حسابات. |
| بطاقات «إعلاناتي/طلباتي» (المسوّق) | السعر الأساسي من صفّ الإعلان | لا حسابات. |
| بطاقات «السلة» و«صفقاتي حاليا» | `property.price` (للعقار) | الحجز يبقى بمبالغه. |
| بطاقات نتائج البحث | `property.price` | لا حسابات. |
| **صفحة تفاصيل الإعلان** | `ListingPricingBreakdown` (5 أسطر) | الأساسي / الضريبة / الإجمالي مع الضريبة / العمولة / المجموع النهائي. |
| الفواتير والإيصالات | كل الأسطر الخمسة | مطابقة لـ `fn_listing_invoice_breakdown`. |
| المعاينة الحيّة في إضافة/تعديل الإعلان | كل الأسطر الخمسة | تتحدّث مع كل تغيير في الحقول. |

---

## 5. قفل النشر ومنع التكرار

- `add_property_page` و `create_market_property_request_page`:
  - علم `_publishLock` يُرفع لحظة الضغط على «نشر».
  - زر النشر يتحوّل إلى «جاري النشر…» مع `CircularProgressIndicator`.
  - `PopScope(canPop: !_publishLock && !_saving, …)` يمنع زر الرجوع
    وإيماءات الإغلاق ويعرض `SnackBar` تنبيهي.
  - `automaticallyImplyLeading: false` على AppBar أثناء النشر.
  - `_publishLock` لا يُحرَّر إلا عند ظهور حوار النجاح (الذي يحتوي رقم الإعلان)
    أو فشل العملية (تحرير صريح للسماح بالمعاودة).

## 6. صورة افتراضية عند عدم رفع وسائط

- `add_property_page._injectDefaultCoverIfNoMedia()` و
  `create_market_property_request_page._injectDefaultCoverIfMissing()`:
  - يحمّلان `assets/logo.png` كبايتات ويعتبرانه غلاف الإعلان عند عدم رفع
    المستخدم لأي صورة قبل النشر.
  - `_usedDefaultCover = true` يُكتب في عمود `default_cover_used` (إن وُجد) أو
    داخل `listing_guidance.media.used_default_cover` كنسخة احتياطية.
  - الـ View `v_property_invoice_breakdown` لا يهتم بهذا الحقل؛ هو مفيد فقط
    لتقارير الجودة لإحصاء كم إعلانٍ يستخدم صورة افتراضية.

## 7. التراجع / الـ Rollback

في حال احتاج فريق التشغيل التراجع، يمكن:

```sql
-- إسقاط الـ view ثم الدالة (آمن لأنهما اشتقاقيّان):
DROP VIEW IF EXISTS public.v_property_invoice_breakdown;
DROP FUNCTION IF EXISTS public.fn_listing_invoice_breakdown(numeric, boolean, numeric, text, numeric, numeric);

-- إعادة الأعمدة إلى ما كانت عليه (انتباه: سيُفقد محتواها):
ALTER TABLE public.properties
  DROP COLUMN IF EXISTS price_includes_vat,
  DROP COLUMN IF EXISTS vat_rate,
  DROP COLUMN IF EXISTS marketing_commission_kind,
  DROP COLUMN IF EXISTS marketing_commission_rate,
  DROP COLUMN IF EXISTS marketing_commission_amount,
  DROP COLUMN IF EXISTS default_cover_used;
-- نفس الأعمدة على listing_requests و market_property_requests.
```

كود Flutter متسامح مع غياب الأعمدة (try/catch صامت)، لذلك التراجع لا يكسر
الواجهة — فقط تختفي تفاصيل الفاتورة، ويعود التطبيق لعرض السعر كما هو.

## 8. خلاصة الضمانات

- **ZATCA**: كل فاتورة تُظهر الأساسي والضريبة بصراحة، سواء كانت الضريبة شاملة
  في المبلغ أو مضافة عليه. التسمية واضحة في كلا اللغتين.
- **REGA**: تفصيل عمولة التسويق ظاهر للمعلن وللمسوّق ضمن نفس البطاقة، مع
  إمكانية المبلغ المقطوع لاستيفاء حالات الاتفاقيات الخاصة.
- **منع التكرار**: لا يمكن إرسال نفس الإعلان مرتين بأي زر أو إيماءة.
- **اتساق بصري**: كل بطاقة في التطبيق تعرض نفس قاعدة السعر (الإدخالي فقط)،
  وتتركز الفاتورة في صفحة التفاصيل وحدها لتجنّب الالتباس.

---

## ملحق — الترحيل v10: Backfill + Trigger مزدوج الاتجاه

بعد ترحيل v9، أُضيف ترحيل آخر لمعالجة:

1. **الإعلانات الموجودة** (drafts غير منشورة + منشورة سابقاً) التي قد تكون
   حُفظت قيم الفوترة فيها داخل `listing_guidance.pricing` (JSONB) من نسخة
   Flutter حديثة قبل تطبيق الأعمدة.
2. **ضمان مستقبلي**: أي INSERT/UPDATE تلقائياً ينقل الأرقام إلى الأعمدة المطلوبة
   ويحتفظ بنسخة احتياطية متطابقة داخل JSONB.

**الملف**: `supabase/migrations/20260602130000_pricing_backfill_and_sync_trigger_v10.sql`

### ما يفعله:

- **(A) Backfill**: لكل صف في `properties` و `listing_requests` لديه
  `listing_guidance.pricing` غير فارغ، يقرأ القيم الصحيحة
  (`price_includes_vat`, `vat_rate`, `marketing_commission_kind`,
  `marketing_commission_rate`, `marketing_commission_amount`,
  `default_cover_used`) وينسخها إلى الأعمدة المخصّصة الجديدة. الصفوف بدون
  pricing تبقى بالقيم الافتراضية الآمنة (شامل ضريبة 5%، بدون عمولة).

- **(B) Trigger `trg_*_pricing_sync`** على الجدولين قبل INSERT/UPDATE:
  - **اتجاه JSONB → الأعمدة** (INSERT فقط، عندما تكون الأعمدة افتراضية):
    إذا كانت `listing_guidance.pricing` تحوي قيماً صحيحة، يملأ الأعمدة منها.
  - **اتجاه الأعمدة → JSONB** (دائماً): يُحدِّث
    `listing_guidance.pricing` ليطابق الأعمدة الحالية + `synced_at` للتدقيق.
    وكذلك `listing_guidance.media.used_default_cover`.

- **(C) دالة مساعدة `fn_resync_listing_pricing(table, id)`**: تُستخدم من
  `service_role` لإعادة المزامنة اليدوية لصف واحد (للديباغ).

- **(D) تقرير ضمن سجل التنفيذ**: `RAISE NOTICE` بعدد الصفوف التي صار لديها
  `pricing.synced_at`، للتحقق من النجاح.

### كيف يستفيد المالك من هذا؟

- إعلانات draft القديمة → افتح أي إعلان عبر «تعديل الإعلان»، أجب على السؤالين،
  احفظ. الـ trigger يضمن المزامنة الكاملة، وتظهر الفاتورة فوراً صحيحة في:
  - تفاصيل الإعلان.
  - معاينة الفاتورة في الإضافة/التعديل.
  - الإيصالات والـ View `v_property_invoice_breakdown` للتقارير.

- أي إعلان جديد → تُملأ الأعمدة المخصّصة مباشرةً من Flutter، والـ trigger يضع
  مرآةً في JSONB دون أي عمل إضافي.

---

## ملحق — التحديث الذي تلا الترحيل الناجح (نفس اليوم)

بناءً على ملاحظة المالك بعد نجاح الترحيل: بطاقات «صفحتي» وبطاقات
«إعلاناتي/طلباتي» للمسوّق وبطاقات السلة وأي بطاقة عقار في التطبيق يجب أن
تعرض السعر الأساسي كما أدخله المعلن، وأن تظهر الفاتورة المفصّلة فقط داخل
صفحة تفاصيل الإعلان عند الضغط على البطاقة. تم تطبيق هذا التحديث في:

- `Property.displayTotalPrice` → يُعيد الآن `price` بدل `finalTotalPrice`.
- `_unifiedListCard` في `user_dashboard.widgets.dart` يستخدم
  `property.price.toDouble()` لكل البطاقات.
- `user_dashboard.my_ads_hub.dart`:
  - بطاقة هَب المالك تعرض `p.price` (بدل `p.displayTotalPrice` المؤقت).
  - كل النداءات لـ `_buildMarketingPriceLine(..., displayListingTotalIncVatAndFee: true)`
    تحوّلت إلى `false` (شريط السعر في تبويبات «إعلاناتي/طلباتي» للمسوّق).
- دالة `MarketingOfferFee.listingDisplayTotalIncVatAndFee` تُركت في مكانها
  لأنها أداة عامة لحساب الإجمالي وقد تُستخدم في الفاتورة لاحقاً، لكن لا
  يستدعيها أي عرض بطاقة بعد الآن.
- صفحة `property_details_page.dart` — لم تتأثر؛ هي المكان الوحيد الذي يبقى
  يظهر تفصيل الفاتورة الكامل عبر `ListingPricingBreakdown` + نموذج
  `ListingInvoiceModel` المشتقّ من الحقول الجديدة في `Property`.