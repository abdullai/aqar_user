# تصميم التكامل مع الهيئة العامة للعقار — REGA Integration Design

**الجهة:** موثوق الإلكترونية — **المنتج:** المنصة العقارية الموثوقة  
**التاريخ:** 2026-05-14  
**النوع:** تصميم ومسار ربط — **documentation only**

---

## تأكيد القيود (إلزامي)

NO UI / NO SCHEMA تغيير ضمن هذه الوثيقة.

---

## 1) الهدف

ربط إعلانات/تصاريح/حالات العمل وفق واجهات **REGA** المعتمدة للكيان المرخص.

---

## 2) طبقة التكامل المقترحة

```text
[App] → [API Gateway / Edge] → [REGA APIs] → callbacks موقّعة
          ↓
     [Postgres RLS] — بيانات المنصة لا تُعرَّض إلا بسياسات
```

---

## 3) مراجع المستودع

- `docs/government_submission/REGA_READINESS.md`  
- `docs/WORKFLOW_FCM_AND_REGA.md` (إن وُجد لسير العمل)

---

## 4) الجاهزية

راجع `INTEGRATION_READINESS_REPORT.md`.

**نهاية التصميم.**
