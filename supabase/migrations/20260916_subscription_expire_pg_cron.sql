-- جدولة انتهاء الاشتراك والفواتير المعلقة عبر pg_cron إن وُجد.
-- لا يمدّد اشتراكاً. لا يحصّل مالاً. فقط lifecycle خادمي.

BEGIN;

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.unschedule('subscription_expire_due_hourly');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'subscription_expire_due_hourly',
    '15 * * * *',
    $job$SELECT public.subscription_expire_due();$job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron not enabled on this project: %', SQLERRM;
END $$;

COMMIT;
