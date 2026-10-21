-- تفعيل pg_cron (إن سمحت الصلاحيات) وجدولة تذكير المعاينة كل 15 دقيقة.
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron enable skipped: %', SQLERRM;
  END;

  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.unschedule('aqar_viewing_reminders');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    PERFORM cron.schedule(
      'aqar_viewing_reminders',
      '*/15 * * * *',
      'SELECT public._viewing_send_reminders(NULL)'
    );
  END IF;
END;
$$;

SELECT CASE
  WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    THEN 'pg_cron ACTIVE'
  ELSE 'pg_cron NOT available - enable in Dashboard > Database > Extensions'
END AS cron_status;
