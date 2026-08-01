-- Platform staff: read subscription lifecycle events (monitoring / finance desk).

DROP POLICY IF EXISTS subscription_lifecycle_events_staff_read
  ON public.subscription_lifecycle_events;
CREATE POLICY subscription_lifecycle_events_staff_read
  ON public.subscription_lifecycle_events
  FOR SELECT TO authenticated
  USING (public.is_platform_staff(auth.uid()));
