-- Push handoff for workflow/in-app notifications.
-- The mobile/web app already writes `in_app_notifications` and stores FCM tokens in
-- `user_push_tokens`; this outbox gives an Edge Function a durable queue to send
-- system push notifications without coupling app writes directly to FCM.

create table if not exists public.push_notification_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid references public.in_app_notifications(id) on delete cascade,
  user_id uuid not null,
  fcm_token text not null,
  platform text,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed', 'skipped')),
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists idx_push_notification_outbox_pending
  on public.push_notification_outbox (status, created_at)
  where status = 'pending';

create index if not exists idx_push_notification_outbox_user
  on public.push_notification_outbox (user_id, created_at desc);

alter table public.push_notification_outbox enable row level security;

drop policy if exists push_notification_outbox_service_role_all
  on public.push_notification_outbox;

create policy push_notification_outbox_service_role_all
  on public.push_notification_outbox
  for all
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

create or replace function public.enqueue_push_for_in_app_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  title_text text;
  body_text text;
begin
  if new.user_id is null then
    return new;
  end if;

  payload := coalesce(new.data, '{}'::jsonb)
    || jsonb_build_object(
      'kind', coalesce(new.data->>'kind', 'workflow'),
      'type', new.type,
      'notification_id', new.id::text
    );

  title_text := coalesce(
    nullif(payload->>'title_ar', ''),
    nullif(payload->>'title_en', ''),
    nullif(new.title, ''),
    'موثوق العقاري'
  );

  body_text := coalesce(
    nullif(payload->>'body_ar', ''),
    nullif(payload->>'body_en', ''),
    nullif(new.body, ''),
    title_text
  );

  insert into public.push_notification_outbox (
    notification_id,
    user_id,
    fcm_token,
    platform,
    title,
    body,
    data
  )
  select
    new.id,
    t.user_id,
    t.fcm_token,
    t.platform,
    title_text,
    body_text,
    payload
  from public.user_push_tokens t
  where t.user_id = new.user_id
    and coalesce(t.fcm_token, '') <> '';

  return new;
end;
$$;

drop trigger if exists trg_enqueue_push_for_in_app_notification
  on public.in_app_notifications;

create trigger trg_enqueue_push_for_in_app_notification
after insert on public.in_app_notifications
for each row
execute function public.enqueue_push_for_in_app_notification();
