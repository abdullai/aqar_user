# Migration policy

## Official migrations

All SQL files in this directory are ordered by filename timestamp and are
applied by Supabase in that order. Do not edit an already-applied migration;
add a new corrective migration instead.

## Development-only migrations

The following naming markers identify local or staging helpers:

- `dev_test`
- `dev_grant`
- `grant_test`
- `reset_`
- `debug`

These files may create test subscriptions, grant test access, reset billing
state, or expose diagnostic data. They must not be included in a production
database history unless the exact effect has been reviewed and approved.

Because Supabase migration history is append-only, an already-applied test
migration cannot be made safe by deleting the file later. Use a clean staging
project to validate the intended production migration sequence.

## Release checklist

1. Export the migration list for the target environment.
2. Review every development-only migration and remove it from the production
   release plan before the first production migration is applied.
3. Run the RLS validation SQL under `supabase/sql/staging_validation`.
4. Verify payment, subscription, storage, notification, and webhook flows with
   non-production credentials.