# Print / PDF-ready policies — operator guide

## Source of truth

- Arabic/English markdown: `docs/compliance/PRIVACY_POLICY_AR.md` (and siblings).  
- Version string: align with `regc_legal_policy_documents.version` and `legal_documents_versions.version` (e.g. `2026-04-05-SA`).

## Recommended PDF pipeline

1. **Pandoc** (or internal CMS) with a corporate LaTeX/Word template.  
2. Inject metadata on each build:

```yaml
---
title: "Privacy Policy"
lang: ar
version: "2026-04-05-SA"
effective_date: "2026-05-01"
footer: "Mawthuq Line Real Estate Establishment — Confidential draft"
signature_placeholder: true
---
```

3. **Header/footer:** use template includes for logo, CR number, page `x / n`.  
4. **Electronic seal / signature:** image placeholders in template — replace after legal sign-off.

## Bilingual bundle

- Generate **two PDFs** per release (AR + EN) or one bilingual PDF if counsel approves layout.

## Storage

- Store signed PDFs **outside** the mobile app bundle; link from operator portal or static CDN with access control.

## Web print (user)

Optional: add `/print/privacy` route in a **future** web-only admin/marketing site — **not** required inside consumer app shell.
