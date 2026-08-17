# مرجع واجهة «صفحتي / إدارتي» — `user_dashboard.my_ads_hub.dart`

> يصف **كل عنصر تفاعلي** (أزرار، `InkWell`، `ListTile.onTap`، أيقونات ضغط) **حسب موقعه في الشجرة** و**الدالة المستهدفة** والمسار الناتج.  
> مبني على الكود الحالي في المستودع (بدون افتراض سلوك غير موجود).

---

## 0) من يرى ماذا؟

| نوع المستخدم | الشاشة داخل `MyAdsHub` | ملاحظة |
|--------------|-------------------------|--------|
| **مالك / غير مسوّق** | تبويبات **صفحتي** (6): `_buildOwnerMyAds` | `TabController` طوله 6 |
| **مسوّق موثّق** | تبويبات **إدارتي** (6): `_buildMarketerMyAds` | `TabController` طوله 6 |
| **زائر (guest)** | يُستدعى حوار تسجيل عند الحاجة (`_showLoginDialog`) | مثلاً مفضلة من بطاقة عقار |

---

## 0.1) بطاقة الإعلان في الرئيسية / المفضلة + تفاصيل العقار (هوية المعلن والناشر)

| السياق | المكوّن / الملف | السلوك |
|--------|------------------|--------|
| **الرئيسية والمفضلة** | `_HomeMixedTimeline` و`_PropertyGrid` في `user_dashboard.ui.dart` | يُمرَّر `suppressPublicOwnerIdentityOnCards: true` حتى لا يظهر الاسم الرباعي للمعلن على البطاقة العامة؛ و`onShareListingFromCard: _shareListingFromCard` لمشاركة الرابط (وصورة أولى إن وُجدت). |
| **صفحتي — إعلانات منشورة** | `publishedTile` → `_RealEstateCard` | القيمة الافتراضية لـ `suppressPublicOwnerIdentity` = `false` (لا قمع الهوية لمالك إعلانه). |
| **تفاصيل العقار** | `PropertyDetailsPage` + `_openDetails` في `user_dashboard.actions.dart` | باراميتر `showOwnerLegalNameToViewer`: **true** للمسوّق فقط و**قبل النشر** (`effectiveWorkflowStage != published`) لإظهار «هذا الإعلان بواسطة» والاسم الرباعي. بعد اعتبار الإعلان منشوراً (`_isPublishedLikeListing`): قسم **«نشر بواسطة»** + صورة العلامة من `marketerBrandImagePublicUrl` (إن وُجدت) + اسم الجهة من `marketingLicenseSnapshot`؛ ويُخفى الاسم الرباعي عن غير المالك. المالك يبقى يرى كتلة «المعلن (أنت)» تحت قسم النشر عند إدارة إعلانه. |

**ملاحظة:** مسار الدردشة مع المالك حسب تفعيل التواصل عند الإنشاء، وحدّ الرفض (3 مسوّقين) ومصفوفة الإشعارات لكل مرحلة — تتطلب إكمالاً في الخادم والتوجيه؛ هذا الملحق يوثّق ما تغطيه الواجهة الحالية في الكود.

### تعديل الإعلان (مالك / مسوّق) + RLS

| الجهة | الشرط (Dart: `ListingEditPermissions`) | أين في الواجهة |
|--------|----------------------------------------|----------------|
| **المالك** | يعدّل حتى **قبل** مرحلة التصاريح (`permit_pending` / `permit_issued`) وليس منشوراً؛ مع `edit_count < max_edits`. | `EditPropertyPage` (المسار العادي)، بطاقة «إعلاناتي المنشورة» تخفي أيقونة التعديل عند عدم الإتاحة؛ تفاصيل العقار تعطّل زر التعديل مع نص توضيحي. |
| **المسوّق** | بعد **`permit_issued_at`** ومرحلة `permit_pending` أو `permit_issued`، وليس منشوراً، وهو `selected_marketer_id` أو `published_by_marketer_id`. | `PropertyDetailsPage`: بطاقة «مطابقة بيانات الهيئة» + `EditPropertyPage(marketerRegaAlignmentMode: true)` — حفظ جزئي عبر `UPDATE` على `properties` (بدون RPC المالك). |
| **بعد النشر** | لا تعديل مباشر من المالك/المسوّق في الواجهة الحالية إلا عبر طلبات الإدارة (حذف إلخ). | — |

**قاعدة البيانات:** ملف `supabase/sql/20260446_properties_update_workflow_rls_v1.sql` يستبدل سياسة `UPDATE` الواسعة على `properties` بسياسة تجمع شرط المالك + شرط المسوّق (ويعتمد على `marketer_can_read_property_for_marketing`). إن وُجدت لديكم سياسة `UPDATE` لـ `is_admin()` يجب إعادتها يدوياً بعد التطبيق.

**تفاصيل العقار — دردشة:** قبل النشر يظهر للمسوّق المرتبط (أو من لديه `allowMarketingOffer`) زر **مراسلة المالك** عبر `ReservationsService.getOrCreatePropertyOwnerConversation`؛ بعد النشر يبقى زر **مراسلة المسوّق** فقط حسب المنطق السابق.

---

## 1) تبويبات المالك (صفحتي) — الفهرس 0..5

| الفهرس | عنوان التبويب | فلترة العقارات `properties` | فلترة الطلبات `listing_requests` |
|--------|----------------|------------------------------|-------------------------------------|
| **0** | بانتظار عروض المسوقين | `ownerTabMatches(0, stage)` | `ownerTabMatches(0, decision.stage)` |
| **1** | بانتظار التعاقد | `ownerTabMatches(1, …)` | نفس المنطق للطلب |
| **2** | لم يتخذ إجراء 72 ساعة | `ownerTabMatches(3, …)` | — |
| **3** | مفسوخ / ملغى | `ownerTabMatches(4, …)` | — |
| **4** | العقارات المحجوزة | — | — (محتوى مختلف) |
| **5** | إعلاناتي المنشورة | `ownerTabMatches(6, …)` | طلبات التبويبات 0–4 فقط (`tabIndex >= 5` فارغ) |

**منطق الفلترة الداخلي:** التبويبات 0–3 تستخدم أرقاماً **منطقية قديمة** `[0,1,3,4]` مع `ListingStageUiHelper.ownerTabMatches` (انظر تعليق `ownerHubLogicalTabs` في الكود).

---

## 2) بطاقات المالك — نوعان

### أ) بطاقة **طلب تسويق** — `_buildOwnerListingRequestCard`

**الضغط على جسم البطاقة (الصورة + النصوص):** `InkWell.onTap` → `open()` → `_openOwnerListingRequestFromRow(row, requestStatusId: id)`.

**محتوى ظاهر (ملخص):** غرض، عنوان فرعي، مدينة، مساحة، سعر، حالة (`ListingWorkflowUiContext`)، شريط تقدم، صور/فيديو معاينة، جهة تسويق، تلميح مالك، أوقات.

| # | عنصر | نوع | الدالة / الوجهة |
|---|------|-----|------------------|
| O1 | منطقة البطاقة العلوية | `InkWell` | `_openOwnerListingRequestFromRow` → إن وُجد `preview_property_id` يحمّل عقاراً و`_openDetails` مع `marketingRequestId`؛ وإلا `properties.request_id`؛ وإلا `ListingRequestStatusPage` |
| O2 | أيقونة «تتبع نشاط الطلب» | `IconButton` | `_showOwnerRequestActivityDialog(row)` |
| O3 | **مراجعة العروض** (شرط `showOwnerActionStrip`) | `FilledButton.icon` | `_openOwnerOffersForRequest(id)` → `OwnerOffersPage` |
| O4 | **محادثة العقد** (إن `inContractingTab` و`contractId`) | `OutlinedButton.icon` | `_openOwnerContractChat(contractId)` → `ListingContractChatPage` |

**شرط الشريط O3–O4:** `showOwnerActionStrip` = مالك غير زائر + ليس مسوّقاً + (تبويب تعاقد **أو** تبويب انتظار عروض مع `showOwnerOffersEntry`).

### ب) بطاقة **عقار** — `_RealEstateCard` داخل `_buildOwnerPublishedPropertiesList` → `publishedTile`

| # | عنصر | الربط في `publishedTile` | الوجهة |
|---|------|---------------------------|--------|
| P1 | بطاقة كاملة (افتراضي) | `onOpenDetails` | `_openDetails(p)` → `PropertyDetailsPage` |
| P2 | مفضلة | `onToggleFav` | `_toggleFav` / `_showLoginDialog` |
| P3 | عداد المشاهدات | `onViewsPillTap` | `PropertyViewService.showSheet` |
| P4 | إضافة للسلة | `onAddToCart` | `_addToCart(p)` إن `canAddToCart` و`_showBottomNavCart` وليس مالكاً |
| P5 | تعديل | `onEditProperty` | `_editProperty(p)` |
| P6 | حذف | `onDeleteProperty` | `_requestDeleteProperty(p)` |

**تحت البطاقة:** إن `effectiveWorkflowStage != published` يظهر `ListingWorkflowProgressStrip`. وقد يظهر صندوق سبب رفض عرض (`_ownerRejectionReason`).

### ج) تبويب **الحجوزات على إعلاناتك** — `_buildOwnerReservationsTab`

| # | عنصر | الوجهة |
|---|------|--------|
| R1 | `ListTile.onTap` | إن وُجد `Property p` → `_openDetails(p)`؛ وإلا لا فتح |

---

## 3) تبويبات المسوّق (إدارتي) — الفهرس 0..5

| الفهرس | العنوان | مصدر الصفوف | بناء القائمة |
|--------|---------|-------------|--------------|
| 0 | الدعوات | `_mkInvites` | `_buildSimpleRowsList` + `marketerInvitesTabLayout: true` |
| 1 | التعاقد | عروض + عقود مدمجة | `_buildMarketerContractingTab` |
| 2 | التصريح 72 ساعة | `_mkPermits` | `_buildSimpleRowsList` type `permit` |
| 3 | منشور / محجوز | `_mkPublished` | `_buildSimpleRowsList` type `published` |
| 4 | بدون إجراء 72 | فلترة صفوف | `_buildSimpleRowsList` type `invite` |
| 5 | مفسوخ / ملغى | فلترة صفوف | `_buildSimpleRowsList` type `contract` |

---

## 4) بطاقة المسوّق — `_buildMarketerRowCard` + `_buildMarketerCardBody`

### تفاعل الصورة والجسم

| # | عنصر | شرط | الاستدعاء |
|---|------|-----|-----------|
| M1 | `InkWell` على صورة المعاينة | `onImageTap()` | غالباً `_openMarketingPreviewProperty(r)` أو لدعوة نشطة `_showMarketingOfferSheetForRow` |
| M2 | `InkWell` على نص الجسم | `bodyTapCallback()` | **باطل** لتبويب دعوات بـ `marketerInvitesTabLayout` (التفاعل بالأزرار فقط)؛ وإلا مثل M1 |

### شبكة أزرار الدعوة — `_buildMarketerInviteActionsGrid`

| # | زر | الاستدعاء |
|---|-----|-----------|
| MG1 | تقديم عرض | `_showMarketingOfferSheetForRow(r)` (معطّل إن الدعوة declined/expired/offered) |
| MG2 | عرض التفاصيل | `_openMarketingPreviewProperty(r)` |

### أزرار `_buildMarketerCardBody` (حسب `type`)

| # | يظهر عندما | الزر | الاستدعاء |
|---|------------|------|-----------|
| MB1 | `invite` وليس تخطيط الدعوات الخاص | تقديم عرض | `_showMarketingOfferSheetForRow` |
| MB2 | `offer` + `requestId` | تتبع | `_showMarketerOfferTrackDialog` |
| MB3 | `offer` بدون عقد + مقبول من المالك | إنشاء عقد | `_createMarketingContract` |
| MB4 | `offer` غير مقبول بعد | نص توضيحي فقط | — |
| MB5 | `contract` + `_marketerContractFlowUnlocked` | محادثة العقد | `ListingContractChatPage` + `_marketerContractActionWidgets` |
| MB6 | `permit` | رفع التصريح | `_submitMarketingPermit` |
| MB7 | `permit` | ربط التصريح مع الهيئة | `_linkRegaAdLicenseWithAuthority` |
| MB8 | `previewPropertyId` أو `published` | فتح الإعلان | `_openMarketingPreviewProperty` |

**`_openListingByRequestFallback`:** يحاول `properties` بـ `request_id` ثم `_openDetails` مع `marketingRequestId` / `marketingInviteId` / `marketerHubPhase`؛ أو `_openMarketerInviteDetails`.

---

## 5) مكوّنات مشتركة في نفس الملف (أزرار/حوارات)

| الدالة | الغرض |
|--------|--------|
| `_simpleErrorBox` | زر **إعادة المحاولة** → `onRetry` (مثلاً `_loadMineAndOffers`) |
| `_buildStableTabBar` | ترويسة ثابتة + `TabBar` — لا أزرار تنقل برمجية هنا |
| `_showOwnerRequestActivityDialog` | حوار نشاط الطلب (زر إغلاق) |

> توجد دوال إضافية في الملف (تصاريح، عقود، رفع ملفات، إلخ) مرتبطة بالأزرار أعلاه؛ للتفاصيل التنفيذية اتبع الاستدعاء من كل `onPressed`.

---

## 6) من الطلب إلى الرئيسية والسلة (ملخص مسار)

1. **قبل النشر:** العناصر تظهر في تبويبات المالك/المسوّق كصفوف `listing_requests` أو صفوف مدمجة (`_mk*`).
2. **عند اكتمال النشر:** `Property` بمرحلة `published` (أو حالات عامة معتمدة في `ListingPermissionsHelper.shouldShowInPublicHome`).
3. **الرئيسية:** العقارات تُجلب في `user_dashboard` وتُفلتر للعرض العام؛ تُبنى البطاقات في `user_dashboard.widgets` (`_RealEstateCard` / المميز).
4. **السلة:** تظهر زر «إضافة للسلة» فقط إذا `canAddToCart` (منشور، ليس مالكاً، ليس مسوّقاً مرتبطاً، ليس مزاداً، `_showBottomNavCart`) ثم `_addToCart` يستدعي تدفق الحجز.

---

## 7) ملحق — مدفوعات، ضمان، مشرف منصة

| الموضوع | الحالة |
|---------|--------|
| **مشرف المنصة** | `20260444_platform_staff_escrow_checkout_v1.sql`: `users_profiles.platform_staff` أو JWT `app_metadata.platform_staff=true`؛ يدير جلسة المزاد مع المالك/المنشّر. |
| **سجل عربون/ضمان** | `listing_payment_events` + `register_listing_payment_event`؛ في **تفاصيل العقار** (مزاد منشور): تسجيل من مالك/منشّر/مشرف أو «نية عربون مشتري» (لا يشمل المسوّق المختار/المنشّر). |
| **Stripe** | Edge `create_listing_checkout` + سر `STRIPE_SECRET_KEY`. |
| **Moyasar** | تلميح في Edge + الواجهة؛ يكمل لاحقاً بمفتاح سري في الخادم. |
| جلسة مزاد + عدّاد | `20260442` + `20260443`؛ `20260444` يضيف صلاحية المشرف على RPC الجلسة. |
| صور الويب | **CORS** و**bucket** في Supabase |

---

## 8) فهرس سريع لأسطر البداية للدوال الرئيسية (للمطور)

| الدالة | تقريباً سطر البداية (الملف) |
|--------|------------------------------|
| `_buildOwnerMyAds` | ~167 |
| `_buildOwnerReservationsTab` | ~237 |
| `_buildOwnerHubTab` | ~334 |
| `_buildOwnerListingRequestCard` | ~521 |
| `_openOwnerListingRequestFromRow` | ~3312 |
| `_buildOwnerPublishedPropertiesList` | ~3511 |
| `publishedTile` | ~3545 |
| `_buildMarketerMyAds` | ~1140 |
| `_buildMarketerContractingTab` | ~1213 |
| `_buildSimpleRowsList` | ~3719 |
| `_buildMarketerInviteActionsGrid` | ~3790 |
| `_buildMarketerRowCard` | ~3880 |
| `_buildMarketerCardBody` | ~4135 |

*الأرقام قد تتحرك قليلاً مع التعديلات؛ استخدم البحث عن اسم الدالة.*
