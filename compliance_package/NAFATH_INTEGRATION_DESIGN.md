# تصميم التكامل مع النفاذ الوطني — NAFATH Integration Design

**الجهة:** موثوق الإلكترونية — **المنتج:** المنصة العقارية الموثوقة  
**التاريخ:** 2026-05-14  
**النوع:** تصميم ومسار ربط — **لا تنفيذ إنتاجي ضمن هذه الوثيقة**

---

## تأكيد القيود (إلزامي)

NO UI CHANGES — DOCUMENTATION ONLY.

---

## 1) الهدف

تمكين مصادقة هوية وطنية موحّدة عبر **NAFATH** وفق برامج الجهة (OIDC/SAML حسب ما تعتمده الهيئة في وقت الربط).

---

## 2) النموذج المقترح (OIDC — design)

```text
[Mobile/Web App] → [Authorization Server / NAFATH] → redirect + code
       ↓
[Backend / Edge] → token exchange + user mapping → Supabase session / JWT
```

---

## 3) الربط مع النظام الحالي

- المصادقة الحالية: **Supabase Auth + JWT**.  
- مسار الدمج: إما **ربط IdP خارجي** مع Supabase أو **تبادل رمز** عبر Edge Function موثّق — يُقرَّر عند اعتماد المشغّل.

---

## 4) مراجع المستودع

- `docs/government_submission/NAFATH_INTEGRATION.md`  
- `lib/core/compliance/platform_compliance_config.dart` — روابط عامة قابلة للتهيئة

---

## 5) الجاهزية

راجع النسب في `INTEGRATION_READINESS_REPORT.md`.

**نهاية التصميم.**
