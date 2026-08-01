# Performance Report (baseline & methodology)

## Flutter Web

| Check | Tool | Target (indicative) |
|-------|------|----------------------|
| First load | Lighthouse | LCP < 4s on 4G (tune per market) |
| Bundle size | `flutter build web --analyze-size` | Track regressions |
| Maps cost | Network panel | Lazy-init maps routes |

## Mobile

- Profile scrolling on `UserDashboard` with DevTools / Systrace.
- Image caching: `cached_network_image` already in use — verify memory caps on low-RAM devices.

## API / Supabase

- Measure RPC latency for hot paths (`get_app_audience_stats`, auth) from staging.
- Add indexes when `EXPLAIN (ANALYZE)` shows seq scans on large tables — see `DATABASE_OPTIMIZATION_REPORT.md`.

## Realtime

- Subscribe only while screen visible; unsubscribe on dispose (audit chat/list screens).

## Status

Automated perf suite: **not** wired in repo — add CI step when template chosen.
