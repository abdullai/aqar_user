-- تعليقات شورتز العقار: مربوطة بالإعلان وتُحذف تلقائياً عند حذف العقار.
-- نفّذ اختيارياً. التطبيق يعمل بدونها (تخزين محلي احتياطي).

create table if not exists public.property_feed_comments (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint property_feed_comments_body_len
    check (char_length(trim(body)) between 1 and 500)
);

create index if not exists property_feed_comments_property_idx
  on public.property_feed_comments (property_id, created_at desc);

alter table public.property_feed_comments enable row level security;

drop policy if exists property_feed_comments_select_public on public.property_feed_comments;
create policy property_feed_comments_select_public
  on public.property_feed_comments
  for select
  to anon, authenticated
  using (true);

drop policy if exists property_feed_comments_insert_own on public.property_feed_comments;
create policy property_feed_comments_insert_own
  on public.property_feed_comments
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists property_feed_comments_delete_own on public.property_feed_comments;
create policy property_feed_comments_delete_own
  on public.property_feed_comments
  for delete
  to authenticated
  using (user_id = auth.uid());
