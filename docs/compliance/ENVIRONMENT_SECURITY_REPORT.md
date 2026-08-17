# Environment & Secrets Security Report

## Principles

1. **Never** commit `service_role` or production anon keys.  
2. Use **CI variables** + sealed secrets manager for builds.  
3. Separate Supabase projects per environment to blast-radius containment.

## Flutter / Dart defines

Prefer:

```bash
flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

## Web

- `web/supabase_config.json` pattern for anon key on web (see repo docs / example files).
- Avoid logging full URLs with embedded tokens.

## Leakage validation (manual)

- [ ] `git grep -i secret` / `api_key` / `service_role` on clean branch  
- [ ] Scan CI logs for printed env  
- [ ] Verify `.gitignore` covers `.env`, keystores, `google-services.json` if applicable

## Google Maps key

Current browser key is in source — **restrict by HTTP referrer** in Google Cloud Console before production traffic.

## Government demo mode

Optional flag `GOVERNMENT_DEMO_MODE` (see `PlatformComplianceConfig.governmentDemoMode`) — **false** in production builds unless running an isolated demo stack.
