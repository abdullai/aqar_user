-- جدول بلاغات المستخدمين على الإعلانات + RLS أساسي للمبلّغ.
-- نفّذ في SQL Editor في Supabase بعد مراجعة أسماء الجداول/المخطط.

create table if not exists public.listing_user_reports (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  reporter_user_id uuid references auth.users (id) on delete set null,
  reason_keys jsonb not null default '[]'::jsonb,
  note text,
  status text not null default 'pending'
    check (status in ('pending', 'reviewing', 'accepted', 'rejected', 'dismissed')),
  created_at timestamptz not null default now()
);

create index if not exists listing_user_reports_property_id_idx
  on public.listing_user_reports (property_id);

create index if not exists listing_user_reports_reporter_idx
  on public.listing_user_reports (reporter_user_id);

alter table public.listing_user_reports enable row level security;

-- إدراج: مستخدم مسجّل فقط، والمبلّغ هو هو (أو null للزائر إن سمحت لاحقاً بسياسة أخرى).
create policy listing_user_reports_insert_own
  on public.listing_user_reports
  for insert
  to authenticated
  with check (reporter_user_id = auth.uid());

-- قراءة: المبلّغ يرى بلاغاته فقط (لوحة الإدارة تستخدم service role خارج RLS).
create policy listing_user_reports_select_own
  on public.listing_user_reports
  for select
  to authenticated
  using (reporter_user_id = auth.uid());

-- حذف: سحب بلاغ معلّق من التطبيق — المبلّغ وحالته pending فقط.
create policy listing_user_reports_delete_own_pending
  on public.listing_user_reports
  for delete
  to authenticated
  using (reporter_user_id = auth.uid() and status = 'pending');
