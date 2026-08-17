# تقرير امتثال المدفوعات والاشتراكات — Payment Compliance

**الجهة:** موثوق الإلكترونية — **المنتج:** المنصة العقارية الموثوقة  
**التاريخ:** 2026-05-14 — **يعتمد على الترحيلات الفعلية فقط**

---

## تأكيد القيود (إلزامي)

وثيقة تدقيق؛ لا تغيير منطق إنتاج.

---

## 1) ما هو منفّذ في المستودع (PostgreSQL / Supabase)

**المصدر الرئيسي:** `supabase/migrations/20260503120000_subscriptions_payments_billing.sql`

يشمل (غير حصرٍ): جداول مثل **`subscription_plans`**, **`user_subscriptions`**, **`billing_transactions`** مع **RLS** مفعّل وفق الترحيل.

**ترحيل مرتبط:** `20260503150000_billing_audit_promotions_staff_read.sql` (عروض/استردادات ترويجية ضمن نطاق الترحيل).

---

## 2) عدم وجود `regc_subscription_transactions` / `regc_payment_refunds`

طبقة **`regc_*` الحالية** لا تتضمن هذين الجدولين — **لا يُذكران كمنفّذ** في الشهادة.

---

## 3) محاذاة PCI-DSS (تصميم — design only)

- **عدم تخزين بيانات بطاقة خام** في النموذج المرجعي؛ الاعتماد على **رمز/توكن** عبر بوابة (mock أو حقيقية حسب إعداد المشغّل).  
- تفصيل التطبيق في كود الخدمات (`lib/services/payment_*`, `payment_gateway_mock` إن وُجد).

---

## 4) الفواتير والاسترداد

- يخضع لتطور المنتج والبوابة؛ الوثيقة تصف **الوجود المخطط في الترحيلات** وليس كل سيناريو تجاري دون مراجعة كود التطبيق لكل مسار.

---

## 5) التدقيق الامتثالي للمدفوعات عبر `regc_audit_logs`

يمكن توسيع `event_type` عبر RPC التدقيق لتسجيل أحداث دفع حرجة **عند ربطها في التطبيق** — الوضع الحالي يغطي الأحداث المعرّفة في مسارات الامتثال القانوني/الموافقات.

---

## 6) تحديث 2026-05-15 — اشتراك دقيق وتجديد تلقائي

- **`user_subscriptions`:** أعمدة `starts_at` / `ends_at` (UTC، حدّ علوي حصري) + حقول فشل التجديد التلقائي — ترحيل `20260516140000_user_subscriptions_instants_renewal_fail.sql`.
- **`billing_transactions`:** عمود `renewal_extension_applied_at` + RPC **`subscription_apply_auto_renew_extension`** — ترحيل `20260516150000_subscription_auto_renew_extension_rpc.sql`.
- **Edge:** `moyasar-webhook` يوسّع الاشتراك عند `purpose=auto_renew` أو `payment_method=card_auto_renew`؛ دالة **`subscription-renew-cron`** للمحاولة المجدولة.

**مقابل قائمة الطلب (قسم 11):** ما زال ينقص غالباً: `payment_reference_number`, `invoice_number`, `refund_reference` كأعمدة مخصصة — يمكن الاكتفاء مؤقتاً بـ `gateway_response` jsonb أو إضافتها في هجرة لاحقة nullable.

**نهاية التقرير.**
