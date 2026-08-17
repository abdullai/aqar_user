# إصلاح سير العمل: العروض المنتهية، السوق العقاري، ونشر التصريح (v12)

## الأعراض

- **Postgres 23505** عند «نشر الإعلان»: `listing_permits_unique_request_marketer_active`
- **Postgres 23505** عند «إرسال العرض»: `offers_unique_request_marketer`
- عرض **منتهٍ** يظهر في تبويب «عروضي» للمسوّق
- طلب بعروض منتهية يبقى عند المالك في «بانتظار المسوقين» بدل «العروض المقدمة» + زر إعادة للسوق
- مكتب/شركة لا يرى الطلب في **السوق العقاري** رغم عدم عرض حيّ في الجولة الحالية
- دعوة جولة قديمة تمنع ظهور الطلب في السوق بعد `marketing_round + 1`

## السبب الجذري

1. قيد فريد على `(request_id, marketer_id)` في `listing_offers` يمنع إدراج عرض جديد عند وجود صف `expired`.
2. `submit_listing_offer` كان يعمل `INSERT` دائماً بدل **تحديث** الصف القديم.
3. دعوة جولة سابقة تُحسب كـ «لديه دعوة» فتُستبعد من السوق المفتوح.
4. منطق الواجهة يعتبر أي عرض غير مرفوض «نشطاً» ويخفي السوق/الدعوات.
5. تصريح النشر: `SELECT` قد يفشل بسبب RLS فيُعاد `INSERT` فيصطدم بالفهرس الجزئي الفريد.

## الحل

### قاعدة البيانات (يُشغَّل في Supabase SQL Editor بالترتيب)

1. `supabase/migrations/20260603000000_fix_publish_and_72h_v11.sql` — إن لم يُشغَّل بعد (نشر + 72 ساعة).
2. `supabase/migrations/20260603140000_workflow_offers_permits_root_fix_v12.sql` — **جديد**  
   - إن ظهر `2BP01 cannot drop index offers_unique_request_marketer`: أعد تشغيل الملف **بعد** التحديث (يُسقِط `CONSTRAINT` أولاً).
3. `supabase/migrations/20260603150000_cron_allow_retry_system_bypass.sql` — **مطلوب قبل cron العروض**  
   - يصلح `42501 allow_previous_marketers_retry may only be changed by the listing owner` عند `SELECT cron_expire_pending_offers_72h();`

بعد v12 + v12.1:

```sql
SELECT cron_expire_pending_offers_72h();
SELECT cron_expire_marketer_permit_72h();
```

### التطبيق (Flutter)

- إخفاء العروض `expired` / `withdrawn` من «عروضي»
- تبويب المالك: «العروض المقدمة» + «إعادة للسوق» عند `_owner_offers_need_relist`
- السوق: عدم الحجب إلا بعرض **حيّ** في الجولة الحالية؛ دعوات الجولة القديمة لا تمنع السوق
- نشر التصريح: RPC `upsert_listing_permit_for_publish` + رسائل عربية أوضح

## التحقق اليدوي

| الدور | الإجراء | النتيجة المتوقعة |
|--------|---------|------------------|
| مالك | طلب `2a4bdefc-...` بعروض منتهية | يظهر تحت «العروض المقدمة» + «إعادة للسوق العقاري» |
| مسوّق فرد (قدّم سابقاً) | «عروضي» | لا يظهر العرض المنتهي؛ الطلب في «السوق العقاري» أو دعوة الجولة الحالية |
| مسوّق | إرسال عرض بعد انتهاء | نجاح (تحديث الصف) بدون 23505 |
| مسوّق مختار | نشر REGA | نجاح بدون `listing_permits_unique...` |

**لم يُنشر على Firebase** — طبّق SQL ثم `flutter build web` محلياً عند الجاهزية.
