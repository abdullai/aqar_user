# 2026-06-02 — أتمتة وحوكمة دورة حياة العرض/التصريح/العقد + تحسين الأداء (v8)

## ملخّص تنفيذي

تَطلب المستخدم نظاماً مُحكَماً لِأتمتة سير عمل المسوّق والمالك:

1. **«إشعار آخر» (Last Call) — 48 ساعة**: إن لم يَردّ المالك على عرض المسوّق
   خلال 48 ساعة، يَظهر زر «إشعار آخر» يُرسل إشعاراً صوتياً للمالك ويُجدّد
   العرض. الزر يَختفي إن اختار المالك مسوّقاً آخر.

2. **أتمتة 72 ساعة للتصاريح**: إن انتهت مهلة 72 ساعة على المسوّق دون رفع
   التصريح، تُحوَّل البطاقة آلياً إلى تبويب «لم يُتَّخذ إجراء» للمالك
   وتختفي تماماً من قائمة المسوّق.

3. **أتمتة 72 ساعة للعقود**: إن وُقِّع العقد ولم يُتابَع خلال 72 ساعة، يَفسخ
   النظام العقد آلياً، ويُلصق نصاً قانونياً تهميشياً على العقد الأصلي.

4. **«إعادة للسوق»**: زر للمالك في تبويب «لم يُتَّخذ إجراء» يَفتح نافذة بخيار
   «السماح للمسوّق السابق بالعودة (تشغيل/إيقاف)» قبل إعادة الطلب للسوق.

5. **إخفاء العروض الخاسرة**: بعد اختيار المالك مسوّقاً، تُعلَّم بقية العروض
   `lost` وتختفي من قوائم المسوّقين الآخرين.

6. **تحميل فوري**: ذاكرة كاش في الجلسة لِبطاقات «صفحتي» تَجعل التنقل بين
   التبويبات لحظياً (stale-while-revalidate).

---

## التغييرات على قاعدة البيانات

### الترحيل: `supabase/migrations/20260602110000_marketing_workflow_automation_v8.sql`

#### أعمدة جديدة على `listing_offers`
- `last_call_count int NOT NULL DEFAULT 0`
- `last_call_at timestamptz`
- `lost_at timestamptz`
- `lost_reason text`

#### أعمدة جديدة على `listing_requests`
- `owner_action_required_at timestamptz`
- `owner_action_reason text`
- `contract_deadline_at timestamptz`
- `prev_selected_marketer_id uuid` (لاستثناء المسوّق السابق)
- `auto_expired_at timestamptz`

#### الدوال (RPCs):

| الدالة | الوصف | الصلاحية |
|---|---|---|
| `marketer_send_offer_last_call(p_offer_id)` | يُرسل إشعار صوتي للمالك ويُجدّد العرض 48h | مسوّق صاحب العرض |
| `marketer_can_send_last_call(p_offer_id)` | فحص الصلاحية (لإظهار الزر في الواجهة) | مسوّق صاحب العرض |
| `cron_expire_marketer_permit_72h()` | تَنقل التصاريح المنتهية إلى `owner_action_required` | service_role/cron |
| `cron_expire_marketer_contract_72h()` | فسخ العقود غير الموقَّعة بعد 72h + بصمة قانونية | service_role/cron |
| `cron_run_72h_workflow_expirations()` | مُجمِّع — يُستدعى من Edge Function/pg_cron | service_role/cron |
| `owner_return_request_to_market(p_request_id, p_allow_same_marketer)` | المالك يُعيد الطلب للسوق + خيار استثناء المسوّق السابق | المالك |
| `_mark_losing_offers_for_request(p_request_id)` | يُعلِّم العروض الخاسرة لجميع المسوّقين غير المختار | داخلي |

#### Trigger:
- `tr_listing_requests_mark_losing` — عند ضبط `selected_marketer_id`، يُعلِّم
  العروض الأخرى تلقائياً بـ`status='rejected'` و`lost_at=now()`.

#### View:
- `v_marketer_visible_offers` — لاحقاً عند الحاجة، يَستثني العروض `lost`
  للمسوّق غير المختار.

---

## التغييرات على Flutter

### ملف جديد: `lib/services/marketing_workflow_automation_service.dart`

خدمة موحَّدة تُغلِّف الـRPCs الجديدة:
- `canSendLastCall(offerId)` / `sendLastCall(offerId)`
- `returnRequestToMarket(requestId, allowSameMarketer)`
- `runExpirations()` — للاختبار اليدوي

### ملف جديد: `lib/services/marketing_buckets_cache.dart`

كاش ذاكرة Singleton لِتبويبات «صفحتي»:
- `saveMarketer(...)` / `readMarketer(uid)` — حفظ/استرجاع
  `_mkInvites/_mkOffers/_mkContracts/_mkPermits/_mkPublished`.
- `saveOwner(...)` / `readOwner(uid)` — `_ownerListingRequests`.
- `clearAll()` — يُستدعى عند تسجيل الخروج.

### تعديلات `lib/screens/user_dashboard.my_ads_hub.dart`

- **زر «إشعار آخر للمالك»** في تبويب «عروضي» بعد زر «تتبع عرضي».
- **زر «إعادة للسوق»** للمالك في تبويب «لم يُتَّخذ إجراء» يَفتح نافذة
  بخيار «السماح للمسوّق السابق».
- دالتان مساعدتان: `_marketerCanShowLastCallButton(r)` و
  `_ownerRowAwaitsReturnToMarket(r)`.
- معالجان: `_marketerSendOfferLastCall(r)` و `_ownerReturnRequestToMarket(r)`.

### تعديلات `lib/screens/user_dashboard.marketing_loaders.dart`

- استرجاع فوري من الكاش قبل ضرب الشبكة (في `_loadMarketerBuckets` و
  `_loadOwnerRequestsBuckets`).
- حفظ النسخة الناجحة في الكاش بعد التحميل.
- توسعة `_marketerOfferExcludedFromOffersList` لِإخفاء:
  - العروض المُعلَّمة `lost`.
  - الطلبات في `owner_action_required` (تَختفي تماماً من قوائم المسوّقين).

### تعديلات `lib/services/in_app_notification_hub.dart`

- تشغيل نغمة `permitWarning` عند وصول إشعار `last_call`/`expired_72h`
  بدلاً من النغمة الافتراضية.

### تعديلات `lib/core/workflow/listing_workflow_stage.dart`

- `workflow_stage='owner_action_required'` يُترجَم إلى
  `ListingWorkflowStage.inactive72h` ليَظهر في تبويب «لم يُتَّخذ إجراء».

### تعديلات `lib/core/auth/safe_sign_out_service.dart`

- استدعاء `MarketingBucketsCache.instance.clearAll()` عند تسجيل الخروج.

---

## Edge Function للجدولة

### ملف جديد: `supabase/functions/workflow-72h-cron/index.ts`

Edge Function تَستدعي `cron_run_72h_workflow_expirations()` كل 10 دقائق.

#### إعدادات النشر:

```bash
# 1. ضع المتغيّرات السرّية
supabase secrets set WORKFLOW_CRON_SECRET="<random-string-≥-32-chars>"

# 2. انشر الدالة
supabase functions deploy workflow-72h-cron --no-verify-jwt

# 3. جدولها كل 10 دقائق من Supabase Dashboard:
#    Edge Functions → workflow-72h-cron → Schedules → Add
#    Cron expression: */10 * * * *
#    Headers: x-workflow-cron-secret: <نفس القيمة أعلاه>
```

#### بديل عبر pg_cron (إن أردت كل شيء داخل DB):

```sql
SELECT cron.schedule(
  'workflow-expirations-72h',
  '*/10 * * * *',
  $$ SELECT public.cron_run_72h_workflow_expirations(); $$
);
```

---

## خطوات الاختبار اليدوي

### 1) زر «إشعار آخر»
1. أرسل عرضاً كمسوّق على طلب لمالك.
2. لا تَقبل العرض من المالك — اضبط `created_at` يدوياً للخلف 49 ساعة:
   ```sql
   UPDATE listing_offers SET created_at = now() - interval '49 hours'
   WHERE id = '<OFFER_ID>';
   ```
3. ادخل تبويب «صفحتي → عروضي» للمسوّق → يَظهر زر «إشعار آخر للمالك».
4. اضغطه → يَصل إشعار صوتي للمالك + يَتجدّد `expires_at` 48h جديدة.
5. حاول الضغط مرة أخرى → يَظهر «مهلة إشعار آخر فعّالة».

### 2) أتمتة 72 ساعة للتصاريح
1. اقبل عرضاً ووقِّع العقد لتصل لِمرحلة `permit_pending`.
2. اضبط `permit_deadline_at` للماضي:
   ```sql
   UPDATE listing_requests SET permit_deadline_at = now() - interval '1 hour'
   WHERE id = '<REQUEST_ID>';
   ```
3. شَغِّل الدالة يدوياً:
   ```sql
   SELECT public.cron_run_72h_workflow_expirations();
   ```
4. تَختفي البطاقة من تبويب «التصريح 72 ساعة» للمسوّق.
5. تَظهر في تبويب «لم يُتَّخذ إجراء» للمالك مع زر «إعادة للسوق».

### 3) إعادة للسوق
1. من بطاقة المالك في «لم يُتَّخذ إجراء»، اضغط «إعادة للسوق».
2. تُفتح نافذة بـ Switch «السماح للمسوّق السابق بالعودة».
3. اضغط «إعادة للسوق» → الطلب يَعود لِ`waiting_marketers` بدورة جديدة.
4. إن أَوقفت الـSwitch، يَتم إنشاء صف في
   `listing_request_marketer_exclusions` يَستثني المسوّق السابق.

### 4) فسخ العقد التلقائي 72h
1. وَقِّع عقداً واتركه:
   ```sql
   UPDATE listing_requests SET contract_sent_at = now() - interval '73 hours'
   WHERE id = '<REQUEST_ID>' AND contract_signed_at IS NULL;
   ```
2. شَغِّل `cron_run_72h_workflow_expirations()`.
3. عقد يُحوَّل إلى `status='cancelled'`، تُلصق ملاحظة قانونية في
   `extra_margin_notes`، الطلب يَدخل `owner_action_required`.

### 5) إخفاء العروض الخاسرة
1. كمالك، اقبل عرض المسوّق A على طلب فيه عروض من B وC.
2. تَلقائياً (Trigger): عروض B وC تَصير `status='rejected'` و`lost_at=now()`.
3. كمسوّق B أو C: ادخل «عروضي» → البطاقة لن تَظهر.

### 6) تحسين الأداء
1. دخول «صفحتي» للمرة الأولى يَجلب من قاعدة البيانات (كالعادة).
2. اخرج للرئيسية أو لتبويب آخر، ثم عُد إلى «صفحتي».
3. البطاقات تَظهر **فوراً** من الكاش، ثم تُحدَّث في الخلفية.
4. عند تسجيل الخروج، يُمسح الكاش.

---

## ملاحظات أمنيّة

- جميع الـRPCs تَفحص `auth.uid()` وتَتأكّد من ملكيّة العرض/الطلب.
- `marketer_send_offer_last_call` يَتحقق:
  - المُستدعِي هو مالك العرض.
  - المالك لم يَختر مسوّقاً آخر.
  - مرّ ≥ 48 ساعة على آخر إشعار.
- `owner_return_request_to_market` يَتحقق:
  - المُستدعِي هو مالك الطلب.
  - الطلب فعلاً في `owner_action_required`.
- `cron_*` تَعمل بـ`SECURITY DEFINER` بدون `auth.uid()` (للـ service_role).

---

## ما تَبقى (اختياريّ)

- ربط زر «طلبات» في النشر مع `listing_requests_unified_allowance` لِمنع
  تجاوز الكوتا في الواجهة (في صفحة إنشاء الطلب).
- إضافة widget «عدّ تنازلي» على بطاقة العرض لِعرض الوقت المتبقّي حتى
  تَفعيل زر «إشعار آخر».
- ربط نظام push notifications (FCM/APNs) لِإرسال إشعار `last_call`
  حتى للمالكين خارج التطبيق.
