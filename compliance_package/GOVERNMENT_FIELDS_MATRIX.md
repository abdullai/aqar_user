# مصفوفة الحقول الحكومية — Government Fields Matrix

**الغرض:** مطابقة الحقول المطلوبة في الطلب مع **ما يظهر في المستودع** (ترحيلات + سكربتات SQL + كود التطبيق).  
**رمز:** ✅ موجود في ترحيل/كود واضح | ⚠️ جزئي / اسم مختلف / JSON | ❌ غير مثبت كعمود مخصص في الترحيلات المراجعة | 🔜 يُنصح به بعد العقد

---

## A) الأفراد (Individuals)

| الحقل المطلوب | الحالة | ملاحظة تقنية |
|----------------|--------|----------------|
| national_id | ⚠️ | غالباً `username` أو مسار `national_id` إن وُجد عمود (يُذكر في `signup_username_taken`) |
| national_id_expiry | ❌ | — |
| date_of_birth | ❌ | — |
| nafath_verified | ❌ | تتبع جلسة في `nafath_logins` وليس عموداً صريحاً على الملف |
| nafath_verified_at | ❌ | — |
| nafath_last_sync | ❌ | — |
| citizenship | ❌ | — |
| gender | ❌ | — |
| legal_full_name_ar | ⚠️ | `full_name_ar` / `full_name` في التشخيصات |
| legal_full_name_en | ⚠️ | إن وُجدت أعمدة اسم إنجليزي في المخطط الفعلي للإنتاج |
| iqama_number | ❌ | — |
| iqama_expiry | ❌ | — |
| user_status | ⚠️ | أقرب شيء: أعلام/حظر منصة في `platform_bans` + `verification_status` |
| verification_status | ✅ | في `handle_new_user` والامتثال |

---

## B) المسوّقون العقاريون

| الحقل | الحالة | ملاحظة |
|-------|--------|---------|
| fal_license_number | ⚠️ | `license_no` على الملف |
| fal_license_type | ❌ | — |
| fal_license_issue_date | ❌ | — |
| fal_license_expiry_date | ⚠️ | `fal_license_expires_at` (timestamptz) |
| fal_license_status | ⚠️ | مُستنتج من التاريخ + `fal_compliance_hold` |
| fal_last_verification_at | ❌ | — |
| rega_marketer_id | ❌ | — |
| rega_verified | ❌ | — |
| rega_verified_at | ❌ | — |

---

## C) مكاتب / شركات / مؤسسات

| الحقل | الحالة | ملاحظة |
|-------|--------|---------|
| commercial_registration_number | ⚠️ | قد يكون داخل JSON أو حقول أخرى — راجع مخطط `org_units` الفعلي |
| commercial_registration_expiry | ❌ | — |
| commercial_name_ar / en | ⚠️ | `display_name_ar` / `display_name_en` في `org_units` |
| establishment_type | ⚠️ | `account_type` على `org_units` |
| unified_number | ❌ | — |
| vat_number | ❌ | — |
| municipality_license_* | ❌ | — |
| chamber_of_commerce_* | ❌ | — |
| company_national_address | ⚠️ | `address_ar` / `address_en` |
| company_email / phone | ⚠️ | `org_public_email` / `org_public_phone` |
| responsible_manager_* | ❌ | — |

---

## D) الصكوك وناجز (على مستوى العقار/المالك)

| الحقل | الحالة | ملاحظة |
|-------|--------|---------|
| property_deed_number | ⚠️ | مسارات صك في سكربتات عقار (راجع `properties` والسكربتات) |
| deed_issue_date / expiry / status | ⚠️ | حسب أعمدة العقار الفعلية في الإنتاج |
| najiz_reference_id | ❌ | — |
| najiz_verified / najiz_verified_at | ❌ | — |
| property_owner_national_id / name | ⚠️ | عبر `owner_id` → `users_profiles` |
| property_verification_status | ⚠️ | منطق نشر/RLS وليس حقل واحد موحّد بكل الأحيان |

---

## E) المدفوعات (مقابل القسم 11 في الطلب)

| الحقل | الحالة | ملاحظة |
|-------|--------|---------|
| payment_reference_number | ❌ | — |
| gateway_transaction_id | ✅ | `billing_transactions.gateway_transaction_id` |
| refund_reference | ⚠️ | حالة `refunded` + `gateway_response` — لا عمود مخصص |
| invoice_number | ❌ | — |
| tax_invoice_url | ⚠️ | `invoice_url` |
| subscription_status / expiry | ✅ | `user_subscriptions` + `starts_at`/`ends_at` |
| auto_renewal_status | ⚠️ | `auto_renew` + أعمدة فشل التجديد |
| failed_payment_reason | ⚠️ | `auto_renew_last_failure_reason` على الاشتراك؛ تفاصيل الدفع في `gateway_response` |

---

## الخلاصة

المشروع **جاهز كطبقة تشغيل وتجارة** مع **امتثال قانوني أساسي (`regc_*`)** و**هوية تشغيلية جزئية**.  
الحقول المفصّلة في الطلب (نفاذ، ناجز، سجل تجاري كامل، مدير مسؤول، إلخ) تحتاج **حزمة هجرات مقصودة** بعد مواصفات الجهات — انظر `FINAL_GOVERNMENT_READINESS.md` لقائمة الهجرات المقترحة **دون تنفيذ**.

**نهاية المصفوفة.**
