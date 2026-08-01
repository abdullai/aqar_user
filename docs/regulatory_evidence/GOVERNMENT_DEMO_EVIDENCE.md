# GOVERNMENT_DEMO_EVIDENCE

## Architectural summary

Government integrations (REGA, Nafath) are **not** activated by default. A **boolean demo flag** is read from environment at runtime for **isolated demo builds** only.

## Configuration (no production impact when off)

```dart
// lib/core/compliance/platform_compliance_config.dart
static bool governmentDemoMode() {
  // GOVERNMENT_DEMO_MODE or COMPLIANCE_DEMO_GOV_MODE — 1/true/yes/on
}
```

```properties
# assets/env/default.env (commented template)
# GOVERNMENT_DEMO_MODE=1
# COMPLIANCE_DEMO_GOV_MODE=1
```

## Demo data

Optional commented seed: `supabase/sql/demo_government_seed_optional.sql` — **demo database only**.

## Evidence for auditors

- Screenshot of **production** build env showing both flags unset or `0`.  
- Separate Supabase project ID for demo walkthrough.

**Validator:** `supabase/sql/staging_validation/validate_government_demo_mode.sql`
