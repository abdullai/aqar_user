# إصلاحات 2026-06-02 — استجابة لطلب المستخدم

ملف توثيق موجز لكل التغييرات في هذه الجلسة. يربط كل مشكلة برمجية بالحل وملفّاته
وخطوات التحقق.

---

## 1) تكرار بطاقة الإعلان في تبويب «تصريح 72 ساعة» للمسوّق

**السبب الجذري**: حلقة `case 3` داخل `_filterMarketerRowsForTab` كانت تُمرّر كل
صفوف `_mkPermits` بدون إزالة التكرار وفق `request_id` (إنتاج صف ثانٍ بعد النشر
أو من سباق إدخال).

**الحل**:
- `lib/screens/user_dashboard.my_ads_hub.dart` — إضافة `permitReqIds.add(rid)` ثم
  `continue` عند التكرار، مع توسيع نفس المنطق على صفوف العقد.
- ترحيل `supabase/migrations/20260602020000_fix_marketer_publish_stage_and_dedup_permits.sql`:
  - تنظيف الصفوف المكرّرة عبر تعطيلها بـ `status='rejected'`.
  - فهرس فريد جزئي
    `listing_permits_unique_request_marketer_active` على
    `(request_id, marketer_id) WHERE status <> 'rejected'` لمنع التكرار مستقبلاً.

**تحقق**:
```sql
SELECT request_id, marketer_id, count(*)
  FROM public.listing_permits
 WHERE status::text <> 'rejected'
 GROUP BY 1,2
HAVING count(*) > 1; -- يجب أن يعود فارغاً
```

---

## 2) خطأ `invalid_request_stage` عند النشر بعد توقيع العقد

**السبب الجذري**: الـRPC `marketer_finalize_rega_permit_and_publish` كان يقبل فقط
`permit_pending`/`awaiting_permits`/`pending_permits`/`permit_issued`. عند ضغط
«نشر» مباشرةً بعد توقيع العقد ومرحلة `contract_signed` يُرفض الطلب. الـUPDATE
المباشر من العميل (`workflow_stage = 'permit_pending'`) كان يفشل صامتاً بسبب
سياسات RLS التي تمنع المسوّق من تعديل `listing_requests` مباشرة.

**الحل**:
- ترحيل `20260602020000_fix_marketer_publish_stage_and_dedup_permits.sql`:
  - إعادة تعريف `marketer_finalize_rega_permit_and_publish` لتقبل
    `contract_signed` وتنقله أوتوماتيكياً إلى `permit_pending` ثم تعتمد التصريح.
  - إضافة `marketer_set_request_to_permit_pending(p_request_id uuid)` بصلاحية
    `SECURITY DEFINER` لتجاوز RLS (مع فحص `selected_marketer_id = auth.uid()`).
- `lib/screens/user_dashboard.my_ads_hub.dart` — تحديث
  `_ensureRequestPermitStageBeforePublish` ليجرب الـRPC أولاً ثم يسقط على
  UPDATE مباشر كحل احتياطي للنسخ القديمة.

**تحقق**: من حساب المسوّق، بعد توقيع العقد من الطرفين، اضغط «نشر الإعلان
العقاري» → يدخل المرحلة `permit_pending` ثم `permit_issued` ثم `published`،
ولا يظهر الخطأ `invalid_request_stage`.

---

## 3) السياسة الكاملة للاشتراكات (v5)

بعد عودة المستخدم بمتطلب موسّع، اعتُمدت السياسة المحكمة التالية: **باقة واحدة فقط
لكل دور** (وليس ثلاث) مع نظام كامل للحراسة والخصومات.

### خريطة الأدوار → الباقة الوحيدة المرئية:

| الدور | الباقة | السعر شهري | السنوي | المقاعد المدفوعة | خصم المقعد |
|-------|--------|-----------|--------|------------------|------------|
| `marketer` | الأساسية (sort=1) | 99 ر.س | 950.40 | 3 | 50% |
| `office` | الاحترافية (sort=2) | 149 ر.س | 1430.40 | 6 | 50% |
| `institution` | الاحترافية (sort=2) | 149 ر.س | 1430.40 | 9 | 50% |
| `company` | المميّزة (sort=3) | 499 ر.س | 4790.40 | 12 | 50% |
| `individual` | أساسي (sort=1) + 11/12/13 (عروض السوق) | 49 ر.س | 470.40 | — | — |

### الخصومات المُحَوْكمة:

1. **خصم سنوي**: `price_yearly = price_monthly × 12 × 0.80` (مدمج في القيمة).
2. **خصم تفعيل الدفع التلقائي**: 20% لمرّة واحدة على فاتورة الاشتراك الأولى عند
   تشغيل `auto_renew=true` — يُحسب على العميل ويُمرَّر فعلياً لـMoyasar،
   ويُسجَّل في `user_subscriptions.auto_pay_discount_applied=true`.
3. **خصم احتفاظ عند الإلغاء**: 20% لمرّة واحدة لكل **مالك** اشتراك (لا يُعرض
   لأعضاء الفريق). يُحجَز فور عرضه عبر `user_retention_offers_consumed`
   فلا يتكرّر من نوافذ متعدّدة.

### حُرّاس قاعدة البيانات (RPCs):

| RPC | الوظيفة | الملف |
|-----|---------|-------|
| `subscription_quote_for_role(p_period, p_with_auto_pay)` | يُرجع تفاصيل الباقة الوحيدة لدور المستخدم + سعرها بعد خصم الدفع التلقائي. | `20260602050000_*.sql` |
| `subscription_can_subscribe()` | يقرّر «هل يسمح بإنشاء اشتراك؟» — يمنع: أعضاء الفريق + من لديه اشتراك مدفوع فعّال. | — |
| `subscription_compute_upgrade_charge(plan_id, period)` | احتساب فرق الترقية بدقة pro-rata. | — |
| `subscription_offer_cancellation_retention(sub_id)` | إصدار/حجز عرض الاحتفاظ مرّة واحدة. | — |
| `team_member_paid_feature_gate()` | بوابة عضو الفريق: يسمح فقط إذا كان للمالك اشتراك فعّال. | — |

### حماية طبقة DB ضد الاشتراك المكرّر:

```sql
CREATE UNIQUE INDEX user_subscriptions_one_active_paid_per_user
  ON public.user_subscriptions (user_id)
  WHERE status = 'active' AND coalesce(is_trial, false) = false;
```
يمنع وجود **أكثر من اشتراك مدفوع نشط** لكل مستخدم — حتى لو فشل العميل في الفحص.

### تنظيف التكرار في الباقات:

ترحيل `20260602040000_canonical_one_plan_per_role_v5.sql`:
- يُعطّل (`is_active=false`) كل الباقات غير التجريبية.
- يفعّل **صفّاً كانونياً واحداً** فقط لكل (user_type, sort_order) مطلوب — مع
  تفضيل السعر الكانوني، ثم الاسم القياسي، ثم الأحدث.
- يُثبّت أسعار/حدود الكانون على كل صف نشط.
- ينشئ أي صف ناقص.
- يَحفظ كل الصفوف القديمة (FK سليم لـ`user_subscriptions`).

### تعديلات العميل:

- `lib/services/subscription_service.dart`:
  - `allowedSortOrdersForAccountType` → باقة واحدة لكل دور (1 للمسوّق، 2 للمكتب
    والمؤسسة، 3 للشركة، 1+11/12/13 للفردي).
  - `_validateNewSubscriptionEligibility` يبدأ باستدعاء RPC
    `subscription_can_subscribe` (مصدر الحقيقة) ثم يَتحقق محلياً كاحتياط.
  - `subscribeToPlan` يطبّق خصم الدفع التلقائي 20% على المبلغ المُحَصَّل عند
    `autoRenew=true`، ويسجِّل `auto_pay_discount_applied`.
  - دوال جديدة: `teamMemberPaidFeatureGate`، `offerCancellationRetention`،
    `autoPayDiscountPercent`، `computeAmountAfterAutoPayDiscount`.
- `lib/screens/subscriptions/payment_checkout_screen.dart`: يحسب
  `_chargeAmount` بطرح خصم الدفع التلقائي ويعرضه سطراً مخصَّصاً في الفاتورة،
  مع رسالة مخصّصة لخطأ `team_member_not_allowed_to_subscribe`.
- `lib/widgets/subscription_cancel_flow.dart`: يستدعي RPC الخادم لعرض
  «خصم الاحتفاظ» (يَحجزه فوراً) ولا يَعرضه لعضو الفريق.

**تحقق**:
```sql
SELECT user_type, sort_order, name_ar, price_monthly, price_yearly,
       max_members, is_active
  FROM public.subscription_plans
 WHERE coalesce(is_trial_plan,false) = false
   AND is_active = true
 ORDER BY user_type, sort_order;
```
يجب أن تعود **8 صفوف فقط**:
`marketer/1`، `office/2`، `institution/2`، `company/3`، `individual/1`،
`individual/11`، `individual/12`، `individual/13`.

---

## 4) ربط الاشتراك بحساب المستخدم وصلاحياته بعد الدفع

تدفّق الربط في الكود الحالي مكتمل ومُحكم:

| خطوة | المسؤول | المرجع |
|------|--------|--------|
| إنشاء سجل دفع معلّق | `PaymentService.createPendingBillingTransaction` | `lib/services/payment_service.dart:64-101` |
| دفع Moyasar (SDK/Apple Pay/Saved Card) | `MoyasarSubscriptionPaymentScreen` / Edge `moyasar-charge-saved-card` | — |
| تحقق Moyasar السيرفري | webhook `moyasar-webhook` | `supabase/functions/moyasar-webhook/index.ts` |
| تأكيد العميل من نجاح الدفع | `pollUntilBillingTransactionPaid` | `payment_service.dart:187-207` |
| إنشاء/تحديث `user_subscriptions` | `subscribeToPlan` / `renewSubscription` / `upgradePlan` | `subscription_service.dart` |
| فتح صلاحيات الميزات | `resolve_subscription_billing_context` RPC | `migrations/20260530310000_*.sql` |

لا حاجة لتعديلات في هذا التدفّق — الصلاحيات تُقرأ من
`user_subscriptions + users_profiles` تلقائياً.

---

## 5) Moyasar — استخدام مفتاح الربط الحقيقي الحالي

المفتاح في `web/supabase_config.json` هو **`pk_live_…`** بالفعل (مفتاح حقيقي).
ليصبح الربط فعّالاً وقابلاً للاختبار يجب التأكد من المفاتيح السرّية على Supabase
Edge Functions:

```bash
# في طرفية مُسجّلة على Supabase CLI
supabase secrets set \
  MOYASAR_SECRET_KEY=sk_live_<your_secret> \
  MOYASAR_WEBHOOK_SECRET=<webhook_secret_from_moyasar_dashboard> \
  MOYASAR_CALLBACK_URL=https://eaqar-mawthuq.web.app/moyasar-3ds-return

# انشر Edge Functions
supabase functions deploy moyasar-webhook
supabase functions deploy moyasar-charge-saved-card
supabase functions deploy subscription-renew-cron
```

ثم في لوحة Moyasar اضبط webhook URL على:
```
https://czfvqhepsqkgsrfnknwm.supabase.co/functions/v1/moyasar-webhook
```

> ⚠️ سطح المكتب (`flutter run`) يحتاج إضافة `MOYASAR_PUBLISHABLE_KEY=pk_live_…`
> في `.env` داخل جذر المشروع، وإلا يَسلك مسار البطاقة الوهمية.

---

## 6) إخفاء «الخريطة» من الشريط العلوي + خريطة ذكية في البحث المتقدم

**الحل**:
- `lib/screens/user_dashboard.ui.dart` — حذف `_dashboardMapButton(cs)` من شريط
  أدوات `AppBar`. لا تأثير على الرمز/الدالة (تم الإبقاء عليهما لإمكانية إعادة
  الاستخدام).
- إضافة `_openSmartAdvancedSearchMap` في `user_dashboard.actions.dart` تتحسس
  `_tabIndex`:
  - عند `_tabIndex == 1` (تبويب «صفحتي») → خريطة `_openMyPageListingsMap`
    بـ `listingsOnly: true` وإعلانات صفحتي فقط.
  - أي تبويب آخر → `_openMapDiscovery` العامة كما السابق.
- زر «الخريطة» داخل نافذة «البحث المتقدم» يستدعي الدالة الذكية.

**تحقق**: داخل تبويب «صفحتي» اضغط «بحث متقدم → الخريطة»: يفتح خريطة عناصرك
فقط وعنوانها «البحث المتقدم — صفحتي». من تبويب الرئيسية: تفتح خريطة الاكتشاف
العامة.

---

## 7) فلترة المنطقة/المحافظة/المدينة/الأحياء

**السبب**: `_regionFilter`, `_governorateFilter`, `_districtFilter` كانت تُحفظ
في الواجهة لكنّ قواعد الفلترة الفعلية لم تكن تستخدمها (المدينة فقط + مفتاح
البحث).

**الحل**: في `lib/screens/user_dashboard.filters.dart`:
- دالة `_matchesHierarchyFilters(Property p)` للممتلكات.
- دالة `_matchesHierarchyFiltersForRequest` للطلبات.
- استدعاؤهما داخل `applyHomeFiltersToProperties` و
  `filterMarketRequests` و `sortedMineForHub` و مسار fallback.
- `lib/screens/user_dashboard.ui.dart` — `_hasActiveTopFilters` يأخذ بعين
  الاعتبار حقول الهرم الجديدة.

**تحقق**: من نافذة «بحث متقدم → اختيار الموقع» اختر منطقة/محافظة/مدينة/حي. ضغط
«تطبيق» يصفّي القائمة فعلياً وفقاً لكل المستويات، ويُظهر زر «متقدم» نشطاً
(لون مميّز) لتأكيد فعالية الفلتر.

---

## 8) توسعة v6 — نظام الدفع العالمي الجذّاب

### الباقات لكل دور (2-3 خيارات منظّمة):

| الدور | الباقات المرئية |
|------|------|
| `marketer` | تجريبية (٣ أيام) + الأساسية (99 ر.س) + توب-أب طلبات (شهري/سنوي/مرّة) |
| `office` | تجريبية + الاحترافية (149 ر.س، 6 مقاعد) + توب-أب طلبات |
| `institution` | تجريبية + الاحترافية (149 ر.س، 9 مقاعد) + توب-أب طلبات |
| `company` | تجريبية + المميّزة (499 ر.س، 12 مقعد) |
| `individual` | تجريبية + الأساسي (49 ر.س) + عروض السوق (11/12/13) |

### تَوب-أب الطلبات العقارية (sort 21/22/23):

| sort | الاسم | السعر |
|------|------|-------|
| 21 | شهري — 30 طلب/شهر | 39 ر.س |
| 22 | سنوي — 30 طلب/شهر (خصم 20%) | 374.40 ر.س |
| 23 | مرّة واحدة — 10 طلبات | 30 ر.س |

### تشديد أمن الدفع (طبقات متعدّدة):

1. **`validate_payment_intent`** — RPC يُستدعى قبل أي تحصيل، يفحص:
   - **حد المعدّل** (10 محاولات/10 دقائق لكل مستخدم)
   - **أحقيّة الاشتراك** (يَستدعي `subscription_can_subscribe`)
   - **المبلغ الكانوني** (مقارنة المُرسَل بالمحسوب من DB، ±0.05 ر.س)
2. **`payment_security_audit`** — جدول لتسجيل كل محاولة:
   - `subscribe_intent` / `subscribe_ok` / `subscribe_failed` / `rate_limited`
   - `amount_mismatch` / `subscribe_denied` / `card_charge`
3. **`compute_canonical_charge`** — السعر الصحيح من DB لكل سيناريو:
   - شهري/سنوي/مرّة واحدة
   - مع/بدون خصم الدفع التلقائي
   - مع/بدون فرق ترقية pro-rata

### بانر التجريبية الجذّاب:

- بطاقة منفصلة في أعلى شاشة الباقات
- متاحة الآن للأدوار التسويقية **والفرد** (بعد توسعة v6)
- زر «تفعيل التجربة 3 أيام» بشارة هدية
- مرّة واحدة لكل مستخدم (محمي عبر `user_trial_subscriptions_used`)

### تحديثات `SubscriptionService`:

| الدالة | الوظيفة |
|-------|--------|
| `validatePaymentIntent` | تحقّق ثلاثي قبل التحصيل |
| `recordPaymentOutcome` | تسجيل نتيجة الدفع في سجل المراجعة |
| `isListingRequestsTopUpSortOrder` | تمييز توب-أب 21/22/23 |
| `isMarketOffersTopUpSortOrder` | تمييز توب-أب 11/12/13 |
| `autoPayDiscountPercent` | قراءة نسبة 20% من الخطة |
| `computeAmountAfterAutoPayDiscount` | السعر بعد خصم التلقائي |
| `teamMemberPaidFeatureGate` | بوابة عضو الفريق |
| `offerCancellationRetention` | عرض الاحتفاظ مرّة واحدة |

### ترتيب تشغيل الترحيلات (v5 → v7):

```
1) 20260602020000_fix_marketer_publish_stage_and_dedup_permits.sql
2) 20260602040000_canonical_one_plan_per_role_v5.sql
3) 20260602050000_subscription_lifecycle_guards_v5.sql
4) 20260602060000_plans_visibility_for_subscribers.sql
5) 20260602070000_world_class_payment_addons_v6.sql
6) 20260602080000_payment_security_hardening_v6.sql
7) 20260602090000_topup_lifecycle_and_listing_quota_v7.sql      ← جديد ومهم
```

### إصلاحات v7 (الثلاث ثغرات الحرجة):

#### (A) دورة حياة Top-up — `is_topup` + إعادة بناء الفهرس الفريد

كانت v5 تَفرض «اشتراك مدفوع نشط واحد لكل user_id». هذا يَكسر شراء توب-أب
الطلبات/العروض. الإصلاح:

```sql
ALTER TABLE user_subscriptions ADD COLUMN is_topup boolean NOT NULL DEFAULT false;
-- Trigger يَضبطه تلقائياً من plan.sort_order ∈ (11,12,13,21,22,23)

DROP INDEX user_subscriptions_one_active_paid_per_user;
CREATE UNIQUE INDEX user_subscriptions_one_main_paid_per_user
  ON user_subscriptions (user_id)
  WHERE status = 'active'
    AND coalesce(is_trial, false) = false
    AND is_topup = false;
```

#### (B) `subscription_can_subscribe(p_target_plan_id)`

أصبح يقبل `plan_id` ليُميّز:
- إن كانت top-up + لديه رئيسية فعّالة → `can_subscribe = true`
- إن كانت top-up + لا رئيسية → `topup_requires_main_subscription`
- إن كانت رئيسية + لديه رئيسية → `already_active_subscription` (الترقية فقط)

#### (C) `listing_requests_unified_allowance` RPC

دالة موحَّدة (مماثلة لـ `market_offer_unified_allowance`) تَحسب:
- الحصة الأساسية من الباقة الرئيسية (max_listing_requests)
- + Top-ups من sort 21/22/23 النشطة
- - الاستهلاك من `market_property_requests` (status IN published, draft)
- = `total_remaining` و `needs_paywall`

#### (D) تفعيل التجريبية لجميع الأدوار التسويقية + الفرد

الترحيل v7 يَضمن:
- `is_active = true` لكل خطة `is_trial_plan = true`
- إنشاء أي خطة تجريبية ناقصة (مع 3 أيام، 1 إعلان، إعدادات معقولة)

### تعديلات Dart المرافقة:

- `subscribeToPlan` يَستدعي `subscription_can_subscribe` بمَعامل `p_target_plan_id` ويَتجاوز الفحوص المحلية إذا كانت الباقة top-up.
- `payment_checkout_screen` يَعرض رسالة واضحة لـ `topup_requires_main_subscription`.

### تحقق نهائي:

```sql
SELECT user_type, sort_order, is_trial_plan, name_ar, price_monthly, is_active
  FROM public.subscription_plans
 WHERE is_active = true
 ORDER BY user_type, is_trial_plan DESC, sort_order;
```

يجب أن ترى **22 صفاً** نشطاً موزّعة:
- `marketer`: تجريبية + 1 + 21/22/23 = 5 صفوف
- `office`: تجريبية + 2 + 21/22/23 = 5 صفوف
- `institution`: تجريبية + 2 + 21/22/23 = 5 صفوف
- `company`: تجريبية + 3 = 2 صفوف
- `individual`: تجريبية + 1 + 11/12/13 = 5 صفوف

### ضمانات أمنية ضد الاختراق:

- ✅ المبلغ يُحسب على الخادم (المستخدم لا يَستطيع تخفيضه)
- ✅ حد معدّل 10 محاولات/10 دقائق (يَمنع Brute Force)
- ✅ سجل مراجعة كامل لكل محاولة (تتبع جنائي)
- ✅ فهرس فريد على `user_subscriptions` (يَمنع الاشتراك المكرّر)
- ✅ RLS صارم على `subscription_plans` (المشترك يَرى باقته فقط إن عُطّلت)
- ✅ `SECURITY DEFINER` مع فحوص مالكية صريحة
- ✅ `auto_pay_discount_percent` يُقرأ من DB (لا يُرسَل من العميل)
- ✅ Moyasar webhook يَتحقق من Signature قبل تأكيد الدفع
